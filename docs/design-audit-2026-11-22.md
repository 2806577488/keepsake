# Keepsake 实际渲染 × 设计交付包 对照审计

- 日期：2026-11-22 23:44
- 交付包基准：`Z:\dsh-restore\ui-handoff\keepsake-ui-handoff\`（README 1.0 / `specs/screens.md` 22 帧 / `design/tokens.json` / `design/components.md` / `flutter/theme_snippet.dart`）
- 实测基准：`Z:\dsh-restore\logs\audit-list.png`、`audit-chat.png`、`audit-settings.png`（1080×2400，420dpi，411dp 宽）
- 证据方法：逐像素量取 + 源码定位。**1dp = 2.625px**（用独立已知量反推并交叉验证：芯片高 44dp=115px、助手头像 28dp=73px、代码块头部 34dp=89px、代码行距 12.5×1.6dp=52.5px 实测 53px）。
- 本报告只读审计，**未修改任何代码或设计文件**。

> 截图可用性：三张截图都成功打开且都是目标页面（列表 / 聊天 / 设置）。但聊天页只裁到「回复正文中段」，设置页只滚到「对话默认」中部，因此消息操作行、停止键、错误条、空态、弹层、后台任务区等**不在画面内**，这些项用源码判定并单列在第 4 节。

---

## 1. 结论摘要（按用户可感知程度排序）

1. **颜色与气泡/代码块结构是达标的**。用户气泡 `#A0F2DF`、助手气泡 `#EFF5F2`、思考块、代码块头部（`alphaBlend(primary 7%, surface)` = `#E4F1EC`）、代码区白纸（`#F5FBF7`）全部与 token 逐像素一致；代码块**已真正通栏出血**（头部横向 126→1048px，正好等于气泡内缘宽度），34dp 头、12.5/1.6 代码字、横向不换行也都对上了。这块不用再改。
2. **排版层级整体错位是最需要处理的一类**：列表/设置 AppBar 标题实测只有约 **14dp**（两字宽 68px、墨高 33px），**比 16dp 的行标题还小**，而设计是 22dp——页面没有主标题；同时全站 `ListTile` 副标题实测约 15dp（设计 12），把列表行撑到 77dp（设计 68）、设置行撑到 76dp（设计 52）。一「该大的小了、该小的大了」，合起来就是「元素注意力平均、页面发松」。
3. **聊天工具芯片行多了一层**：设计只有 3 个芯片、附件并入「+」按钮；实际有 4 个，第 3 个「上下文：最近 20 轮」已经顶到屏幕右缘（x≈1038/1080），第 4 个「添加附件」被挤出屏幕，只能横滑才能看见，且和输入栏左侧「+」入口重复。
4. **错误条仍可能直出英文异常原文**（B5 硬验收「不得直出异常原文」未满足）：只有 `ApiError` 有中文文案，其它异常 `error.toString()` 原样进横幅，例如设计文档点名的 `device or resource busy`。
5. **设置页「删除平台」不是红色**（实测图标像素 `#3F4946`，非 `error #BA1A1A`），违反 README 验收「删除类一律 error」。
6. **会话列表元信息反了**：设计「12 轮 · 今天 10:41」，实际「54 分钟前 · 2 个对话」——时间与轮数顺序互换，且「个对话」统计的是消息条数，不是轮次。

---

## 2. 逐项对照表

合计 **19 条**：致命 1 · 明显 6 · 细节 12。差异等级：**致命** = 违反硬验收/会误导用户且必须改；**明显** = 一眼能看出的层级/结构偏差；**细节** = 尺寸或令牌级别的收口。

### A. 会话列表（`audit-list.png`）

