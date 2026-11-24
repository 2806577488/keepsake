# 聊天流式跟随：迭代记录与未决问题（2026-11-24）

## 现状（未决）

用户实测：**还是跳，但方向反过来了。**

- v1 症状：流式时反复回到「输入框下方」（= 助手气泡顶部），看不到后面输出/思考，上滑被拽回。
- v2 症状（当前）：跳的方向相反（倾向于是"往底部/最新行方向"的跳动），仍然影响阅读。

工程判断：两版都没找到真正的触发条件。v2 已把最可疑的一层（`ScrollablePositionedList` 的
懒加载估值 + `alignment: 1`）去掉，换成普通 `ListView` + `jumpTo(maxScrollExtent)`；如果仍跳，
说明触发源在**别处**（布局高度变化 / 键盘 / 用量条出现 / Markdown 结束重排 / 跟随定时器竞争）。

## 已做过的修改（按时间）

1. **v3.5 之前**：`ScrollablePositionedList` + 每 60ms 全量通知 + 每帧 `jumpTo(alignment: 1)`。
2. **第一次修**：跟随节流 150ms、120ms 平滑动画、`_onPositionsChanged` 用「最后一条是否可见」
   判定在底部。
3. **第二次修**：判定改 `extentAfter ≤ 80dp`；仅用户拖动才停止跟随；按钮移出列表浮层；
   流式中气泡锁宽；通知间隔 100ms；贴底改无动画 jump。
4. **第三次修（当前）**：消息列表换普通 `ListView` + `ScrollController`；
   `_pinToBottom() = position.jumpTo(maxScrollExtent)`；「加载更早」用 max 增量补偿 pixels；
   删除 SPL 依赖与按条目对齐代码。

## 下一步排查计划（如果用户再反馈）

1. `adb shell screenrecord --time-limit 10 /sdcard/s.mp4` 录流式过程，抽帧比对
   「气泡顶边 y 坐标」和「scroll offset」两条曲线，确认是**内容高度突变**还是**offset 被改**。
2. 在 `_pinToBottom` / `_onMetricsChanged` / `_scheduleFollow` 三处打时间戳日志，看谁在改 offset。
3. 怀疑点（按可能性排序）：
   - 流式结束：纯文本 → Markdown 一次性排版，气泡高度变化 → offset 看起来"跳"；
   - 键盘弹出/收起：viewport 高度变 → maxScrollExtent 变 → 贴底逻辑触发；
   - 「用量条」出现/隐藏（现在常显，但首次数据到达会重排一次）；
   - 跟随定时器与用户手势竞争（100ms 窗口内）。
4. 候选终极方案：`reverse: true` 的 ListView（底部天然锚定，不需要任何贴底代码），
   代价是「加载更早」和「滚动到指定消息」要重写；若上面的日志证明是 offset 被改，直接换。

## 复现条件（给下次的自己）

- 真 Key（DeepSeek flash），长回答（≥800 词）→ 内容超过视口；
- 流式中观察：视口是否停在最新一行；上滑后是否保持；
- 结束后观察：是否在 Markdown 重排瞬间跳动。
