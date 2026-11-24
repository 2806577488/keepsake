# Keepsake（留声）设计 Token

> **结论先行**：这套 UI 只有一个颜色种子 —— `#2F6B5F`（深青绿），其余所有颜色都由 Material 3 的 `ColorScheme.fromSeed` 算法推导；字号、字重、行高除少数几处行高覆盖外，全部是 Material 3 默认排版。
> 所以设计师真正要「定」的不是一堆色值，而是**这 1 个种子色 + 圆角尺度 + 间距节奏 + 几个自定义数值**（见 §7）。

**来源文件**（相对工程根 `Z:\dsh-restore\keepsake`）：

| 内容 | 文件 |
| --- | --- |
| 全部配色 / 排版 / 组件主题 | `lib/core/theme.dart` |
| Markdown 与代码块样式 | `lib/core/theme.dart`（`keepsakeMarkdownStyleSheet`）+ `lib/features/chat/widgets/markdown_view.dart` |
| 气泡、芯片、输入栏等局部硬编码 | `lib/features/chat/chat_screen.dart` |
| 会话行、分割线缩进 | `lib/features/sessions/sessions_screen.dart` |
| 分区标题、进度条 | `lib/features/settings/settings_screen.dart` |

**色值取值说明**（重要，避免误读）：

- 标「**采样**」的十六进制值，是从真机截图（`screenshots/list-now.png`、`screenshots/codeblock-new.png`）逐像素取的平均值，浅色模式、Android 13、1080×2400。可以直接拿去对稿。
- 标「**推导**」的是 Material 3 按 seed `#2F6B5F` 生成的同一族颜色，截图里没取到（深色模式、error、outline 等）。**深色模式整套尚未采样**，出图后建议回采校准。
- 工程里**没有**任何自定义色值（全 `lib/` 只有 mermaid 用了一次 `Color(0x00000000)` 透明），也没有自定义字体（`pubspec.yaml` 没声明 `fonts:`）。等宽用的是系统族 `monospace`。

---

## 1. 颜色

### 1.1 基础角色（浅色）

| 角色 | 用途（出现位置） | 浅色值 | 来源 |
| --- | --- | --- | --- |
| `seed` | 唯一色种，所有颜色的源头 | `#2F6B5F` | 自定义（`KeepsakeTheme.seedColor`，源码注释里标注为「推断」） |
| `primary` | 顶栏强调文字（「搜索结果」标题、分区标题）、链接、已复制的勾、联网搜索图标、聚焦边框、全选按钮 | `#046B5C` | 采样（来自填充按钮/图标） |
| `onPrimary` | `primary` 上的文字 | `#FFFFFF` | 推导 |
| `primaryContainer` | **用户气泡底**、FAB 底、选中态芯片底、助手头像底、空态图标底、置顶头像底 | `#A0F2DF` | 采样 |
| `onPrimaryContainer` | 用户气泡文字、选中芯片文字/图标、FAB 文字 | `#005045` | 采样 |
| `surface` | 页面底、AppBar 底、输入栏底 | `#F5FBF7` | 采样 |
| `surfaceContainerLow` | 卡片底、**助手气泡底**、未选中芯片底、表格单元格底 | `#EFF5F2` | 采样 |
| `surfaceContainerHigh` | 对话框底、底部弹层底、**代码块标题栏**、导入进度横幅底、搜索结果 pill 底、回到底部圆钮底 | `#E3EAE6` | 采样 |
| `surfaceContainerHighest` | **输入框填充**、头像底、代码块底、思考过程展开底（50% 不透明） | `#DEE4E1` | 采样 |
| `onSurface` | 主正文 | `#191C1B` | 推导（近黑） |
| `onSurfaceVariant` | 次要文字：相对时间、消息数、提示语、思考标签、代码块语言名、工具芯片默认态 | `#496F66` | 采样 |
| `outline` | 空态大图标、未选项圆圈、小字 token 数 | `#7C8B86` | 推导 |
| `outlineVariant` | 分割线、卡片/芯片描边、代码块边框（60% 不透明）、输入框默认边框 | `#CAD1CD` | 采样 |
| `error` | 错误条图标、删除按钮/删除文字、「这条回答中断了」 | `#BA1A1A` | 推导（Material 3 默认红） |
| `onError` | `error` 上的文字 | `#FFFFFF` | 推导 |
| `errorContainer` | **错误条底**、左滑删除露出的底、录音中按住说话底 | `#FFDAD6` | 推导 |
| `onErrorContainer` | 错误条文字/图标 | `#410002` | 推导 |
| 遮罩 | 对话框/底部弹层背后的 scrim | `#000000` @ 54% | 采样验证（`t-backfill2.png` 为 `#707371`，即 `surface` 压 54% 黑） |

