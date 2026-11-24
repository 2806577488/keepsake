# 审查清单对照：0.4.25 两份问题清单 vs 当前版本（2026-11-24）

- 输入：`Keepsake-0.4.25-工程侧问题清单-20261123.zip`、`Keepsake-0.4.25-设计侧问题清单-20261123.zip`
- 当前基线：`main` @ `4360e1c`（0.4.26 + 相册 / chip 按压态 / 顶部轻提示 / 文档共 5 个 commit）
- 方法：源码逐条 grep + 阅读；**本机没有真机**，依赖设备/性能/像素的条目标 `需真机复测`
- 判定口径：**以当前代码与当前设计资产为准**；旧清单里版本号的出入不算问题

---

## 一、一句话结论

工程 44 条里 **8 条已修、17 条源码可证仍存在、9 条需真机复测、8 条等设计裁决**；
设计 30 条里 **我抽查的 20 条全部仍存在**，其中 **D-19（`tokens/skin_tokens.dart` 编译不过）是阻断级**，它会污染所有"token 是真值"的结论。
最有价值的新发现是 4 条（第二节），其中 **N-1 ABI 崩溃在本机实测仍可复现**、**N-2 设计 token 文件仍无法编译**。

---

## 二、旧清单没有、这次新发现的（按严重度）

### N-1（阻断，仍可复现）ABI 崩溃风险没有真正关掉，只靠构建脚本传参

今天我在本机按**默认命令**出包：
`flutter build apk --release --no-pub --target-platform android-arm64`

`aapt2 dump badging` 结果仍是：

```
native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'
tar -tf app-release.apk | findstr libflutter → lib/arm64-v8a/libflutter.so  （只有一条）
```

也就是 E-01 描述的"声明三个 ABI、只放一个 ABI 的引擎库"完全没变。0.4.25 的修复是
`android/app/build.gradle.kts` 里 `if (keepsakeAbi != null) ndk { abiFilters… }`，
依赖 `build-abis.cmd` 设置 `ORG_GRADLE_PROJECT_keepsakeAbi`；**任何人不带这个变量出包
（包括 README 里写的 `flutter build apk --release --target-platform android-arm64`）
都会重新产出一个 x86_64/armv7 必崩的包**。

建议：`abiFilters` 直接按 Flutter 传进来的 `-Ptarget-platform` 收紧（不再依赖外部脚本），
并在打包后断言 APK 里 `lib/` 只有目标 ABI；把断言写进构建脚本/CI。

### N-2（阻断，设计侧）`keepsake-design/tokens/skin_tokens.dart` 仍然编译不过

D-19 原样存在：`fsBody` 字段声明两次、构造函数参数也两次（`tokens/skin_tokens.dart:180-181`、`200-201`）。
这个文件是"唯一允许出现颜色与圆角字面量"的 token 真值，却从未通过 Dart 编译器；
`check_consistency.py` 只用正则抓值，所以错误一直没暴露。

### N-3（高）chip 高度 SPEC 32 / CSS 36 仍分裂，而且我新加的按压态也按 36 写了

- `SPEC.md` §4.8 与工程 `kChipHeight = 32` 一致；
- `reference/full.css` 的 `.chip { height: 36px }`（D-10 原样存在）；
- 今天补的 `.chip:active` 是按 36 的盒子写的。

改 CSS 到 32 时要连按压态一起改，否则"HTML 是唯一真值"会把工程带偏。

### N-4（中）新功能没有任何设计资产，也不在旧清单的验收范围内

相册页（分类抽屉 / 日期分组 / 序号多选）、预览页、图片编辑器、顶部轻提示，
都只有工程实现 + 我补的 SPEC 段落（§4.8 按压、§4.9 toast），**没有 screens/ 截图、
没有 HTML 示例屏、没有 UI 测试**。E-44 想接入的设计测试也覆盖不到这些页面。

