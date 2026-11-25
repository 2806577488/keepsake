# Keepsake（留声）

一个把 DeepSeek 网页对话「留」在本地的 Android 应用：导入导出、分支重生成、搜索、Markdown 与代码块、语音、角色卡。

> 个人项目，MIT 许可。当前版本 **0.4.29**。

## 功能

- **导入 / 导出**：支持 DeepSeek 官方导出 ZIP 与单会话导出；导入是后台队列（进度持久化、可断点续跑），打开会话时优先补导该会话。
- **大会话不卡**：消息列表窗口化（首屏只构建最近约 12 条，顶部「加载更早」分批），单条超长正文先渲染纯文本、按需「展开完整排版」。
- **会话管理**：列表左上角多选（全选 / 批量删除 / 导出选中）；会话级「深度思考 / 思考强度 / 上下文」只影响当前会话，设置页管默认值。
- **聊天**：流式输出、停止、重新生成（新建分支，不覆盖旧回答）、复制、搜索来源 pill、Markdown 代码块（横向滚动、语法高亮、一键复制）。
- **相册与图片编辑**：「从相册选择」是 App 内自带的相册（相册分类 / 多选序号 / 大图预览 / 只读 MediaStore），不会再被系统跳去文件管理器；预览页可裁剪、旋转、镜像后再发。
- **角色卡**：按会话内容补建角色卡，可中断、可续跑；设置页显示后台任务进度。
- **多平台**：OpenAI 兼容协议与 Anthropic `/v1/messages` 协议，支持 DeepSeek 及其他兼容平台。

## 构建

需要 Flutter 3.50+（Dart 3.14）与 Android SDK 36。

```bash
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
# 出包后自检：每个被声明的 ABI 都必须带 libflutter.so（否则装到对应设备上启动即崩）
python tool/check_apk_abi.py build/app/outputs/flutter-apk/app-release.apk
```

- `--target-platform` 现在会**自动收紧 abiFilters**（`android/app/build.gradle.kts`）：
  以前只有 `build-abis.cmd` 设 `keepsakeAbi` 才过滤，按上面这条命令出包会得到
  「声明 3 个 ABI、只带 arm64 引擎库」的必崩包。
- 应用只面向 Android（Windows / iOS 未验证）。
- 发布包目前使用 debug 签名，覆盖安装前请先备份并卸载旧版。

## 架构

- `lib/features/**`：会话列表、聊天、设置、角色卡等页面与私有组件。
- `lib/core/db`：drift（SQLite），会话 / 消息 / 附件 / 角色卡 / 用量。
- `lib/core/api`：OpenAI 与 Anthropic 协议客户端、模型列表、文件上传。
- `lib/core/import`：DeepSeek 导出 ZIP 解析、导入任务队列、子集导出。
- `lib/core/chat`：上下文构建、系统提示、Markdown 与代码块渲染。
- Riverpod 管状态，chat 控制器持有消息树（分支）。

## 隐私

- API Key 只保存在本机设置（SharedPreferences），不会随代码或仓库提交。
- 导入的会话数据只写本地 SQLite，不上传。

## 设计

界面按 `docs/design-handoff/` 里的设计交付包实现：`tokens.md`（颜色/排版/间距）、`screens/`（5 张 2× 设计表）、`specs/screens.md`（逐帧规格）。

## 致谢

- 流式与 Markdown：`flutter_markdown`、`flutter_math_fork`、`flutter_highlight`。
- 数据：drift / sqflite。
- 设计交付包：由项目作者与 AI 设计师协作产出。

## License

MIT
