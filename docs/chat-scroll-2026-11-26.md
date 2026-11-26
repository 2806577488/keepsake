# 聊天流式跟随 v4：根因定位与修复（2026-11-26）

上一版（2026-11-24，见 `chat-scroll-2026-11-24.md`）的结论是「还是跳，方向反过来」，
工程判断没找到触发条件。这一版把触发条件定住了：**不是布局高度变化，也不是
`maxScrollExtent` 估值，而是跟随开关的判定规则写错了**。

## 根因

`chat_screen.dart` 里「要不要继续跟随」是由 `extentAfter`（离底多远）判的：

```dart
// 旧
final bool atBottom = metrics.extentAfter <= _followThreshold; // 80dp
if (atBottom) { if (!_autoFollow.value) _autoFollow.value = true; }
```

三个问题叠在一起：

1. **80dp 的宽容度把「刚上滑一点」也判成还在底部。**
   回复短的时候，整个列表最多只比视口高几十 dp；用户上滑 30dp 想回看开头，
   `extentAfter` 是 30 ≤ 80，照样算「在底部」。于是下一个 token 到达时跟随被重新
   打开，紧接着 `_pinToBottom()` 把人按回去。用户的手指永远赢不了这 100ms 的循环。

2. **`_pinToBottom()` 结尾又把跟随打开一次**（`if (!_autoFollow.value) _autoFollow.value = true;`），
   形成自激回路：贴底 → 判定仍在底部 → 再贴底。这一条让「停下来」在代码上做不到。

3. **拖拽过程中也在 `jumpTo`。** `ScrollPositionWithSingleContext.jumpTo()` 第一步是
   `goIdle()` → `beginActivity(IdleScrollActivity)`，而 `beginActivity` 里有：

   ```dart
   _currentDrag?.dispose();
   _currentDrag = null;
   ```

   正在进行的 `DragScrollActivity` 和它的 `ScrollDragController` 就此作废，
   `Scrollable._drag` 变成 null，之后的手指移动没有对象接收 ——
   列表从「跟手」变成「按着不动」，直到用户抬手重新按下。这就是「界面挪不动」
   的机制（不是视觉错觉）。

另有两个次级跳源（这次一并修）：

- `_scroll.addListener(_onScrollMetricsFromController)` 用 `maxScrollExtent - pixels`
  再判一次「在底部」，同样是 80dp 宽容度，同样是自动重开跟随。
- 通知没有过滤 `depth`：消息里**代码块的横向滚动**也会冒泡到聊天页的
  `NotificationListener`，横滑一下代码块就能改掉跟着/按钮的状态。

## 修复（`lib/features/chat/chat_screen.dart`）

- 跟随的**关闭**只认用户手势：`ScrollStartNotification` / `ScrollUpdateNotification`
  带 `dragDetails`（= 手指发起）的第一时间就 `_autoFollow = false`，**不看距离**。
- 跟随的**开启**只有三个显式入口：
  1. 用户自己把列表拖/甩回最底部（`ScrollEndNotification` 且 `extentAfter <= 4`）；
  2. 点「回到底部」按钮（`_jumpToBottom`）；
  3. 发送新消息（`_send` 之后 `_jumpToBottom(animate: false)`）。
- 布局/内容高度变化（`ScrollMetricsNotification`）**只能开启、不能关闭**，
  且要求 `extentAfter <= 4`（真的在最底部），不再用 80dp。
- 新增 `_dragging`：拖拽期间 `_pinToBottom()` 直接返回，一次 offset 都不改。
- `_pinToBottom()` 不再重开 `_autoFollow`（去掉自激回路）。
- 通知处理加 `depth == 0` 过滤；`maxScrollExtent <= 0`（内容不足一屏）时不动按钮状态。
- 删掉 `_onScrollMetricsFromController` 与 `_followThreshold`，新增 `_followResumeSlop = 4`。

## 为什么没用 `reverse: true`

试算过（上一版文档的「候选终极方案」），结论是**这个场景不比现在好**：

`reverse: true` 的锚点在底部，所以「跟随」确实零代码、零抖动；但反过来，
用户上滑看历史时，底部那条气泡**继续长高会把已有内容整体往上顶**
（offset 从底部量，底部变高 = 上方全部位移），阅读中的位置会持续漂移。
非 reverse 的 offset 从顶部量，底部增长完全不影响上方已读内容 —— 也就是
「用户停下来的地方」天然稳定。这个 App 的关键诉求恰好是后者，所以保留
普通 `ListView`，只把「跟随开关」修对。

真要换 reverse，还需要：`_windowStart` / 「加载更早」的像素补偿重写、
`extentBefore` 与 `extentAfter` 语义对调、`_didInitialPin` 删除。

## 验证（真机，长回答 ≥ 800 词）

1. 流式中不上手：视口应停在最新一行（每 100ms 一次无动画 jump，仍会「步进」，见下节）。
2. 流式中上滑 20~30dp：应**立刻**停住，不再被拽回；出现「回到底部」按钮。
3. 上滑期间继续输出：视口不动（内容在下方长高）。
4. 拖拽中松开再按住拖动：手感应连续，不再「按住却不动」。
5. 点「回到底部」：平滑回到底部，之后重新跟随。
6. 上滑到顶，点「加载更早消息」：屏幕上的那条内容不应跳动（原有像素补偿保留）。

## 仍未解决（下一轮再看）

- **跟随时的步进感**：`chat_controller` 的 `_notify` 节流是 100ms，跟随也是 100ms
  一次无动画 `jumpTo`，所以视口是 10Hz 阶跃。想更顺，要么把通知节流降到 ~33ms
  （UI 成本要测），要么跟随改成短动画（历史上试过，会被重定向打断而抖动）。
- **流结束瞬间**：纯文本 → `KeepsakeMarkdown` 一次性排版 + 气泡 `minWidth` 由
  `bubbleMax` 收回内容宽度，气泡高度会变一次。这是「结束时跳一下」的来源，
  与跟随无关；如果用户仍报这个，再单独处理（例如结束后保持流式宽度 300ms）。

## 追加（2026-11-26 晚）：按钮版式

「回到底部」不再单独占一行。原实现放在列表与芯片之间，虽然不压字，但会空出一条横带、
还挤掉消息区一截高度（用户实测原话"整一行也盖我文字"）。现在挪进 `_ComposerTools`
所在 `Row` 的最右端，和三个工具芯片**同一行**、右对齐，只在离开底部时出现。

设计库已同步（v3.8）：`SPEC.md` §4.10 改按钮位置并补「拖拽期间不许改 offset」硬规则；
`docs/CHECKLIST.md` §27 加两条验收；`reference/full-chat.html` 的 `chips()` 支持
`goBottom`、`full.css` 的 `.gobottom` 去掉 `position:absolute`。