| 帧/元素 | 设计规格 | 实际（截图/代码证据） | 差异等级 | 代码位置 | 修法 |
| --- | --- | --- | --- | --- | --- |
| A1 AppBar 标题「留声」 | `titleLarge` 22 / w600（tokens §type；E-spec） | 实测字形墨高 33px、两字宽 67px ⇒ 约 **14dp**，**比 16dp 的行标题还小**（行标题实测 16dp 已正确）。源码标称 22 ⇒ 截图与当前源码明显不一致，优先怀疑构建产物陈旧或主题未生效 | 明显 | `lib/core/theme.dart:91-99`（`appBarTheme.titleTextStyle = titleLarge`）、`lib/features/sessions/sessions_screen.dart:662` | 先重建一次再复测；若仍为 14–16，直接在 `AppBar(title: Text('留声', style: theme.textTheme.titleLarge))` 显式指定 22/w600 |
| A1 行副标题 | 12 / `onSurfaceVariant`，格式「N 轮 · 时间」（components §1） | 实测 ink 37px ≈ **15dp**（`bodyMedium`），文案「54 分钟前 · 2 个对话」：顺序、单位、时间粒度全不符 | 明显 | `sessions_screen.dart:845-849` | `subtitle: Text(..., style: textTheme.bodySmall)`；文案改「${轮数} 轮 · ${绝对时间}」。轮数需由 `messageCount/2` 推导或读会话轮次字段 |
| A1 行高 / 分割线缩进 | 行高 68（标题一行）/76（两行）；分割线缩进 64 | 实测相邻分割线间距 202px = **77dp**；分割线起点 x=189px = **72dp** | 细节 | `sessions_screen.dart:786-792`（`indent: 72`）、`theme.dart:145-148`（ListTile contentPadding） | `indent: 64`；用 `visualDensity`/`minVerticalPadding` 或自定义行把行高收到 68（副标题降到 12 后自然回落 ~10dp） |
| A1 行内条目 | 头像 40 圆 + ⋮ 44×44；⋮ 多选态隐藏 | 实测头像 105px=**40dp**、左起 16dp；⋮ 44dp；多选态隐藏（代码） | 已相符 | `sessions_screen.dart:820-857` | — |
| A1 FAB | 56 高、`primaryContainer`、「新对话」 | 实测高 146px=**55.6dp**、`#A0F2DF`、右/下均 16dp + 导航条 inset | 已相符 | `sessions_screen.dart:707-719` | — |
| A5 空态（代码） | 64 图标 +「还没有会话」+ 一行引导，**不再重复放新对话按钮** | 代码一致（64 / `titleMedium` / 一行说明），且注释明确删掉了重复按钮 | 已相符（截图未覆盖） | `sessions_screen.dart:1217-1250` | — |

### B. 聊天页（`audit-chat.png`）