### N-5（中）E-44 实际上无源可接

设计仓库根目录**没有 `test/` 目录**，清单里提到的 `test/keepsake_ui_test.dart` 在交付包里不存在；
工程 `test/` 也确实只有 `md_bold_test.dart`。要么设计方补文件，要么这条从验收清单里删掉。

### N-6（中）"以谁为准"仍未落地，而且这次还多了一份要维护的文档

`SPEC.md` §7 仍写"HTML 是唯一真值来源"，但 `check_consistency.py` 喂 `full-chat.html` /
`full-settings.html` 会各 FAIL 2 项（E/H 的 `fs-title` 16/17 vs dart 15/16）——今天复跑确认。
我新加的 v3.1/v3.2 规则同时写进 SPEC 与 CSS，等于让"三份真值"变成"四份"。

### N-7（低）发行说明链路仍是 0.4.24

`docs/IMPLEMENTATION-0.4.24.md` 是最新的"发行说明"，今天的 5 个 commit 没有对应发行说明。
E-03（版本/哈希手写）根因没消除：仍是手写文档，没有从构建产物自动生成。

---

## 三、工程侧 44 条：逐条状态

图例：✅ 已修 · ❌ 仍存在（源码可证）· ⏳ 需真机复测 · ⚖️ 等设计裁决

### A. 阻断

| # | 状态 | 证据（当前代码） |
|---|---|---|
| E-01 | ❌ 本次实测仍可复现 | 见 N-1：默认构建产出 3-ABI 声明 + 只有 arm64 引擎库 |
| E-02 | ⏳ 需真机 | 导入收尾仍在主 isolate；未新增分帧/`PostFrameCallback` 证据 |
| E-03 | ✅ 机制已修（2026-11-24） | keepsake-build CI 现在把发行说明作为资产发布（`IMPLEMENTATION-<ver>.md`，版本/哈希/签名指纹都取自构建产物）；仓库里的 `IMPLEMENTATION-0.4.24.md` 降级为历史文档 |

### B. 高

| # | 状态 | 证据 |
|---|---|---|
| E-04 | 部分修 / ⏳ | 状态行本来就存在（`_StreamStatus`）；这次把它改成**固定 24dp 高**（E-22）。"请求已发、首字节未到"这段的观感要真机看 |
| E-05 | 部分修（2026-11-24） | `_applyCharacterMode` 不再静默吞异常：失败会提示并指向「设置 › 数据维护」；收尾再查一次缺卡数，>0 就明确告知。**根因（3457 那次到底断在哪一步）仍需真机复现** |
| E-06 | ✅ | `sessions/delete_task.dart:54-58`：单事务失败即整体回滚，注释明确"绝不能退回逐条删除" |
| E-07 | ✅ 已修（2026-11-24） | 流式期间正文改**纯文本渲染**（不再每个 tick 解析 Markdown、不再逐帧高亮代码块），通知间隔 60→100ms，气泡套 `RepaintBoundary`（只有正在生成那条重绘）。真机流畅度仍建议复测 |
| E-08 | ✅ 已修（2026-11-24） | `_onDispose` 现在调用 `_persistAbandonedStream()`：把已流出的正文/思考写回占位行（标 `error` 旗标，回来显示「这条回答中断了」）；一个字都没收到则删掉占位行 |
| E-09 | ✅ 已修（v3.5 裁决后） | A/H 的 `aiBg` 改 `low`、`aiFg` 改 `onS`；E 改纸色 `#F1EDE4`；用户/AI 气泡不再同色 |
| E-10 | 不成立（规范外） | 见 §六：当前设计交接 `ui-logic.md:158` 明确写「更多菜单只有『设置』一项……刻意保持极简，不要往这里加按钮」；会话列表的 ⋮ 菜单代码里已有（`sessions_screen.dart:515-566`）。审计引用的「v3.3 §2.4」不在两个仓库里 |
| E-11 | ✅ 已修（2026-11-24 模拟器实测后真修） | 原实现是 `_SessionUsageGate` 卡「占用 < 80% 整条隐藏」，正常使用时**永远看不到**；现在只要会话 id 非空就交给 `SessionUsageBar` 表达（读取中 / 无数据 / 失败）。空会话实测显示「本会话 占用 — · 缓存命中 —」 |
| E-12 | ✅ 已修（v3.5 裁决后） | `sessions_screen.dart` `_NewSessionFab`：`pC` 底 + 1px `kFabLineColor`（#8CCDBB）描边；DESIGN SPEC §4.5 同步改为同一口径 |

