# Keepsake 0.4.25 工程实现说明

> 本文只陈述工程实际实现，不作验收判定。测试与设计对照请以设计包（`keepsake-design-full`）为准。

---

## 1. 构建信息

| 项 | 值 |
| --- | --- |
| 版本 | `0.4.25`（versionCode 4250） |
| applicationId | `app.keepsake.chat` |
| minSdk / targetSdk / compileSdk | 24 / 36 / 36 |
| Flutter / Dart | 3.50.1 / 3.14.0（stable） |
| 签名 | 仓库内固定 keystore（`android/keystore.jks`），SHA-256 `a34896426f879c6d020b85c792a4603fb2bcc637bd0da43311791bfe087d1fd6` |
| 构建方式 | `build-release.cmd` → 构建库的 `build-abis.cmd`，分 ABI 出两个包 |

产物（构建于 2026-11-23）：

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `keepsake-0.4.25-arm64.apk` | 32,909,412 B | `5bace1a8dc04c446ad977d6c523608ae329e875e89f1d5fc69a2c73d2a9e84f4` |
| `keepsake-0.4.25-arm.apk` | 31,385,702 B | `69cf68eda49ed6ce82b000725ff3563df1d8e8243a39c2bd057836c222deab9b` |

---

## 2. 技术栈与依赖

- 状态管理：`flutter_riverpod`
- 本地数据库：`drift`（SQLite），库文件在应用私有目录
- Markdown：`flutter_markdown 0.7.7+1`（pub 已标记 discontinued，仍在使用）+ `flutter_highlight` + `flutter_math_fork`（数学公式解析器在依赖里，但渲染未启用）
- 字体：E 皮肤打包 `assets/fonts/KeepsakeSerif-subset.otf`（思源宋体子集，含 Bold 字重，启动时 `FontLoader` 预加载）
- 语音：自写 WAV 读写 + ASR/TTS HTTP 客户端（`lib/core/voice/`）
- 导出：自写 ZIP 读写（`lib/core/export/`、`lib/core/import/zip_reader.dart`）
- 网络：`dart:io HttpClient` + 自写 SSE 解析（`lib/core/api/sse.dart`）

---

## 3. 代码结构

```
lib/
  core/
    api/          平台客户端（OpenAI 兼容 / Anthropic 兼容）、SSE、文件上传、模型列表
    brain/        记忆、情绪、人格、召回、事实抽取
    characters/   角色卡服务、会话聚类、补建任务、孤立卡清理任务
    chat/         附件、blocks、上下文构建、摘要、图片工具、图库选择
    db/           drift 数据库与表结构（database.dart / database.g.dart）
    export/       导出
    import/       导入、会话导出、导入任务
    usage/        token 用量、费用、余额
    update/       更新服务（检查、下载、补丁合并、安装、权限）
    voice/        录音、ASR、TTS、WAV、语音守卫
    skin_tokens.dart  三套皮肤的数值定义（唯一允许出现颜色字面量与圆角字面量的地方）
    theme.dart        由 token 生成 ThemeData（零阴影、按压色、选中等）
  features/
    sessions/     会话列表、多选、删除任务
    chat/         聊天页、Markdown 渲染、思考面板、来源列表、代码块、mermaid
    settings/     设置、AI 平台、数据维护、角色卡、用量、余额、导出导入、权限卡片
  widgets/        共享组件
```

---

## 4. 皮肤系统实现

三套皮肤（A 清透 / E 纸感 / H 墨色）各是一个 `SkinMorph` 常量（`lib/core/skin_tokens.dart`），运行时通过 `KeepsakeSkinColors.of(context)` 取用。`SkinMorph` 字段：

`rBubble` `rFab` `rCard` `rSheet` `rChip` `rField` `rSend` `rCb` `rRadio`（圆角）、`fsBar` `fsTitle` `fsBody` `fsSub` `rowHeight`（字号与行高）、`lineHeight` `titleWeight` `titleLSEm` `iconSize` `iconMood` `avatarRadius` `cardBorderWidth` `fontFamily` `fontFamilyFallback` `monoForMeta`。

当前数值（与 `check_consistency.py` 校验通过一致）：