| 帧/元素 | 设计规格 | 实际（截图/代码证据） | 差异等级 | 代码位置 | 修法 |
| --- | --- | --- | --- | --- | --- |
| B5 错误条文案 | **必须中文摘要，不得直出异常原文**（specs B5 验收）；最多 3 行 | 横幅直接渲染 `state.error`。`_errorMessageOf` 只对 `ApiError` 取中文 `message`，其余返回 `error.toString()`（去掉 `Exception: ` 前缀），`FileSystemException` 之类会出英文原文 | 致命（需真实失败才能看见） | `lib/features/chat/chat_screen.dart:3129-3189`（3159 行直接渲染）、`chat_controller.dart:2236-2249` | 增加中文分类映射：网络 / 超时 / 中断 / 文件被占用 / 权限 / 未知；原文收进「详情」可展开，不进主文案 |
| B2 工具芯片行 | 3 个芯片：`联网搜索 关/开`、`深度思考 关/中/高`、`上下文 20 轮`；高 44；**新增附件芯片并入「+」，不再占一行**（E-spec 改动清单） | 实际 4 个芯片：`联网搜索：关`、`深度思考：关`、`上下文：最近 20 轮`、`添加附件`。第 3 个右缘 x≈1038（屏宽 1080），第 4 个完全在屏外 | 明显 | `chat_screen.dart:2519-2565`（四个 `_ToolChip`，`2551-2565` 为第 4 个）、文案 `2521/2532/2543-2545` | 删掉第 4 个「添加附件」芯片（输入栏已有「+」）；标签去掉冒号，恢复设计措辞；确认「深度思考」开启时带档位 |
| B2 用户气泡内边距 | 12 / 10 / 12 / 10（components §2） | 实测左右各 10dp（文字左缘 = 气泡左缘 + 10dp） | 细节 | `chat_screen.dart:1546-1555`、`widgets/markdown_view.dart:367`（`pPadding` 10） | 统一改 12（注意代码块要维持左右 0 出血，只改正文块的横向 padding） |
| B2 气泡配色/圆角/最大宽 | 用户 `primaryContainer`、助手 `surfaceContainerLow`；16/尾角 4；86% | 逐像素一致：`(160,242,223)`、`(239,245,242)`；助手气泡实测 923px = 351.6dp ≈ 86% 屏宽（411dp）；圆角 16/4 | 已相符 | `chat_screen.dart:1487-1496, 1622-1629` | — |
| B2 助手头像 | 设计任务口径：气泡外 28dp、右间距 8、`primaryContainer` | 实测 73×73px=**28dp**，左 12dp、与气泡间距 22px=**8.4dp**，底色 `#A0F2DF`（注：`components.md` 写 24，与任务口径 28 冲突，本次按 28 判相符） | 已相符 | `chat_screen.dart:1694-1710` | — |
| B2 消息正文 | 15 / 1.6 | 实测每行 23 个汉字、字步进 ≈37.6px=14.3dp ⇒ 15dp；基线间距 ≈63px=24dp=15×1.6 | 已相符 | `theme.dart:85-89`、`markdown_view.dart:361-368` | — |
| B4 思考折叠条 | 44 高、`surfaceContainerHighest @ 50%`、圆角 8、左 chevron、右「展开」`primary` 11 | 实测高 116px=**44dp**、色 `(230,236,233)`（= 50% highest 叠在气泡低面上，公式正确）、圆角 8、右侧「展开」用 primary | 已相符（文案见下行） | `chat_screen.dart:1833-1904` | — |
| B4 思考耗时文案 | 「思考过程（12.3 s）」 | 拼接为 `（21.6s）`，数字与 `s` 之间无空格 | 细节 | `chat_screen.dart:1837-1841` | 改 `'思考过程（${seconds.toStringAsFixed(1)} s）'` |
| B4 展开体左竖线 | 2px `outlineVariant`（components §4） | 代码用 `scheme.primary` 2px | 细节（展开态，截图未覆盖） | `chat_screen.dart:1905-1922`（1913 行） | 改 `scheme.outlineVariant`（若要保留品牌感，应与设计确认后再改，不要自定） |
| B7 代码块结构 | 通栏出血（贴气泡内缘）、无外框无圆角；头部 34 淡青；1px 分隔线；代码区白纸 + padding 12；12.5/1.6；横向滚动不换行；复制热区 44×34 | 实测：头部 x **126→1048**＝气泡内缘等宽（真通栏）；高 89px=**34dp**；色 `(228,241,236)` = `alphaBlend(primary 7%, surface)`；代码区 `#F5FBF7`；首行文字 x=158（=气泡左缘+12dp）；行距 53px=20dp=12.5×1.6；无折行 | 已相符 | `markdown_view.dart:689-770` | — |
| B2 输入栏 | 44 高（1 行）、`surfaceContainerHighest`、圆角 14、发送 44 圆 | 实测输入框高 129px≈**49dp**（1 行态）；其余相符；「+ / 麦克风 / 发送」布局与设计一致 | 细节 | `chat_screen.dart:2862-2892`（`contentPadding` 垂直 12 + `isDense`） | 垂直 padding 收到 10，或固定 `constraints.minHeight = 44` |
| B2 用量条 | 位置 AppBar 下方左对齐；**占用 <80% 不出现**；文案「本会话 占用 X% · 缓存命中 Y%」 | 截图中未出现（符合预期）；代码阈值 `_showThreshold = 80`，无数据也隐藏；文案模板一致 | 已相符 | `chat_screen.dart:3087-3125`、`session_usage_bar.dart:55-63` | — |