### C. 中

| # | 状态 | 证据 |
|---|---|---|
| E-13 | ❌ ⚖️ | `markdown_view.dart:682` `fromLTRB(14, 12, 14, 0)`（规范 16/14） |
| E-14 | ❌ ⚖️ | `chat_screen.dart:1794` `width * 0.76`（规范：用户屏宽−88 / AI 屏宽−56） |
| E-15 | ❌ | `sessions_screen.dart:849` `Divider(height: 1)` 通栏（规范左缩进 62） |
| E-16 | ❌ ⚖️ | `sessions_screen.dart:967-976` 竖条 2px；`kSelectionBarWidth = 2` 且**没有任何引用**（`skin_tokens.dart:41`） |
| E-17 | 部分修（2026-11-24 模拟器实测） | 主题/配色方案/思考强度三处弹窗原来用 `Icons.check_circle`（实心+白勾），不符合「20 外环 + 中心 8dp 点」。已换自绘 `_RadioDot`（`settings_screen.dart` 末）。**导入确认弹窗仍是 Material `RadioListTile`**（import_tile.dart），留作后续 |
| E-18 | 部分 | 按压态按 v3.1 新规则复用 `high`（不需要新 token）；`fabLine` 仍缺（与 E-12 同源） |
| E-19 | ⏳ 未复核 | E 字体预加载路径未逐行看 |
| E-20 | ⏳ 未复核 | 左滑背景已是 `errorContainer`（`sessions_screen.dart:868`）；确认弹窗按钮配色未核 |
| E-21 | ⏳ 未复核 | 自动滚动阈值 / 节流 / 新内容浮标未逐行核 |
| E-22 | ✅ 已修（2026-11-24） | `_StreamStatus` 固定 24dp 高（`SizedBox(height: 24)`），文案长短不影响气泡高度 |
| E-23 | ⏳ 未复核 | 输入框常态边框未核 |
| E-24 | ✅ 已修（2026-11-24） | 构建库本来就发 `<apk>.sha256` 附件；App 侧 `update_service` 下载后按附件校验（不匹配删文件+报错），原生加 `fileSha256` 方法 |
| E-25 | ⏳ 未复核 | `database.dart` onUpgrade 的 catch 未逐行看 |
| E-26 | ✅ 已修（2026-11-24） | `sse.dart` 加单行 256KB / 单事件 4MB 上限，超限抛 `SseLimitExceededException`；新增 `test/sse_limits_test.dart` 3 条回归 |
| E-27 | 部分 | CRC 已校验（`zip_reader.dart:307`）、非 UTF-8 已回退（`:363`、`:549-554`）；背压/半截文件未核 |
| E-28 | ✅ 已修（2026-11-24） | 后台已在删时先 `return` 并提示「正在删除会话，请稍候再试」；事务回滚时提示「删除失败…已整体回滚」（`sessions_screen.dart` `_deleteSelected`） |
| E-29 | ✅ | `import_task.dart:143`「正在导入 x / y」 |
| E-30 | ✅ | `provider_section.dart:560` 转圈 + `:377/379` 成功/失败 toast |
| E-31 | ❌ ⚖️ | `chat_screen.dart:2840` 仍是 `'$n 轮'`；设计要求「上下文 · 最近 20 轮」 |
| E-32 | ⏳ 未复核 | 动作条是否缺「分支 / 更多」待逐屏核 |
| E-33 | ⏳ 需真机 | — |
| E-34 | ✅ | `import_tile.dart:381`「确认导入历史对话？」 |
| E-35 | ✅ | `chat_screen.dart:982/3204`「发消息…」 |
| E-36 | ✅ 已修（2026-11-24） | `chat_screen.dart` AppBar `titleSpacing: 8 → 4`（SPEC §4.1） |
| E-37 | ✅ 已修（2026-11-24） | `theme.dart` 引用块改 2px `selectionBar`、不铺底（与 `markdown_view` 一致）；`tokens.md` 同步 |
| E-38 | ⏳ 未复核 | 朗读项图标↔文字间距未核 |
| E-39 | ✅ 已修（v3.5） | `skin_tokens.dart` E 的 `avatarRadius: 0 → 17`（圆形，与 A/H 一致） |
| E-40 | ❌（低） | `mermaid_block.dart:333` `Color(0x00000000)` |
| E-41 | ✅ 已修（2026-11-24） | `pubspec.yaml` 版本注释改为"tag 必须与本行一致"；`kSelectionBarWidth` 改为**真正被引用**（选中竖条 `width: kSelectionBarWidth`），不再是死常量 |
| E-42 | ✅ 不复现 | 今天 `flutter analyze`（13 条历史告警）**退出码 0** |
| E-43 | ❌ | `IMPLEMENTATION-0.4.24.md` 仍是唯一发行说明；README 未覆盖今天的 `docs/*.md` |
| E-44 | ❌ 无源可接 | 设计仓库没有 `test/` 目录，清单提到的测试文件不存在 |