### 1.2 合成色（运行时算出来、不能当 token 用）

| 表达 | 实际效果 | 浅色实测 |
| --- | --- | --- |
| `surfaceContainerHighest` @50% | 「本会话 占用 …」用量条底 | `#E9EFEC` |
| `outlineVariant` @60% | 代码块边框、输入栏顶边 | 混入 `surface` |
| `error` @60% | 出错气泡描边 | 混入气泡底 |
| `primary` @40% | 选中芯片描边 | 混入芯片底 |
| `primary` @60% | Markdown 引用块左侧 3px 竖线、链接下划线 | — |
| 深色代码块底 | `surfaceContainerHighest` 压 `black` 18% | — |

### 1.3 语义映射规则（**不要改**）

- 用户内容 = `primaryContainer`；助手内容 = `surfaceContainerLow`。两者**必须**保持「有色 / 无色」的对照，这是全 App 唯一的「谁在说话」线索（气泡无名字、无图标区分外）。
- 可破坏性操作（删除、清空记忆）= `error` + `errorContainer`，不允许换成品牌绿。
- 进度/成功等中性信息用 `surfaceContainerHigh`，不用彩色，避免和「选中态」抢注意力。
- 「选中」= `primaryContainer` 底 + `primary` 40% 描边 + 字重加粗，三者同时出现；只改其中一项会削弱可辨识度。

---

## 2. 排版

### 2.1 字体族

| 用途 | 字族 | 来源 |
| --- | --- | --- |
| 全部正文/标题 | 系统默认（Android 上是 Noto Sans CJK / Roboto） | Material 3 默认，未自定义 |
| 代码、等宽 | `monospace`（`KeepsakeTheme.monoFontFamily`） | 自定义常量 |

没有引入自定义字体文件 —— 如果设计师要换字体，需要新增 `pubspec.yaml` 的 `fonts:` 段，这属于**新增依赖**，请单独确认。

### 2.2 字号 / 字重 / 行高

Material 3 默认排版，代码**只覆盖了 `bodyMedium` 和 `bodyLarge` 的行高（→ 1.45）**，字号/字重都是规范值。

| 角色 | 字号 | 字重 | 行高 | 字距 | 用在哪 |
| --- | --- | --- | --- | --- | --- |
| `titleLarge` | 22 | w600 | 1.27 | 0 | AppBar 标题（列表页「留声」、设置页「设置」）；字重是自定义覆盖 |
| `titleMedium` | 16 | w600 | 1.5 | 0.15 | 会话行标题、聊天页顶栏会话名、空态「还没有会话」「问点什么」；字重覆盖 |
| `titleSmall` | 14 | w500 | 1.43 | 0.1 | 「搜索结果（N）」弹层标题 |
| `bodyLarge` | 16 | w400 | **1.45**（覆盖） | 0.5 | 搜索输入框、思考强度选项标题 |
| `bodyMedium` | 14 | w400 | **1.45**（覆盖） | 0.25 | **正文默认**：消息气泡、列表副标题、对话框正文、提示语 |
| `bodySmall` | 12 | w400 | 1.33 | 0.4 | 思考过程正文、进度条下方说明、错误条文字、小字提示 |
| `labelLarge` | 14 | w700（覆盖） | 1.43 | 0.1 | **设置页分区标题**（primary 色）；字重覆盖 |
| `labelMedium` | 12 | w500 | 1.33 | 0.5 | 「N 个网页」pill、错误条「重试」 |
| `labelSmall` | 11 | w500 | 1.45 | 0.5 | **工具芯片文字**、代码块语言名（另加 `letterSpacing 0.6`）、思考过程标签、token 数 |

### 2.3 局部自定义字号（硬编码，不在主题里）