| 项 | A | E | H |
| --- | --- | --- | --- |
| fsBar | 20 | 20 | 22 |
| fsTitle | 16 | **15** | 16 |
| fsBody | 15 | 16 | 16 |
| fsSub | 13 | **12.5** | 13 |
| rowHeight | 68 | 68 | 68 |
| rBubble | 16 | 8 | 14 |
| rCard | 14 | 6 | 12 |
| rChip | 999 | 3 | 8 |
| iconSize | 24 | 24 | 26 |
| 图标风格 | 实心 | 描边 | 实心 |
| 字体 | 系统 | 打包宋体 | 系统 |
| 元信息等宽 | 否 | 是 | 否 |

> 本次修正：E 的 `fsTitle` 由 16 改为 15、`fsSub` 由 13 改为 12.5；新增 `rowHeight` 字段（三套均 68），此前行高是顶层常量 `kRowHeight`，校验脚本按字段名取不到。

颜色方面：颜色字面量只出现在 `skin_tokens.dart`（每套明/暗两组）。`zip_reader.dart` / `wav.dart` 里的 `0xFFFFFFFF` 是文件格式哨兵常量，不是颜色。

---

## 5. 功能实现

### 5.1 会话列表
- 行高由 `kRowHeight`（68）控制，`theme.dart` 里导出为 `listRowHeight`。
- 多选：`_pendingDeleteIds` 集合；复选框替换头像时占位沿用 34（`kCheckboxSlot`）。
- 删除：确认后从列表立即移除（乐观删除），后台 `deleteTaskProvider` 逐批调用 `db.deleteSessions(ids, onProgress:)`——单事务、每 400 条分块；顶部显示进度条（可收起），退出多选不影响任务。
- 删除会话时同步清理该会话关联的角色卡（`CharacterService.deleteCharacter`，连带清空该角色的 brain 记忆）。
- 搜索按标题匹配。

### 5.2 聊天页
- 发送/停止：流式输出中发送键变为停止键（`errBg`/`errC`），无发送内容时禁用（`high`/`onV`）。
- 流式：SSE 增量 append；思考内容单独存 `thinking`，与正文分离显示（`_ThinkingPanel`，显示耗时）。
- 分支：每条回答可有多个分支，可切换上一/下一分支。
- 附件：图片（压缩后上传）与文件卡片，失败回滚。
- 语音：按住录音 → WAV → ASR；TTS 播放。
- 联网搜索：要求模型输出 `[N]` 引用；回答下方「N 个网页」胶囊，点开底部弹层列出来源，条目点击打开浏览器。
- 引用角标：`KeepsakeMarkdown` 内用正则 `\[([0-9]{1,3})\]` 解析（排在链接语法之前），渲染为 10px 上标数字、`selBar` 色、24×24 触摸区；`onCitationTap` 回调由聊天页接到来源弹层（定位第 N 条并加选中底色）。无来源时不响应点击，但仍是上标。
- 长正文：超过约 12k 字先渲染纯文本 +「展开完整排版」按钮，点击后走 Markdown。
- 代码块：自带头部（语言名 + 复制），横向滚动；mermaid 代码块尝试渲染，失败回退源码。

### 5.3 Markdown 渲染
- 在 `flutter_markdown` 的样式表基础上 `copyWith` 覆盖：粗体 700、斜体、删除线 + `onV`、链接 `selBar` + 1px 下划线、引用块左侧 2px `selBar` 竖线、分隔线 1px `ov`、图片按屏宽−28 约束 + `rCard` 圆角、列表缩进 20、分级符号（一级 decimal/disc、二级 lower-alpha/circle、三级 lower-roman）。
- 已知依赖点：`flutter_markdown` 0.7 的 `inlineSyntaxes`、inline builder 合并行为、`bulletBuilder`。

### 5.4 设置
分组顺序：AI 平台 / 对话默认 / 用量 / 后台任务 / 外观 / 数据 / 关于。
- 对话默认：系统提示词、上下文预算、思考强度、深度思考、联网搜索、记忆与回忆、情绪、人格。
- 外观：配色方案（A/E/H）、主题（浅/深/跟随）。
- 数据：角色卡入口、数据维护（补建缺少角色卡的会话、清理孤立角色卡；数量为 0 时整项隐藏）。
- 关于：版本、检查更新。
- 后台任务：导入 / 补建 / 清理 / 删除的进度。

### 5.5 角色卡
- 服务层 `CharacterService`：创建、编辑、删除（删除同时清 brain 记忆）。
- 会话聚类：`character_clustering.dart` 决定会话归属角色。
- 补建任务 `card_backfill_task.dart`、孤立卡清理 `card_cleanup_task.dart`。