统计：✅ 8（E-06/11/29/30/34/35/42 + E-04 部分）· ❌ 17 · ⏳ 11 · ⚖️ 4（E-09/12/13/14/16/31/39 里部分并入裁决）

---

## 四、设计侧 30 条：抽查结果

| # | 状态 | 证据（当前 `keepsake-design`） |
|---|---|---|
| D-01 `--lh` E 1.5 vs 1.7 | ❌ | `SPEC.md:21` 1.5 ↔ `:82` 1.7 |
| D-02 `--meta-font` | ❌ | `SPEC.md:87` 三套无衬线 ↔ 硬性约束 5 与 §0 说 E 衬线/等宽 |
| D-03 `--row-h` H 68 vs 78 | ❌ | `SPEC.md:83` 68 ↔ `:96` 78 |
| D-04 A `--title-w` | ❌ | `SPEC.md:86` 600；token 表该格空；`skin_tokens.dart` A 段无 titleWeight=600 |
| D-05 `--av-r` 未定义 | ✅ 已修（v3.5） | HTML 有 `--av-r`（A=17、E=6）；按裁决统一 17 圆形，E 已改；token 表补 `--av-r` 行 |
| D-06 `r-send/r-fab/r-sheet` 三套缺值 | ❌ | SPEC §4.5/4.6 引用，token 表无；只有 dart 里有 |
| D-07 `[N]` 引用样式缺 | ❌ | `full.css` 无 `.cite` |
| D-08 19 个变量跨来源不一致（尤其 E 圆角=H） | **审计结论有误**（2026-11-24 复核） | 逐个文件核对：三份 HTML 的 E 块写的是 `r-bubble 8 / r-card 6 / r-chip 3 / r-field 6 / r-send 6 / r-fab 6 / r-sheet 14 / r-cb 3`，与 `skin_tokens.dart` 的 E **一致**；旧审计报的「E = H 的 14/12/8…」是把 H 块当成 E 解析了（`check_consistency.py` 的 `extract_html` 用正则抓块，容易抓错）。真正仍不一致的是 `fs-title`（见下表 E/H 行） |
| D-09 屏数多种说法 | ❌ | `reference/index.html:27`「30 个屏」、`:53`「9 张 1360 宽」；SPEC 411×892 |
| D-10 chip 32 vs 36 | ❌ | SPEC §4.8 32 ↔ `full.css:172` 36 |
| D-11 chip 图标 15 vs 13–14 | ❌ | SPEC 15 ↔ `docs/icons.md:75`「13–14」 |
| D-12 抓手 32 vs 36、弹层标题 18 vs `fs-bar` | ❌ | `full.css:227` `.sheet h4 { font-size: var(--fs-bar) }` |
| D-13 危险按钮配色 | 未复核 | — |
| D-14 气泡宽度/内距 | 未复核 | — |
| D-15 竖条 2 vs 3 | ❌ | 与 E-16 同源 |
| D-16 明度差 8% 不可执行 | ❌ | `SPEC.md:91` 仍未给口径 |
| D-17 `pC = aiBg` 气泡同色 | ❌ | 设计侧 dart 同值；真机已复现（E-09） |
| D-18 E 的 `aiBg` 冷薄荷 | ❌ | `skin_tokens.dart`/`SkinColors` E `aiBg #A0F2DF` |
| D-19 `skin_tokens.dart` 编译不过 | ❌ **阻断** | 见 N-2 |
| D-20 字体 fallback 字段缺 | ❌（抽查结论） | `skin_tokens.dart` 无 fallback 列表字段 |
| D-21 icons 清单 21 vs 36 | 未复核 | — |
| D-22 缺 token（`field-bg`/`code-*`/`usage`/`sel-line`/`fab-line`/`tail`） | ❌ | `full.css` 在用、SPEC/token 表未定义 |
| D-23 版本号写死 v1.1.0 | ❌ | `reference/full-settings.html:142` |
| D-24 screens 尺寸说明 | ❌ | 三处说法（1360 / 411×892 / 实测 1360×4690） |
| D-25 test import 路径不符 | ❌ | 且文件缺失（见 N-5） |
| D-26–D-29 工具失效 | 未复核 | 这次只跑了 `check_consistency.py`：喂 `full-chat`/`full-settings` 各 FAIL 2 项（D-28 成立） |
| D-30 FAB 两套写法 | ❌ | `full.css:114` pC 底 + `--fab-line` 描边；SPEC 硬性约束 4 说 surface 底 + `#8CCDBB` |