### C. 设置页（`audit-settings.png`）

| 帧/元素 | 设计规格 | 实际（截图/代码证据） | 差异等级 | 代码位置 | 修法 |
| --- | --- | --- | --- | --- | --- |
| D1 AppBar 标题「设置」 | `titleLarge` 22 / w600（与列表页同一规则） | 实测两字宽 68px、墨高 32px ⇒ 与列表页同样约 **14dp**，与行标题（16dp）几乎同号 | 明显（与 A1 同一根因） | `settings_screen.dart:359`（`AppBar(title: const Text('设置'))`，样式来自 `theme.dart:91-99`） | 与 A1 一起修，不要分两处改 |
| D1 行副标题 / 行高 | 副标题 12 / `onSurfaceVariant`；行最小 52 | 实测「系统提示词」标题 ink 39px（16dp ✓）、副标题 ink 38px ⇒ **≈15dp**；相邻行标题基线间距 199px = **76dp** | 明显 | `settings_screen.dart:368-441`（ListTile 未设 `subtitleTextStyle`，落到 `bodyMedium` 15） | 在 `ThemeData` 里给 `listTileTheme.subtitleTextStyle = bodySmall(12/1.5)`，行高随之下落到 52–56 |
| D1 删除类颜色 | 删除类一律 `error`（README 验收；components §10 危险行） | 「AI 平台」行 trailing 的垃圾桶图标实测 `(63,73,70)`（默认 `onSurfaceVariant`），不是 `#BA1A1A`；旁边的「编辑」也是同色，两者视觉无差别 | 明显 | `lib/features/settings/provider_section.dart:152-166`（162 行无 color） | `color: theme.colorScheme.error`；更稳的做法是把「编辑/删除」收进 ⋮ 菜单，行尾只留 chevron（与设计 D1 一致） |
| D1 分区标题 | `labelLarge` 700 `primary`，内边距 **24 / 16 / 8** | 字号 14/w700/`#046B5C` 全对；实测左内边距 **16dp**、上 20、下 6 | 细节 | `settings_screen.dart:600-619`（610 行 `fromLTRB(16, 20, 16, 6)`） | 改 `fromLTRB(24, 16, 24, 8)` |
| D1 行分隔线 | 每行下 1px `surfaceContainerLow`，左右 16 | 实测 x=1040 列从 400→900px 无任何颜色变化 ⇒ **没有行分隔线** | 细节 | `settings_screen.dart:361-492`（ListView children 未插入 Divider） | 每行后加 `Divider(height: 1, thickness: 1, color: surfaceContainerLow)`，或用 `ListView.separated` |
| D1 行前导图标 | D1 帧中行内**无图标**，标题起于 16dp | 每行左端都有 24dp 图标（tune / compress / psychology / lightbulb / globe / sparkle / smiley / persona），标题缩进到 ≈58dp | 细节 | `settings_screen.dart:369/379/385/391/399/407/415/423`（`leading` / `secondary`） | 去掉 `leading`/`secondary`，回到「纯文字 + 右侧取值」的设计形态（AI 平台行保留头像/状态标记除外） |
| D1 开关 | 44 × 24，选中 `primary` | 实测 ON 态绿轨道 135×83px = **51.4 × 31.6dp**（M3 默认 52×32） | 细节 | `settings_screen.dart:390-429`（`SwitchListTile` 未定制尺寸） | `switchTheme` 用 `SwitchThemeData(thumbColor/trackOutline…)` + `Transform.scale`/自定义 44×24 轨道 |
| D1 危险行 | 危险操作单独红字行 | 「清空记忆数据」图标与文字均为 `error`，副标题保留说明 | 已相符 | `settings_screen.dart:430-441` | — |
| D2/D3 后台任务 | 存在；**只显示不启动**；空态仅一句「没有正在运行的后台任务」+ 说明入口在哪 | 代码存在「后台任务」分区，只 watch 进度不启动；空态只有一句，**缺「入口在哪」的说明行** | 细节（截图未覆盖） | `settings_screen.dart:449-450, 507-560`（548-557 空态） | 空态补一行：「导入在『数据 › 导入历史对话』启动，补建在会话列表启动」 |
| D1 检查更新 | （交付包未列帧，任务要求核查是否存在且文案合理） | 代码存在：`关于` 区 `_UpdateTile`，标题「检查更新」，副标题「当前版本 x.y.z」/「发现新版本 x.y.z」，点按有检查/下载/安装流程 | 相符（截图未覆盖） | `settings_screen.dart:488-490, 924-946` | — |