### 5.6 导入导出
- 会话导出：ZIP（含会话 JSON 与附件），支持多选或单条导出。
- 导入：自写 ZIP 解析（支持 ZIP64、stored/deflate），导入任务带进度与失败提示。
- 角色卡导入导出同为 ZIP。

### 5.7 记忆 / 情绪 / 人格
- 全部在 `lib/core/brain/`：事实抽取、记忆存储、召回排序、情绪衰减、人格描述。
- 注入：系统提示中包含记忆与人格内容；用户/助手的情绪状态行已从注入内容中移除（不再注入「此刻状态」「当前状态」）。
- 开关：记忆与回忆、情绪、人格三个开关分别控制是否注入。

### 5.8 更新
- 仓库：`2806577488/keepsake-build`，Release 资产为两个 APK + sha256 文件。
- 检查更新会比对当前版本与最新 Release；有新版时弹窗显示清洗后的发布说明（去 Markdown 符号、过滤 SHA256/签名/资产名等技术行，最多 6 行）。
- 下载：优先差分补丁（KSD1 容器 + Kotlin 端 `Inflater(true)` 合并 + Python 端自检），不可用或自检失败自动回退全量。
- 安装：下载完成后拉起安装器；被系统拦住时弹「安装被拦住」并给出「去设置 / 在浏览器打开」。
- 下载好的包路径会保留（`_pendingApk`），从系统设置授权回来后再点更新，按钮为「继续安装」，不再重新下载。
- 当前版本不发布差分补丁（见第 7 节）。

### 5.9 权限
- 安装、存储、麦克风、通知等被拒时，用聊天页/设置页内的权限卡片说明，不反复弹系统框。

### 5.10 构建与发布
- 源码库 `2806577488/keepsake`，构建发布库 `2806577488/keepsake-build`，设计库 `2806577488/keepsake-design`。
- 构建库 GitHub Actions：prepare → 分 ABI 构建 → publish（含签名守卫）→ patch。
- 固定签名：`android/key.properties` + `keystore.jks`。

---

## 6. 自动化与静态检查现状

| 项 | 实际状态 |
| --- | --- |
| `flutter analyze` | 13 issues，0 error（基线） |
| `flutter test` | 仅 `test/md_bold_test.dart` 一个文件；设计包给的 `test/keepsake_ui_test.dart`（10 条断言）**未接入工程** |
| 圆角字面量 | 除 `skin_tokens.dart` 注释外 0 处 |
| 阴影 | `elevation` 全部为 0（theme.dart 8 处、chat_screen.dart 1 处） |
| 颜色字面量 | 仅 `skin_tokens.dart`；`zip_reader.dart`/`wav.dart` 的 `0xFFFFFFFF` 为格式常量 |
| 设计一致性校验 | `check_consistency.py` 对 `skin_tokens.dart` 全部 ok（27 项） |

---

## 7. 已知实现缺口（客观陈述）

1. **差分补丁算法有缺陷**：`tool/make_patch.py` 的还原逻辑在还原真实包时出现字节偏移（本地可复现：还原结果 `a7f127b8…` ≠ 目标 `e010b171…`，首个差异在 1115197 字节处）。因此本版**不发布 patch 资产**，更新走全量下载；自检失败会丢弃补丁。
2. **`flutter_markdown` 已停止维护**（pub 显示 replaced by `flutter_markdown_plus`），当前锁定 0.7.7+1。
3. **引用角标在 `selectable: true` 下的点击行为未自动化验证**：`SelectableText` 的计时器会让 widget test 挂起，只做了渲染与回调的单元验证，真机点击行为未测。
4. **设计的 10 条断言未接入**：工程 `test/` 里目前只有 `md_bold_test.dart`。
5. **E 皮肤字号刚变更**：`fsTitle` 16→15、`fsSub` 13→12.5 是本次按设计包校正的，尚未经过真机视觉复核。
6. **ABI 目录混装（已修，待下一版验证）**：0.4.25 两个包在 `aapt` 里声明了三个 ABI，非目标 ABI 目录仍含插件 `.so`（`libdartjni`、`libdatastore_shared_counter`），x86_64 设备会误选导致启动崩溃。已在 `android/app/build.gradle.kts` 加 `abiFilters`（由 `ORG_GRADLE_PROJECT_keepsakeAbi` 传入），**0.4.26 起生效**。