| 元素 | 值 | 位置 |
| --- | --- | --- |
| 代码块代码 | **12.5 / 行高 1.55 / `monospace`** | `markdown_view.dart` `_CodeBlockState` |
| Markdown 行内代码 | 13 / 行高 1.45 | `theme.dart` `keepsakeMarkdownStyleSheet` |
| Markdown 段落 | 继承 `bodyMedium`，**行高 1.6** | 同上 |
| 用户气泡正文 | `bodyMedium`，**行高 1.5** | `chat_screen.dart` `_MessageBubble` |
| 思考过程正文 | `bodySmall`，**行高 1.5** | `_ThinkingPanel` |
| 代码块语言名 | 11 / w500 / 字距 0.6 | `_CodeBlockState` |

> 设计提示：正文行高实际是 1.45（不是 Material 默认 1.43），Markdown 段落 1.6，用户气泡 1.5 —— 三种行高混用，中文密排时建议统一到 1.5 或 1.6 二选一。

---

## 3. 间距

间距以 2 的倍数为主，主力值 4 / 6 / 8 / 10 / 12 / 16 / 20 / 24。**没有全局 spacing token**，都是在各 widget 里写死的。

| 场景 | 值 | 位置 |
| --- | --- | --- |
| 页面左右留白（消息列表） | 12 | `_buildMessageList` |
| 消息列表上下留白 | 10 | 同上 |
| 气泡内边距 | 12 / 10 / 12 / 10 | `_MessageBubble` |
| 气泡之间垂直间距 | 上 6，下 2（同一条的尾巴处 6） | `_MessageBubble` |
| 助手头像与气泡间距 | 6，头像距气泡顶 2 | `_MessageBubble` |
| 气泡最大宽度 | 屏宽 **86%** | `_MessageBubble` |
| 助手操作行缩进 | 左 30 | `_MessageBubble` 底部行 |
| 输入栏内边距 | 8 / 4 / 8 / 8 | `_InputBar` |
| 输入框内边距 | 14 / 12 | `_InputBar` |
| 工具行高度 | 36（横向滚动） | `_ComposerTools` |
| 工具行左右留白 | 10 | `_ComposerTools` |
| 芯片内边距 | 10 / 6，芯片间距 6 | `_ToolChip` |
| 设置页分区标题 | 16 / 20 / 16 / 6 | `_SectionTitle` |
| 列表行内容边距 | 16 / 2（ListTile 主题） | `theme.dart` |
| 列表底部留白（给 FAB 让位） | 88 | `sessions_screen` |
| 会话行分割线缩进 | 72（搜索命中行 56） | `sessions_screen` |
| 代码块外边距 | 上下各 10 | `_CodeBlockState` |
| 代码块内边距 | 12 | 同上 |
| 代码块标题栏高度 | 34 | 同上 |
| 空态留白 | 32（聊天空态水平 32 / 垂直 24） | `_EmptyState` / `_EmptyChat` |

---

## 4. 圆角

| 元素 | 半径 | 来源 |
| --- | --- | --- |
| 卡片 `Card` | 16 | 主题 |
| 对话框 | 20 | 主题 |
| 底部弹层（顶部） | 24 | 主题 |
| 输入框 / 按住说话条 | 14 | 主题 + 局部重复声明 |
| 填充按钮 | 12 | 主题 |
| `ListTile` | 12 | 主题 |
| SnackBar | 12 | 主题 |
| 芯片 `Chip` | 10 | 主题 |
| **消息气泡** | 16，但「尾巴」那个角 **4**（用户右下、助手左下） | `_MessageBubble` 自定义 |
| 工具芯片 | 14 | `_ToolChip` 自定义 |
| 代码块容器 | 12 | 自定义 |
| 思考过程展开块 | 8 | 自定义 |
| 本会话用量条 | 10 | `session_usage_bar.dart` |
| 搜索结果 pill | 14 | `_SearchSourcesView` |
| 回到底部圆钮 | 圆形 36×36（紧凑分支 26×26） | `_ArrowButton` |

> 两套圆角体系并存：**16 系**（卡片/气泡）和 **12/14 系**（输入、芯片、代码）。设计师如果要统一，建议保留气泡 16（视觉重心），把输入/芯片/代码统一到 12。

---

## 5. 阴影 / elevation

| 元素 | elevation | 说明 |
| --- | --- | --- |
| `Card` | 0 | 主题明确置 0，靠底色分层，不靠阴影 |
| AppBar | 0；滚动时 1（`scrolledUnderElevation`） | 主题 |
| 回到底部圆钮 | 2（紧凑分支 0） | `_ArrowButton` |
| FAB / 对话框 / 底部弹层 | Flutter Material 3 默认，未覆盖 | — |

