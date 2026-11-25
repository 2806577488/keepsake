# 联网改造：服务端工具 / 外部 Search API 双模式（2026-11-25）

## 为什么要改

DeepSeek 的「服务端联网工具」`deepseek_web_search` / `deepseek_read_url`（以及
`safety_check: {level:"high"}`）一出现，请求就进入 **扩展模式**：**当前这一轮最后
一条 user 消息被限制在 32768 tokens**。带 PDF 时 4MB 的文档解析出 38.5 万 tokens，
必然 400：

```
user input too long, 385203 tokens exceeds max 32768 tokens
```

裸调（不声明扩展字段）则按 1M 上下文放行。

## 实测证据（deepseek-flash，2026-11-25）

| 请求形态 | 结果 |
| --- | --- |
| 无扩展字段 + 38.5 万 tokens 文档 | 200 |
| `tools:[deepseek_web_search]` + 同文档 | 400（max 32768） |
| `tools:[deepseek_read_url]` + 同文档 | 400 |
| `safety_check:{level:"high"}`（无 tools）+ 同文档 | 400 |
| 自定义 `{"type":"function"}` 工具 + 同文档 | 200 |
| 扩展模式 + 6 万 tokens assistant 历史 + 小 user | 200 |

结论：32,768 只卡**当前轮最后一条 user 消息**（含文档解析后的正文），历史轮次不算。

## 两种联网方式

| 方式 | 搜索计费 | 大文档 | 说明 |
| --- | --- | --- | --- |
| `server`（默认） | **免费**（结果按 token 计） | ❌ 会撞 32768 | DeepSeek 服务端工具，行为与旧版一致 |
| `external` | $0.75 / 1000 次 | ✅ 1M 上下文 | 客户端 function 工具 + `/v1/tools/search`、`/v1/tools/fetch` |

配置在「设置 → 对话默认 → 联网方式」（`Settings.webSearch`）：
`serviceId`（`deepseek`/`custom`）、`baseUrl`（留空用官方）、`apiKey`（留空复用
当前平台 Key）、`count`（默认 8）。

**自动兜底**：服务端模式下，如果本轮带有附件（文档），`ChatController` 会自动切到
`external`，避免必然的 400；外部服务没配好时仍回退服务端。

## 新链路（external 模式）

```
模型（1M 上下文，读完整份文档）
  → 输出 web_search(query) / read_url(url)
  → App 调 POST {base}/v1/tools/search、/v1/tools/fetch
  → 结果回填（role:"tool" / tool_result）
  → 模型继续回答（最多 4 轮；最后一轮不带工具，强制出正文）
```

- OpenAI 协议：`lib/core/api/openai_client.dart`（`_pumpClientTools` 等）。
- Anthropic 协议：`lib/core/api/anthropic_client.dart`（同样的多轮 `tool_use` /
  `tool_result` 循环，见该文件注释）。
- 外部服务实现：`lib/core/search/web_search.dart`（`DeepSeekWebSearchService`），
  非 DeepSeek 平台把 `apiKey`/`baseUrl` 填成自己的搜索服务即可（形状兼容
  DeepSeek Search API：`POST {base}/v1/tools/search`、`/v1/tools/fetch`）。

## 验证

- 单测：`test/web_search_test.dart`、`test/openai_client_tools_test.dart`、
  `test/anthropic_tools_test.dart`（全量 18 个用例）。
- 真实链路冒烟（临时测试，已删除）：
  1. OpenAI 协议：普通联网提问 → 模型自动搜索并给出带链接的回答；
  2. OpenAI 协议：思考 + 联网 → 正常；
  3. **OpenAI 协议：4MB PDF（38.5 万 tokens）+ 思考 + 联网（external）→ 正常回答**
     （旧实现必 400）；
  4. **Anthropic 协议：思考 + 外部联网 → 正常（12 个工具事件、1 个来源、528 字回答）**。
- `flutter analyze`：与基线一致（13 条既有 issue，无新增）。

## 后续

- 外部服务可继续接 Tavily / 博查等（新实现类 + `serviceId` 分支即可）。
- 服务端模式在**不带文档**时仍是最省钱的默认，保持免费。