### D. 全局令牌

| 帧/元素 | 设计规格 | 实际（截图/代码证据） | 差异等级 | 代码位置 | 修法 |
| --- | --- | --- | --- | --- | --- |
| 分割线颜色 `outlineVariant` | `#CAD1CD`（tokens.json sampled） | 会话列表分割线实测 `(190,201,197)` = `#BEC9C5`，比 token 更饱和一档；同页 `primary`、`primaryContainer`、`surface*` 却与 token 完全一致 | 细节 | `theme.dart:71-74`（`ColorScheme.fromSeed` 直出）、`theme.dart:149-153` | 显式覆盖 `outlineVariant`（及 `outline`）为该 token 值，避免不同 Flutter 版本 fromSeed 漂移 |
| 阴影策略 | 无阴影 + 底色分层，投影只给浮层 | `AppBarTheme.scrolledUnderElevation: 1`；`_ArrowButton` 用了 `elevation: 2` | 细节 | `theme.dart:93`、`chat_screen.dart:3041-3081`（3061 行） | AppBar 改 0；滚动到底按钮改为无阴影的 `surfaceContainerHigh` 圆底 |

---

## 3. 已相符清单

- 用户气泡 `primaryContainer` / 助手气泡 `surfaceContainerLow`，颜色逐像素命中；气泡内无名字无图标。
- 气泡圆角 16 / 尾角 4；最大宽 86% 屏宽（助手气泡实测 351.6dp）。
- 助手头像 28dp 气泡外、右间距 8、`primaryContainer` 底色、✦ 图标。
- 消息正文 15dp / 行高 1.6；聊天页 AppBar 标题 16 + 副行 11 `primary`（与 B2 一致）。
- 思考折叠条 44dp 高、`surfaceContainerHighest@50%`、圆角 8、左 chevron、右「展开」`primary`。
- 代码块：通栏出血（头部与气泡内缘等宽）、34dp 头、淡青 `alphaBlend(primary 7%, surface)`、1px 分隔线、白纸代码区、12dp 内边距、12.5/1.6 等宽、横向不换行、复制键视觉 16/热区 44×34、浅色用 atom-one-light。
- 工具芯片 44dp 高；选中三件套（`primaryContainer` + `primary@40%` 描边 + w600）代码齐全（截图中无选中芯片可验）。
- 用量条：<80% 隐藏、无数据隐藏、文案模板「本会话 占用 X% · 缓存命中 Y%」、位置在 AppBar 下左对齐。
- 会话列表：头像 40dp、行左右 16、⋮ 44、FAB 56 + `primaryContainer`、空态不重复放「新对话」。
- 设置页：7 个分区、顺序与设计一致；分区标题 `labelLarge` 700 `primary`；「清空记忆数据」红字行；「后台任务」只显示不启动；「检查更新」存在且文案合理；数据说明「数据全部存在本机」。
- 空态（B1）：64 大麦克风、「问点什么」、一行说明「打字，或按住麦克风说话」、3 条建议为静默列表且点击只预填、底部一行导入入口——代码全部符合，只是截图未覆盖。