**整体是「无阴影 + 底色分层」的扁平路线**：层次由 `surface` → `surfaceContainerLow` → `surfaceContainerHigh` → `surfaceContainerHighest` 的明度差表达。设计师若要加投影，建议只给浮层（弹层、FAB）加，不要给卡片和气泡加。

---

## 6. 动效

| 场景 | 时长/曲线 | 位置 |
| --- | --- | --- |
| 滚到某条消息 | 220 ms | `chat_screen._scrollToIndex` |
| 流式跟随到底部 | 120 ms | `_followBottomSmooth` |
| 跟随节流窗口 | 150 ms（合并同一窗口的多次滚动） | `_followInterval` |
| 流式刷新通知节流 | 60 ms | `chat_controller` |
| 进入/退出语音模式 | 120 ms | `voice_button.dart` |
| 代码块「已复制」回弹 | 2 s 后复位 | `_CodeBlockState` |
| 导入批量写库的让出间隔 | 300 ms / 批次 | `core/import/import_task.dart` |
| 批量删除的让出节奏 | 每 8 条让一次事件循环 | `sessions_screen._deleteSelected` |
| **工具芯片按压态**（v3.1） | 120 ms，`high` 底 ↔ 透明底 | `chat_screen._ToolChip` |

> **按压态的总规矩（v3.1 起）**：可点的元素只允许用「底色档位（`surface` → `low` → `high`）」或透明度表达按下；**不允许** Material 默认的灰色 `highlightColor` / 水波纹。原因：Ink 是按**触摸框**（48dp）画的，而视觉本体只有 32dp，那一圈多出来的灰色矩形在浅色皮肤上非常显眼，用户看到的就是「点一下闪一块灰」。芯片类组件一律 `splashFactory: NoSplash.splashFactory` + 自绘按压底。

没有自定义 `Curve`（全用默认 `Curves.easeInOut` 系）。没有页面转场定制，全走 `MaterialPageRoute` 默认。

---

## 7. 硬编码数值清单（设计师会想改、但代码里没有 token）

| 值 | 含义 | 备注 |
| --- | --- | --- |
| `#2F6B5F` | 唯一色种 | 改它 = 整套配色变 |
| `12.5` / `1.55` | 代码字号 / 行高 | 偏小，长代码阅读吃力 |
| `34` | 代码块标题栏高度 | 复制按钮正好 34×34 |
| `0.86` | 气泡最大宽度 | 屏宽占比 |
| `12000` | 单条正文走 Markdown 的字数上限（超过先纯文本） | 性能兜底，**不能随意调大** |
| `120` | 搜索命中片段截断字数 | — |
| `72` / `56` | 分割线缩进 | 和头像/图标对齐 |
| `88` | 列表底部留白 | 给 FAB 让位 |
| `1.45` / `1.5` / `1.6` | 三种正文行高 | 建议收敛 |
| `0.54` | 遮罩不透明度 | Flutter 默认 `black54` |

---

## 8. 给设计师的改造边界

**可以自由改（不影响逻辑）**

- `#2F6B5F` 种子色（改完所有角色自动重算，但请保证 `primaryContainer` 与 `surfaceContainerLow` 的明度差 ≥ 8%，否则「用户/助手」分不出来）。
- 圆角尺度、间距节奏、字重、按钮形状、图标风格（现全部是 Material Symbols 轮廓系）。
- 阴影策略、动效时长与曲线。
- 代码块的高亮主题（现为 `atom-one-light` / `atom-one-dark`，只要不是荧光色即可 —— 之前用过 github 那套被否过）。

**不能改（改了就坏逻辑或坏性能）**

- 语义映射：用户 = `primaryContainer`，助手 = `surfaceContainerLow`，删除 = `error`。
- 代码块**必须**允许横向滚动、不换行不裁剪（长行是硬需求）。
- 单条正文超 12k 字必须先纯文本渲染（否则 ANR，真机实测过 9.9 s/帧）。
- 消息气泡长按必须能唤出菜单（复制/编辑/重生成/删分支都挂在这里）。
- 工具芯片的**长按 = 改思考强度**，这个隐藏操作不能被视觉改动弄丢（详见 `ui-logic.md` §3.9）。