---

## 五、下一批怎么分（**修正版**：上一版把"需要口径"的混进了"可直接修"）

### A. 真·不需要裁决（机械修复，改完能自证）

> **2026-11-24 已完成**：A-1…A-8 全部落地（工程 4 条 + 设计 5 条，见下表的"已完成"列）。
> 设计侧同步在 `keepsake-design` v3.4。

| # | 事项 | 为什么不需要裁决 |
|---|---|---|
| A-1 | E-41 `pubspec.yaml` 注释「必须与 tag v0.4.14 一致」+ 删无引用的 `kSelectionBarWidth` | 注释过时；常量无人引用，删掉不影响行为 |
| A-2 | E-36 顶栏 `titleSpacing: 8 → 4` | `SPEC.md` §4.1 白纸黑字「左右各 4」，工程单边偏离 |
| A-3 | D-19 `tokens/skin_tokens.dart` 重复字段（`fsBody` 两处声明/两处参数） | 编译错误，删重复即可；改完再跑一次编译器，可能暴露后续错误，属同一条 |
| A-4 | D-10/N-3 `.chip` CSS 36 → 32（连 v3.1 按压态） | SPEC §4.8 与工程 `kChipHeight=32` 一致，CSS 是唯一偏离方 |
| A-5 | D-11 `icons.md` chip 图标 13–14 → 15 | SPEC 硬性要求 15，`icons.md` 自己那一节也写"Material 图标 13 会糊" |
| A-6 | D-23 `full-settings.html` 写死 `v1.1.0` | 直接把版本号改成「版本见工程发行说明」，不再写死 |
| A-7 | D-24/屏数尺寸：在 `index.html` 写清「screens/ 是 1360 宽导出图，画布 411×892，2× 关系」 | 是把事实写清楚，不涉及取舍 |
| A-8 | E-28 并发删除时 UI 别再说"已开始" | 行为对错明确；文案我给默认「正在删除，请稍候」，可改 |