---

## 4. 无法从截图判断（需真机/交互复验）

| 项 | 原因 | 建议验证方式 |
| --- | --- | --- |
| 消息操作行（朗读/复制/重试，44×44、间距 0、距气泡 4、复制反馈 2s） | 截图里回复正文被输入栏截断，操作行在屏外 | 滚到回复末尾截一张 |
| 停止键（流式中变红方块 `errorContainer`，始终可点） | 截图是完成态 | 发一条长回答后立刻截图 |
| 错误条 + 出错气泡（红描边 +「这条回答中断了」） | 截图无错误态 | 断网/停止生成后截图（同时验证文案是否中文摘要） |
| 思考过程展开态（竖线颜色、12/1.5 次要色、长思考不顶出答案） | 截图为折叠态 | 展开思考后截图 |
| 代码块横向滚动手势、滚动条、复制后 ✓ 与 2s 复位 | 静态图无法验证 | 长代码行左右滑动 + 点复制 |
| 空态（B1）、搜索态（A3/A4）、多选态（A2）、导入中（A7）、加载失败（A6） | 截图未覆盖这些状态 | 逐个状态截图对帧 |
| 弹层/对话框（C1–C5：模型选择、长按菜单、导出、删除确认、思考强度） | 截图未覆盖 | 逐个打开截图；重点看遮罩 54%、圆角 24/20、选中项内缩块 |
| 设置页「用量 / 后台任务 / 外观 / 数据 / 关于」全部 | 设置截图只到「对话默认」中部 | 向下滚动补 2–3 张 |
| 深色模式 | 只有推导值，交付包也未采样 | 切深色后回采 `surfaceContainerLow` 与 `primaryContainer`，确认明度差 ≥8% |
| 系统字号 1.3× / 1.5× | 静态默认字号 | 改系统字体大小后复验芯片行与 AppBar 标题 |
| 手势类：长按气泡菜单、长按「深度思考」改强度、左滑删除 | 需要交互 | 手动逐个触发 |

---

## 5. 建议修复顺序（按用户可感知程度排序）

1. **副标题统一 12dp + 行高收口（列表 68、设置 52）** — 一处 `listTileTheme.subtitleTextStyle` 能同时修好列表与设置两页，直接影响「页面松不松」的第一观感，最划算。
2. **AppBar 标题 22dp 层级** — 列表/设置的主标题实测只有 14dp，比行标题（16dp）还小，页面没有主入口；先重建复验一次（源码标称 titleLarge 22，屏幕只到 14），确认是构建产物旧还是 `AppBarTheme.titleTextStyle` 未生效。
3. **工具芯片行回到 3 个 + 文案去冒号** — 现在第 4 个芯片在屏外，「添加附件」入口重复且不可发现。
4. **错误条中文摘要** — 这是硬验收，也是唯一会把 `device or resource busy` 直接怼到用户脸上的地方。
5. **删除类一律 `error` 色**（设置页「删除平台」）— 与「编辑」同色同权重，误触风险。
6. **会话列表元信息改成「N 轮 · 绝对时间」** — 现在「2 个对话」单位还错（统计的是消息条数，不是轮次），属于数据语义问题，改文案时顺手把轮数字段补上。
7. **设置页结构收口**：分区标题 24/16/8、加 1px 行分隔线、去掉行前导图标、开关 44×24。
8. **细节批**：气泡内边距 12、思考展开竖线色、思考耗时空格、输入框 44、分割线缩进 64、`outlineVariant` 显式覆盖、去掉多余阴影。

> 说明：第 1、2 条是「氛围级」改动，改完再截图对照，能明显感到层级回来了；第 4、5 条是「事故级」缺陷，不能拖。
