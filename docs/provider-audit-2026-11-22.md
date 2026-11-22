# Keepsake（留声）AI 平台 / 协议实现一致性审计

- **审计对象**：`Z:\dsh-restore\keepsake`（Flutter）
- **审计范围**：`lib/core/api/provider_models.dart`、`openai_client.dart`、`anthropic_client.dart`、`model_list.dart`、`file_upload.dart`、`chat_backend.dart`（另核对 `chat_controller.dart` 的附件上传调用点）
- **审计方式**：只读代码 + 逐条比对官方文档（DeepSeek API Docs 及各家开放平台文档），未运行构建、未修改任何代码
- **审计时间**：2026-11-22
- **差异等级口径**
  - **致命**：按当前写法请求必然失败（4xx）或该功能完全不生效
  - **功能缺失**：请求能成功，但文档描述的能力实际没有生效 / 数据被丢弃
  - **不建议**：能跑通，但偏离文档、有平台兼容风险或纯属无效字段
  - **一致**：与官方文档相符，无需改动

> 说明：本报告引用的官方文档以审计当时线上页面为准（DeepSeek 文档已更新到 V4.1 / `deepseek-flash` 与 `deepseek-v4-pro` 两个模型名，与工程里的预设一致）。平台侧文档分散且常改版，`models` 列表类结论只对"审计当时官网可见的名称"负责。

---

## 一、结论摘要

1. **附件（Files API）整条链路是断的，两处致命错位**：`purpose` 写成了官方枚举里不存在的 `assistant`（`file_upload.dart:38`），DeepSeek `POST /files` 会直接 400；即使改对枚举，上传拿到的 `file_id` 也被塞进请求体**顶层**的 `attachments[]` / `file_id`（`openai_client.dart:550-571`），而官方要求的是 `messages[].content` 数组里的 content block `{"type":"file","file_id":"..."}`。也就是说：**上传必挂，通话也永远不会真正带上文件**。
2. **开启「联网搜索」后第二轮必然 400**：官方 Thinking Mode 页明确"请求带 `tools` 时，历史轮次的 `reasoning_content` 必须完整回传，否则返回 400"，而 `buildRequestBody` 只按 `role`/`content` 重建 messages（`openai_client.dart:76-88`），`reasoning_content`、`server_tool_calls` 全部丢弃。
3. **Anthropic 协议引用已上传文件必定 400**：代码用 `{'type':'image'|'document','source':{'type':'file','file_id':...}}`（`anthropic_client.dart:521-543`），官方规定这种 `source.type=file` 必须随请求带 `anthropic-beta: files-api-2025-04-14`，而 `_requestHeaders()` 完全没有这个头（`anthropic_client.dart:177-189`）。
4. **三个"思考"相关参数集体失效**：`thinking` 只在开启时写、关闭时什么都不写，而 DeepSeek **默认就是开启思考（effort 默认 high）**，所以「深度思考」开关关不掉；档位写进了官方不认识的 `reasoning: {level, budget_tokens}`（`chat_backend.dart:414-418`），OpenAI 格式的正确字段是 `reasoning_effort`；Anthropic 格式的 `thinking.budget_tokens` 被官方文档明确标注为 **Ignored**，真正的档位字段是 `output_config.effort`。
5. **服务端工具声明这一块反而是对的**：两种协议都按官方形状声明（Chat Completions 用 `{"type":"deepseek_web_search"}`、Messages 用 `{"type":"deepseek_web_search","name":"deepseek_web_search"}`），没有误写成 OpenAI function tool，也没有设置 `tool_choice` 指向服务端工具。这是整个实现里最贴合文档的部分。

**统计**：共 21 条差异（致命 5 / 功能缺失 9 / 不建议 7），另有 9 项核对为「一致」。

---

## 二、差异明细

### A. DeepSeek · Chat Completions（OpenAI 兼容）