### B. 需要你拍一个小口径（你点头我就做）

| # | 事项 | 需要你定什么 | 我的默认建议 |
|---|---|---|---|
| B-1 | N-1 ABI 收紧 + 断言 | 是否继续出 armv7（32 位）包；不支持 ABI 时"装不上"还是"装了崩" | 继续出 arm64 + arm 两个包（沿用 build-abis.cmd），只让每个包**只声明自己的 ABI**；打包后断言 `lib/` 只有目标 ABI |
| B-2 | E-26 SSE 长度上限 | 阈值与超限行为 | 单行 ≤ 64KB、单事件 ≤ 512KB，超限抛可读错误并保留已收内容 |
| B-3 | E-24 完整包 sha256 | 校验值从哪来（keepsake-build 的 release 里加 `.sha256`？还是塞进现有 patches 元数据？）+ 不匹配时提示什么 | 由 keepsake-build 额外发 `keepsake-<ver>-<abi>.apk.sha256`，App 下载后校验，不匹配就删文件并提示"安装包校验失败，请重试" |
| B-4 | E-03/N-7 发行说明自动生成 | 生成放在哪：本仓库脚本还是 keepsake-build CI | 放 keepsake-build CI（它已经有版本/哈希），成功后回写/上传 `IMPLEMENTATION-<ver>.md` |
| B-5 | E-37 引用块样式 | 3px+底色 / 2px 不铺底 / 2px+底色 —— **仓库里两处文档现在自相矛盾**（`tokens.md:57` 写 3px，`IMPLEMENTATION-0.4.24.md` 写 2px），不是"照一处改就行" | 按 v3.3：2px `selBar`、不铺底 |
| B-6 | D-28 `check_consistency` 三份 HTML 都过 | 这本质是 **E/H `fs-title` 到底 15 / 16 / 17**（G-2 第 11 条），不是工具 bug | E=15（与 dart 一致），把两份 HTML 的 16/17 改掉 |

### C. 必须先裁决（不裁决工程会一直"照错实现"）
- D-08 / G-0：`HTML` / `skin_tokens.dart` / `SPEC.md` 谁是唯一真值（**这一条不定，下面 20 条都没法定**）
- E-09/D-17 气泡同色、D-18 E 的 AI 气泡、D-30 FAB 底色+描边、D-16 明度口径
- E-13/E-14 气泡/正文内距、E-16 竖条 2/3、E-31 chip 文案、D-01/D-03/D-04/D-05/D-06 数值

### D. 只能真机
E-02（导入后 ANR）、E-04/E-22（等待反馈）、E-33（气泡右侧 ∨）、E-17/E-19/E-20/E-21/E-23/E-25/E-32/E-38 的未复核项。

---

## 七、模拟器实测（2026-11-24，Android 15 x86_64 + adb 逐步操作）

环境：本机装了 emulator + `system-images;android-35;google_apis;x86_64`，用 AEHD 加速（驱动安装完成、**未重启**）；
装 `--target-platform android-x64` 的包，adb 逐条命令操作（tap/swipe/text/screencap），非脚本回放。

走了一遍：首页空态 → 设置（含滚动到底）→ 聊天空态 → 输入聚焦 → 无 Key 发送 → 会话列表 → ⋮ 菜单 → 长按多选 → 搜索。

**发现并已修 3 处：**