参照文档：[Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion)、[Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode)、[Web Tools](https://api-docs.deepseek.com/guides/web_tools)、[Files API](https://api-docs.deepseek.com/guides/files_api)、[Build a Chatbot](https://api-docs.deepseek.com/guides/build_a_chatbot)

| # | 平台/协议 | 代码里的写法（文件:行） | 官方文档要求 | 差异等级 | 建议改法 |
|---|---|---|---|---|---|
| A1 | DeepSeek / OpenAI | `messages` 只由 `role`+`content` 重建，历史里的 `reasoning_content`、`server_tool_calls`、`annotations` 全部丢弃（`openai_client.dart:76-88`） | 带 `tools` 的请求必须把历史轮 `reasoning_content` 完整回传，否则 **400**（[Thinking Mode › Tool Calls](https://api-docs.deepseek.com/guides/thinking_mode)）；`assistant.message.server_tool_calls` 应"原样回传"（[Web Tools › Chat Completions](https://api-docs.deepseek.com/guides/web_tools#chat-completions-api)） | **致命** | `ChatTurn` 增加 `reasoningContent` / `serverToolCalls` 字段，流式结束时落库，下一轮原样带回 messages |
| A2 | DeepSeek / OpenAI | 附件写成请求体顶层 `attachments: [{type,file_id,file_name,mime}]` + `file_id`（`openai_client.dart:550-571`，调用点 `:117`） | 用 `file_id` 引用文件的方式是 **content block**：`{"role":"user","content":[{"type":"text",...},{"type":"file","file_id":"file-api-..."}]}`（[Files API › Use an Uploaded File in a Chat Request](https://api-docs.deepseek.com/guides/files_api)） | **致命** | 把附件合并进最后一条 user 消息的 `content` 数组；顶层 `attachments` / `file_id` 删掉 |
| A3 | DeepSeek / OpenAI | `thinking` 只在 `enabled` 时写入；不开启时整个字段不出现（`chat_backend.dart:402-419`） | `thinking` 省略时为 **默认开启**；关闭必须显式 `{"type":"disabled"}`（[Chat Completions API › thinking](https://api-docs.deepseek.com/api/create-chat-completion)，[Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode)） | **功能缺失** | 始终写 `thinking: {"type": request.thinking ? "enabled" : "disabled"}` |
| A4 | DeepSeek / OpenAI | 档位写成 `reasoning: {"level": "低/中/高", "budget_tokens": N}`（`chat_backend.dart:414-418`） | OpenAI 格式的档位字段是 **`reasoning_effort`**，取值 `none/low/high/max`（`minimal→low`，`medium/xhigh→high`，`ultra→max`）；`reasoning` 顶层对象只在 Responses API 使用（[Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion)、[Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode)） | **功能缺失** | 改发 `reasoning_effort`；映射建议 低→`low`、中→`high`、高→`max`（注意官方 `medium` 也映射到 `high`，用 `medium` 会让"中/高"两档无差别） |
| A5 | DeepSeek / OpenAI | `thinking` 对象里附带 `budget_tokens`（`chat_backend.dart:410-413`） | Chat Completions 的 `thinking` schema 只有 `type` 一个属性；Anthropic 侧 `budget_tokens` 明确 **Ignored**（[Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion)、[Messages API › AnthropicThinkingConfig](https://api-docs.deepseek.com/api/create-message)） | 不建议 | 去掉 `budget_tokens`，档位交给 `reasoning_effort` |
| A6 | DeepSeek / OpenAI | 把 `request.metadata` 写进顶层 `metadata`（`openai_client.dart:113-116`） | Chat Completions 没有 `metadata` 字段，用户标识用顶层 **`user_id`**；Messages 侧 `metadata` 只认 `user_id`，其余忽略（[Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion)、[Messages API › AnthropicMetadata](https://api-docs.deepseek.com/api/create-message)） | 不建议 | 改发 `user_id`，或直接移除 |
| A7 | DeepSeek / OpenAI | `stream: true` + `stream_options: {include_usage: true}`（`openai_client.dart:90-95`） | 支持；注意官方说明**没有独立的 usage-only chunk**，统计挂在最后一个带 `finish_reason` 的 content chunk 上（[Chat Completions API › stream_options](https://api-docs.deepseek.com/api/create-chat-completion)） | 一致 | 保持；现有"任意 chunk 解析 `usage`"的写法正好兼容 |
| A8 | DeepSeek / OpenAI | 联网工具声明为 `[{"type":"deepseek_web_search"},{"type":"deepseek_read_url"}]`（`openai_client.dart:410-413`） | Chat Completions 正是这个形状（无 `name`、无 `function` 包裹）：[Web Tools › Chat Completions](https://api-docs.deepseek.com/guides/web_tools#chat-completions-api) | 一致 | 无需改动（这条是本工程做得最准的地方） |
| A9 | DeepSeek / OpenAI | 不设置 `tool_choice`（全文无该字段写入） | `tool_choice` 不能指向 `deepseek_web_search` / `deepseek_read_url`，否则 400；`none` 会连带关掉 URL reading（[Web Tools › Declare the Tools](https://api-docs.deepseek.com/guides/web_tools#declare-tools)） | 一致 | 保持"不设置" |
| A10 | DeepSeek / OpenAI | `flatten` 非流式回退取 `choice.message`（`openai_client.dart:319-372`） | 非流式返回 `message.content` / `message.reasoning_content` / `message.annotations` / `message.server_tool_calls`（[Chat Completions API › Response](https://api-docs.deepseek.com/api/create-chat-completion)） | 一致 | 保持 |
| A11 | DeepSeek / OpenAI | 见 `finish_reason == 'tool_calls'` 就报"联网搜索没有被服务端执行"（`openai_client.dart:233-247`、`:362-370`） | 声明服务端工具后 `finish_reason` 只会是 `stop`/`length`/`content_filter`；`tool_calls` 只属于客户端函数工具（[Web Tools › Chat Completions › Output](https://api-docs.deepseek.com/guides/web_tools#chat-completions-api)） | 一致（防御性，可保留） | 保留，但文案可改成"当前平台把搜索当成了客户端函数"更准确 |

### B. DeepSeek · Messages（Anthropic 兼容）

参照文档：[Using the Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api)、[Messages API](https://api-docs.deepseek.com/api/create-message)、[Web Tools](https://api-docs.deepseek.com/guides/web_tools)

| # | 平台/协议 | 代码里的写法（文件:行） | 官方文档要求 | 差异等级 | 建议改法 |
|---|---|---|---|---|---|
| B1 | DeepSeek / Anthropic | 请求头只有 `content-type` / `accept` / `anthropic-version` / `x-api-key` / `authorization`，**没有 `anthropic-beta`**（`anthropic_client.dart:177-189`），但正文会用 `source.type=file` 的图片/文档（`:521-543`） | `source.type=file` 引用上传文件时，请求必须带 `anthropic-beta: files-api-2025-04-14`（[Messages API › anthropic-beta](https://api-docs.deepseek.com/api/create-message)、[Anthropic API › HTTP Header](https://api-docs.deepseek.com/guides/anthropic_api)） | **致命** | 在有 `file_id` 附件时补 `anthropic-beta: files-api-2025-04-14` |
| B2 | DeepSeek / Anthropic | 档位写进 `thinking.budget_tokens`（`anthropic_client.dart:154-162`） | `budget_tokens` **Ignored**；档位字段是 `output_config.effort`（`none/low/high/max`，别名 `minimal/medium/xhigh/ultra`）（[AnthropicThinkingConfig](https://api-docs.deepseek.com/api/create-message)、[AnthropicOutputConfig](https://api-docs.deepseek.com/api/create-message)） | **功能缺失** | 保留 `thinking:{type}`，另加 `output_config:{effort: ...}` 承载三档 |
| B3 | DeepSeek / Anthropic | 不开启思考时完全不写 `thinking`（`anthropic_client.dart:154`） | 省略时两个模型都**默认开启**思考；关闭需 `{"type":"disabled"}`（[AnthropicThinkingConfig](https://api-docs.deepseek.com/api/create-message)） | **功能缺失** | 始终下发 `thinking.type` |
| B4 | DeepSeek / Anthropic | 未命名的 `data: {"error":{...}}` 帧会被丢弃：`type` 取 `event.event ?? json['type']`，为 null 就 `continue`（`anthropic_client.dart:295-297`） | 生成等待超时时，服务端会发**一个没有 `event` 名、也没有顶层 `type` 的** `data` 帧：`{"error":{"message":"..."}}`，然后关连接（[Anthropic API › Streaming](https://api-docs.deepseek.com/guides/anthropic_api#streaming)） | 功能缺失 | 在 `type == null` 分支里先看 `json['error']`，有就抛 `ApiError`，别静默丢弃 |
| B5 | DeepSeek / Anthropic | `max_tokens` 固定兜底 4096（`anthropic_client.dart:33-34`、`:146-148`） | `max_tokens` 可选；**包含 thinking tokens**，未设时按模型/思考模式/effort 取默认（[Messages API › max_tokens](https://api-docs.deepseek.com/api/create-message)） | 不建议 | 不传时直接省略，交给服务端默认；若要兜底，用 8K~64K 量级 |
| B6 | DeepSeek / Anthropic | 历史消息被拍平为纯文本（`ChatTurn.content` 只有 String），`server_tool_use` / `web_search_tool_result` / `web_fetch_tool_result` / `thinking.signature` 都不回传（`anthropic_client.dart:116-138`） | 官方要求"把上一轮 assistant 回复原样回传，包含 `kind` 和 `signature`"；`read_link` 的页面正文靠 `signature` 恢复，缺了就"不加入上下文但请求仍成功"（[Web Tools › Multi-turn](https://api-docs.deepseek.com/guides/web_tools#multi-turn)） | 功能缺失 | 会话层保存原始 content blocks，多轮时按原样回传（至少保留 `signature` 与 `tool_use_id`） |
| B7 | DeepSeek / Anthropic | 进度关键词只找 `query` / `q` / `keyword`（`anthropic_client.dart:549-557`） | `deepseek_web_search` 的 `input.action=search` 用的是 **`queries`（数组）**；`open_page` / `find_in_page` / `read_link` 用 `url`（[Web Tools › server_tool_use](https://api-docs.deepseek.com/guides/web_tools#response-blocks)） | 不建议 | 与 `openai_client.dart:536-542` 对齐：优先读 `action.queries`，再兜底 `query` |
| B8 | DeepSeek / Anthropic | `citations_delta` 直接 `break`，引用角标不收集（`anthropic_client.dart:367-369`） | 引用以 `citations_delta` 逐个下发，含 `web_search_result_location`（url/title）与文本块归属（[Web Tools › Citations](https://api-docs.deepseek.com/guides/web_tools#citations)） | 功能缺失 | 解析 `delta.citation`，按 text block 累积成 `CitationMark`（OpenAI 侧已实现 `annotations`，此处应对齐） |
| B9 | DeepSeek / Anthropic | 读链接正文 `_toolTextOf` 找 `content`/`text`/`snippet`（`anthropic_client.dart:600-621`） | `web_fetch_tool_result` 的正文**永远不返回**：`content.source.data` 恒为空字符串，页面内容加密在 `signature` 里（[Web Tools › web_fetch_tool_result](https://api-docs.deepseek.com/guides/web_tools#response-blocks)） | 功能缺失（文档未写明可展示正文） | 改成只展示 url/title/published_at，或明确"正文仅服务端可见"；不要再指望取到文本 |
| B10 | DeepSeek / Anthropic | 基址 `https://api.deepseek.com/anthropic/v1` + `/messages`（`provider_models.dart:302`、`anthropic_client.dart:63-69`） | 官方 Anthropic SDK `base_url` 是 `https://api.deepseek.com/anthropic`（SDK 自动加 `/v1`）；直连 HTTP 用 `POST /anthropic/v1/messages`（也接受 `/anthropic/messages`）（[Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api)、[Messages API › Endpoint](https://api-docs.deepseek.com/api/create-message)） | 一致 | 无需改动（拼出来的最终 URL 正确，只是常量命名容易误导） |
| B11 | DeepSeek / Anthropic | 服务端工具声明为 `{"type":"deepseek_web_search","name":"deepseek_web_search"}` 与 `deepseek_read_url`（`chat_backend.dart:426-429`） | Messages 协议正是这个形状（`type`+`name`，不带 `input_schema`）（[Web Tools › Declare the Tools](https://api-docs.deepseek.com/guides/web_tools#declare-tools)） | 一致 | 无需改动 |
| B12 | DeepSeek / Anthropic | 同时发 `x-api-key` 和 `Authorization: Bearer`（`anthropic_client.dart:183-188`） | 两者任选其一均可；同时提供时 `Authorization` 优先（[Messages API › Authentication](https://api-docs.deepseek.com/api/create-message)） | 一致 | 可保留；若担心第三方兼容性，可按 `kind` 二选一 |
| B13 | DeepSeek / Anthropic | 发 `anthropic-version: 2023-06-01`（`model_list.dart:29-30`） | DeepSeek 侧**忽略**该头（[Anthropic API › HTTP Header](https://api-docs.deepseek.com/guides/anthropic_api)） | 一致 | 保留（Anthropic 官方要求，其他兼容平台也可能校验） |
| B14 | DeepSeek / Anthropic | SSE 终止判定同时接受 `message_stop` 和 `[DONE]`（`sse.dart:240-241`）；解析 `message_start` / `content_block_start` / `content_block_delta` / `content_block_stop` / `message_delta` / `message_stop` / `ping`（`anthropic_client.dart:299-408`） | Anthropic 流**不发 `data: [DONE]`**，正常以 `message_stop` 结束；事件名与增量类型（`text_delta`/`thinking_delta`/`input_json_delta`/`signature_delta`/`citations_delta`）与代码一致（[Messages API › Streaming](https://api-docs.deepseek.com/api/create-message)） | 一致 | 无需改动 |

### C. Files API 与模型列表

参照文档：[Files API](https://api-docs.deepseek.com/guides/files_api)、[Lists Models](https://api-docs.deepseek.com/api/list-models)、[文件上传](https://api-docs.deepseek.com/api/create-file)

| # | 平台/协议 | 代码里的写法（文件:行） | 官方文档要求 | 差异等级 | 建议改法 |
|---|---|---|---|---|---|
| C1 | DeepSeek / Files | 默认 `purpose = 'assistant'`（`file_upload.dart:38`，调用点未覆盖：`chat_controller.dart:1965-1970`） | `purpose` 必填，枚举只有 `user_data` / `text_recognition` / `rich_layout_recognition`；把 PDF/Word/PPT 用 `user_data` 上传会 400（[Files API › Upload a File](https://api-docs.deepseek.com/guides/files_api)） | **致命** | 图片与纯文本→`user_data`；PDF/Word/PPT→`text_recognition`（或 `rich_layout_recognition`），按 MIME/扩展名派发 |
| C2 | DeepSeek / Files | Anthropic 类型平台的上传基址取 `provider.effectiveBaseUrl`（`chat_controller.dart:1967`），而 `effectiveBaseUrl` 走 `anthropicBaseOf()`（`provider_models.dart:401-405`、`:313-328`） | 自定义 Anthropic 平台的 Anthropic SDK 基址就是用户填的 `.../v1`（不应插入 `/anthropic/v1`）；DeepSeek 的 Files 是 `/anthropic/v1/files`（[Files API › Anthropic-Compatible Files API](https://api-docs.deepseek.com/guides/files_api)） | **致命** | 用户填 `https://api.anthropic.com/v1` 时，上传会打到 `https://api.anthropic.com/anthropic/v1/files`（404）。应让上传基址与 `AnthropicClient.anthropicBase`（`anthropic_client.dart:50-61`）共用同一套派生逻辑 |
| C3 | DeepSeek / Files | 上传头里无条件带 `anthropic-beta: files-api-2025-04-14`（`file_upload.dart:275-288`） | Anthropic 兼容端点**必须**带该头；OpenAI 兼容 `POST /files` 不需要（多余头无害）（[Files API](https://api-docs.deepseek.com/guides/files_api)） | 一致（无害） | 保留 |
| C4 | DeepSeek / Files | multipart 字段 `file` + `purpose`（`file_upload.dart:182-194`） | 字段名一致；**文档要求 `purpose` 必须在 `file` 之前**（`http.MultipartRequest.fields` 先写、`files` 后加，实际顺序正确） | 一致 | 保持现有顺序（别把 files 提前） |
| C5 | DeepSeek / Models | `GET {base}/models`，`openai_client` 用 `normalizeProviderBase(baseUrl)`（`openai_client.dart:42`、`model_list.dart:33-37`） | `GET https://api.deepseek.com/models`，返回 `{object:"list", data:[{id, owned_by, ...}]}`（[Lists Models](https://api-docs.deepseek.com/api/list-models)） | 一致 | 保持；解析 `data[].id` 正确 |
| C6 | DeepSeek / Models | Anthropic 客户端的 `modelsUrl` 用 `provider.baseUrl` 而非 anthropic 基址（`anthropic_client.dart:71-80`） | DeepSeek 的模型列表只有 OpenAI 家 `/models`，Anthropic 侧无 `/models`（[Lists Models](https://api-docs.deepseek.com/api/list-models)） | 一致 | 保持（DeepSeek 下正好拼成 `https://api.deepseek.com/models`） |

### D. 13 个内置预设（base_url / 模型 / 能力位）

| # | 平台 | 代码里的写法（`provider_models.dart`） | 官方文档要求 | 差异等级 | 建议改法 |
|---|---|---|---|---|---|
| D1 | DeepSeek（官方） | `base_url=https://api.deepseek.com`；`thinking/search/files/asr/tts` 全 `true`；模型 `deepseek-flash`、`deepseek-v4-pro`（`:143-156`） | base_url、两个模型名与官方完全一致；Files/Search 能力确由官方提供（[Your First API Call](https://api-docs.deepseek.com/)、[Files API](https://api-docs.deepseek.com/guides/files_api)、[Web Tools](https://api-docs.deepseek.com/guides/web_tools)）；ASR/TTS 官方有独立 API（[Speech to Text](https://api-docs.deepseek.com/guides/asr)、[Text to Speech](https://api-docs.deepseek.com/guides/tts)） | 一致 | 保持 |
| D2 | 月之暗面 Kimi | `base_url=https://api.moonshot.cn/v1`；模型 `moonshot-v1-8k`、`kimi-k2-turbo-preview`（`:157-165`） | base_url 正确（[Moonshot 平台](https://platform.moonshot.cn)）；但官网现行模型已到 `kimi-k2.7-code` / `kimi-k2.6` / `kimi-k2.5` / `kimi-k2-thinking` 等，`kimi-k2-turbo-preview` 属早期预览名，随时可能下线 | **功能缺失** | 换成现行 `kimi-k2.x` / `kimi-k2-thinking`；思考能力对应 `-thinking` 模型而非参数 |
| D3 | 智谱 GLM | `base_url=https://open.bigmodel.cn/api/paas/v4`；模型 `glm-4.6`、`glm-4-flash`（`:166-173`） | base_url + `/chat/completions` 与官方一致，`glm-4.6` 存在（[BigModel API](https://open.bigmodel.cn/dev/api)） | 一致 | 保持 |
| D4 | 硅基流动 | `base_url=https://api.siliconflow.cn/v1`；模型 `deepseek-ai/DeepSeek-V3`、`V3-0324`、`V3.2`、`R1`、`Qwen/Qwen3-235B-A22B`（`:174-187`） | base_url 正确（[SiliconFlow](https://docs.siliconflow.cn)）；官网 `/v1/models` 当前可见 `deepseek-ai/DeepSeek-V4-Flash`、`DeepSeek-V4.1-Flash`、`DeepSeek-V4-Pro`、`zai-org/GLM-5.x` 等，预设里的 V3/V3.2/R1 已被取代 | **功能缺失** | 更新为 V4 系列；同时把 `supportsAsr` 打开（官方有 `FunAudioLLM/SenseVoiceSmall`、`TeleAI/TeleSpeechASR` 与 TTS 模型） |
| D5 | 百川智能 | `base_url=https://api.baichuan-ai.com/v1`；模型 `Baichuan4-Turbo`、`Baichuan3-Turbo`（`:188-194`） | base_url 与模型名均在官方文档列表内（[百川 API](https://platform.baichuan-ai.com/docs/api)） | 一致 | 保持（可选补 `Baichuan4-Air`、`Baichuan3-Turbo-128k`） |
| D6 | 百度千帆 | `base_url=https://qianfan.baidubce.com/v2`；模型 `ernie-4.5-turbo-128k`、`ernie-speed-128k`（`:195-201`） | base_url 与官方 OpenAI 兼容说明一致（[千帆 OpenAI SDK 兼容介绍](https://cloud.baidu.com/doc/qianfan/s/Hmh4suq26)）；模型名需按千帆当前上线清单核对 | 一致（base_url）/ 无法确认（模型名） | 用 `/models` 实测一次再固化 |
| D7 | 火山方舟 | `base_url=https://ark.cn-beijing.volces.com/api/v3`；`models: []`、`defaultModel: ''`（`:202-209`） | base_url 与 `/api/v3/models` 均存在（[Volcengine Models API](https://docs.volcengine.com/docs/ark/models-api)）；但方舟对话更常用**推理接入点 ID**（`ep-xxx`）或带日期的模型 ID，`data[].id` 是否即对话可用 model 需实测 | 不建议 | 保留留空策略，但在 UI 提示"填推理接入点 ID 或模型 ID"，并确认 `/models` 返回结构 |
| D8 | MiniMax | `base_url=https://api.minimaxi.com/v1`；模型 `MiniMax-M2`、`abab6.5s-chat`（`:210-216`） | 官网现行 OpenAI 兼容 base_url 是 **`https://api.minimax.cn/v1`**，`POST /v1/chat/completions` 已正式支持；模型为 `MiniMax-M3.1-Flash` / `MiniMax-M3`（[OpenAI SDK](https://platform.minimaxi.com/docs/api-reference/text-openai-api)、[对话补全](https://platform.minimaxi.com/docs/api-reference/text-chat-openai)） | **功能缺失** | 改 `https://api.minimax.cn/v1`，模型换 M3 系列；`api.minimaxi.com` 旧域名可用性需实测 |
| D9 | 阿里云百炼（通义千问） | `base_url=https://dashscope.aliyuncs.com/compatible-mode/v1`；模型 `qwen3-max`、`qwen-plus`、`qwen-turbo`（`:217-223`） | base_url 是官方兼容模式地址，`/chat/completions` 与 `/models` 均可用；模型名在官方清单内（[DashScope 兼容模式](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)） | 一致（base_url） | 保持；注意 Qwen 的思考开关是 `enable_thinking`，见 E1 |
| D10 | 阶跃星辰 | `base_url=https://api.stepfun.com/v1`；模型 `step-1-flash`、`step-2-16k`（`:224-230`） | base_url 与官方 SDK 示例一致；官网现行模型为 `step-3.x` 系列（[StepFun Chat Completions](https://platform.stepfun.com/docs/zh/api-reference/chat/chat-completion-create)） | **功能缺失** | 更新为 `step-3.7-flash` 等现行模型 |
| D11 | 腾讯混元 | `base_url=https://api.hunyuan.cloud.tencent.com/v1`；模型 `hunyuan-turbos-latest`、`hunyuan-lite`（`:231-237`） | base_url + `/chat/completions` 与官方一致，`hunyuan-turbos-latest` / `hunyuan-lite` 均为官方模型 ID（[混元 OpenAI 兼容接口](https://cloud.tencent.com/document/product/1729)） | 一致 | 保持 |
| D12 | 自定义（OpenAI 兼容） | `baseUrl: ''`、`kind: openai`（`:238-244`） | 空串由用户填写，`normalizeProviderBase` 会补 `https://` 并去尾斜杠 | 一致 | 保持 |
| D13 | 自定义（Anthropic 兼容） | `baseUrl: ''`、`kind: anthropic`（`:245-251`） | 用户填 Anthropic SDK 基址（如 `https://api.anthropic.com/v1`）；**但上传基址会走 `anthropicBaseOf` 被插入 `/anthropic/v1`**，见 C2 | **致命**（上传路径） | 与 C2 一起修：自定义 Anthropic 平台不要走 `anthropicBaseOf` |
| D14 | 能力位派发 | 仅 DeepSeek 打开 `supportsFiles/Search/Asr/Tts`，其余平台全 false（`:142-252`）；语音守卫再强制"只有 DeepSeek"（`lib/core/voice/voice_guards.dart:58-68`） | 官方文档中 Moonshot / 智谱 / DashScope / 硅基流动 等均提供文件上传或语音能力；硅基流动明确有 ASR/TTS 模型（见 D4 链接） | 功能缺失 | 不建议一次性全开；按平台补 `supportsAsr/Tts/Files`，并让请求构造按平台派发（见 E1） |

### E. 跨平台参数派发（`supportsThinking` 的前提）

| # | 平台/协议 | 代码里的写法 | 官方文档要求 | 差异等级 | 建议改法 |
|---|---|---|---|---|---|
| E1 | Moonshot / 智谱 / 硅基流动 / DashScope / StepFun | 无论哪个平台，`ensureReasoning` 都发同一套 DeepSeek 形状：`thinking{type,budget_tokens}` + `reasoning{level,budget_tokens}`（`chat_backend.dart:402-419`） | 各家思考开关字段并不统一：DashScope 兼容模式是 `enable_thinking`、硅基流动是 `enable_thinking` + `thinking_budget`、Moonshot 走 `kimi-k2-thinking` 模型名、智谱 GLM-4.5+ 才认 `thinking:{type}` | 无法确认（未逐页核对各家参数名）/ 风险高 | 至少给 `ensureReasoning` 加平台分支；拿不准的字段宁可不发，避免第三方网关严格校验时 400 |
| E2 | 全部 OpenAI 兼容平台 | 强制 `stream:true` + `stream_options.include_usage`（`openai_client.dart:90-95`） | DeepSeek 明确支持；其余平台多数支持，但不排除个别网关对 `stream_options` 报 400 | 无法确认 | 加一级降级：400 且错误提示指向 `stream_options` 时，去掉该字段重试一次 |
| E3 | 全部平台 | 历史只有纯文本，多轮上下文里 `reasoning_content` / `server_tool_calls` / `signature` 都不保留 | 官方要求原样回传（见 A1、B6） | 功能缺失 | 属于会话模型改造：`ChatTurn` 需要能存结构化 payload，而不是只存 String |

---

## 三、无法确认清单（文档没写 / 需要真 Key 才能验证）

1. **未知顶层字段是否 400**：`attachments`、`file_id`、`reasoning`、`metadata` 都不在 DeepSeek Chat Completions schema 里，也不在 [Ignored Parameters](https://api-docs.deepseek.com/guides/build_a_chatbot#ignored-parameters) 列表内。是"静默忽略"还是"400"，官方未写明，只能实测；但无论哪种，**文件都不会进上下文**（A2 的结论不变）。
2. **`thinking` 对象里多带 `budget_tokens` 是否被拒**：schema 只有 `type`，未见 `additionalProperties:false` 的明确说明（对比 `title` 明确写了 `additionalProperties: false`），需要用真 Key 发一次带多余键的请求确认。
3. **DeepSeek 的 `metadata` 语义**：Chat Completions 只有 `user_id`；`metadata`（除 `user_id`）在 Messages 侧明确"忽略"，Chat Completions 侧未提，属文档空白。
4. **各平台 `/models` 是否都实现、返回结构是否都是 `data[].id`**：DeepSeek、DashScope、SiliconFlow、Ark 有 `GET /models`；智谱 `/api/paas/v4/models`、百川、阶跃、混元的对应端点未逐一核实。代码 `_findModels` 已做多形态兜底，风险可控。
5. **方舟 `/api/v3/models` 返回的 id 能否直接作为对话 `model`**：文档只说"查询可见的基础模型版本"，未说与推理接入点 ID 的关系，需实测（D7）。
6. **MiniMax 旧域名 `api.minimaxi.com` 是否仍解析**：官网现行文档统一写 `https://api.minimax.cn/v1`，旧域名未声明下线，也未声明可用（D8）。
7. **各平台思考参数的确切字段名**：本报告只对 DeepSeek 的两个协议给出文档级结论；Moonshot/智谱/硅基流动/DashScope/StepFun 的 `enable_thinking` / `thinking_budget` / 模型变体名，属"业界通行写法"，本次未逐页取官方 URL 核实（E1）。
8. **Anthropic 协议下 `document` + `source.type=file` 是否也要求同样的 beta 头**：文档对 `document` 的 `file` source 仅在 Files API 页说明"请求必须带 `anthropic-beta: files-api-2025-04-14`"，未区分 image/document，按"需要"处理（B1 已按最严口径判）。
9. **`finish_reason == 'tool_calls'` 在 DeepSeek 服务端工具模式下是否真不会出现**：文档列出的 `finish_reason` 枚举里 `tool_calls` 存在，但服务端工具场景描述的是 `stop/length/content_filter`；代码的防御分支是否会误报，需真 Key 跑一次搜索验证。

---

## 四、修复优先级建议（不改代码，仅排序）

1. `purpose` 枚举（C1）与 `attachments` 位置（A2）—— 二者一起修，附件功能才从"必挂"变成"可用"。
2. `reasoning_content` 回传（A1）—— 不修则"联网搜索 + 多轮"必 400，是本工程最容易被用户撞到的致命组合。
3. `anthropic-beta`（B1）与自定义 Anthropic 上传基址（C2）—— 决定 Anthropic 协议的附件能不能用。
4. `thinking` 开关与 `reasoning_effort` / `output_config.effort`（A3-A5、B2-B3）—— 决定「深度思考」三档是否真的有区别。
5. 预设模型名与 `base_url` 更新（D2、D4、D8、D10）—— 影响"点开即用"的第一印象。
6. 多轮结构化回传（B6、E3）与引用/关键词解析（B7、B8）—— 体验类，可随后做。