1. 输入框聚焦是**近黑 1.5px 粗边**（聊天输入 / 搜索框一致）：主题 `focusedBorder` 用了 `onS 1.5`，且 `enabledBorder` 无描边。
   设计是「未聚焦 1px outlineVariant、聚焦 primary 1.2px」→ 已改为 `ov 1px` / `selBar 1.2px`，复验通过。
2. 顶部用量条**正常状态永远不出现**（E-11 之前标"已修"是误判）→ 去掉 80% 闸门，见上表。
3. 没有平台时副标题写成「**未配置 · deepseek-flash**」，像已经选好模型 → 无平台时只显示「未配置」。

**验证通过、未发现问题**：设置页 7 个分组与滚动、后台任务空态、配色/主题入口、聊天空态与建议卡、
chips 禁用态、发送禁用态、错误横幅（重试/关闭）、列表行（头像/标题/轮数/时间）、⋮ 菜单（重命名/置顶/删除，无补建）、
多选顶栏（已选 N/全选/导出/删除）与行内选中条、搜索「没有找到…」空态、键盘弹起时输入栏位置。

**仍待真机/模拟器深测**：流式（需要真 Key）、导入大包（需要 197MB 导出 ZIP）、相册（需图片）、
深/浅色切换、E/H 两套皮肤逐屏、横屏、系统大字号、长按消息菜单与分支切换。

---

## 六、复核后撤回的一条（E-10）

旧清单说「会话内 ⋮ 只有设置，5 个应有项全缺」。复核结论：**按当前设计交接，聊天页 ⋮ 就该只有「设置」一项**，不是缺陷。

证据：

- `docs/design-handoff/ui-logic.md:158`：「更多菜单只有一个「设置」项（跳到设置页）。**这里刻意保持极简，不要往这里加按钮**。」
- 那 5 项（重命名 / 置顶 / 导出这一条 / 删除这一条 / 查看用量）属于**会话列表行**的操作，不是聊天页顶栏：
  `ui-logic.md:59` 写的是列表 ⋮ 菜单 = 会话标题 + 重命名 → 置顶/取消置顶 → 删除会话 → 为缺少角色卡的会话补建；
  代码里已经实现：`sessions_screen.dart:515-566`（重命名 / 置顶·取消置顶 / 删除会话）；
  其中「为缺少角色卡的会话补建」按 v3.3 §2.2 搬到了「设置 › 数据维护」（`sessions_screen.dart:248-249`）。
- 旧清单引用的「v3.3 §2.4」不在 `keepsake` 也不在 `keepsake-design` 仓库里；设计资产 `full-list.html:246-260` 的 ⋮ 菜单也是 4 项（重命名 / 置顶 / 补建 / 删除会话），且**没有**「导出这一条 / 查看用量」。

如果产品上确实想要"会话内也能重命名 / 置顶 / 只导出这一条 / 只删这一条 / 查看用量"，那是一次**新需求**（还要同步改设计交接 §2.2 那句"不要加按钮"），不是修 bug。

### 用户确认后的口径（2026-11-24）

- 聊天页 ⋮ **只有「设置」**；
- **补建是"对全部会话"的批量修复**，所以它**不该**出现在单条会话 / 单条列表行的菜单里 ——
  这一条是产品语义决定的，不是工程偷懒；
- 列表行 ⋮ 保留 重命名 / 置顶·取消置顶 / 删除会话。

代码侧已经就是这个口径（`sessions_screen.dart:515-566` + `data_maintenance_section.dart:3` 的
"影响所有数据的，从设置进"）。这次修正的是**文档**：

- `docs/design-handoff/ui-logic.md` §1.3（列表 ⋮ 菜单链去掉补建）、§1.7（入口改到设置）、§3.2（后台任务只显示）；
- `docs/design-handoff/README.md` 第 8 条；
- 设计库：`reference/full-list.html` 示例屏去掉补建一行、`CHECKLIST` 第 26 条、`CHANGELOG` v3.3。
