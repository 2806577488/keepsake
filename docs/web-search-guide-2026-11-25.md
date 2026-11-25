# 联网服务使用教程（2026-11-25）

> 适用版本：0.4.27+；代码入口 `lib/core/search/`、设置页「对话默认 → 联网方式」。

## 1. 支持哪些联网方式

| 方式 | 搜索计费 | 大文档 | 说明 |
| --- | --- | --- | --- |
| **服务端（免费）**（默认） | 免费 | ❌ 32768 限制 | DeepSeek 服务端工具，普通聊天不花搜索费 |
| **外部 API** | 见下表 | ✅ 1M 上下文 | 客户端工具 + 外部搜索服务 |

外部服务共 **4 家 + 自定义**：

| 服务 | 搜索 | 读链接 | 价格 / 免费额度 | 适合 |
| --- | --- | --- | --- | --- |
| **DeepSeek**（默认） | ✅ | ✅ | $0.75 / 1000 次（约 ¥5/千次） | 已有 DeepSeek key，中文结果好 |
| **Tavily** | ✅ | ✅ | 1000 次/月免费，之后按量 | 英文、Agent 场景 |
| **博查 Bocha** | ✅ | ❌ | ¥0.036/次，1000 次试用 | 中文结果好 |
| **Brave Search** | ✅ | ❌ | 独立索引，免费额度约 2k/月 | 想要 Google 之外的索引 |
| 自定义 | ✅ | 视实现 | — | 兼容 DeepSeek Search/Fetch 形状的自建服务 |

> 「读链接」= 模型调用 `read_url` 抓网页正文。博查 / Brave 只有搜索，所以
> App 不会给它们声明 `read_url` 工具（模型会基于搜索摘要回答）。

## 2. 怎么开启

1. **设置 → 对话默认 → 联网搜索**：打开开关（聊天页出现「联网 · 开」芯片）
2. 点 **联网方式**：
   - **服务端（免费）**：默认，搜索本身不计费；当前轮 user 输入限 32768 tokens；
   - **外部 API**：选搜索服务（DeepSeek / Tavily / 博查 / Brave / 自定义），
     按次计费但**没有 32768 限制**，大文档也能联网。
3. 选「外部 API」后填：
   - **搜索服务**：下拉选择；
   - **服务地址**：只有「自定义」需要填；其它显示默认地址（留空即默认）；
   - **API Key**：填对应服务的 key；DeepSeek 可留空（复用当前平台 Key）；
   - **条数**：每次搜索返回多少条，默认 8（1–50；Tavily / Brave 上限 20）。
4. 保存即生效。

## 3. 什么时候会自动切换

「服务端（免费）」模式下，如果**本轮带了附件（文档）**，App 会自动改用外部
API——文档解析后通常超过 32768，服务端工具必然报错。外部没配好（缺 Key/地址）
时仍退回服务端。

普通聊天（不带文档）始终走服务端，**不产生搜索费用**。

## 4. 各服务 Key 在哪申请

| 服务 | 控制台 |
| --- | --- |
| DeepSeek | https://platform.deepseek.com/api_keys |
| Tavily | https://app.tavily.com（1000 credits/月免费） |
| 博查 Bocha | https://open.bochaai.com（注册后「API KEY」） |
| Brave | https://api.search.brave.com/app/keys |

## 5. 自建 / 聚合服务怎么接

选「自定义」，服务地址填自己的基址、Key 填自己的 key，实现下面两个接口即可：

```http
POST {base}/v1/tools/search
Authorization: Bearer <key>
Content-Type: application/json

{"query": "关键词", "count": 8, "need_content": false}
```

```json
{
  "results": [
    {
      "title": "标题",
      "url": "https://example.com/a",
      "snippet": "100–200 字摘要",
      "summary": "600–800 字长摘要（给模型读）",
      "content": "可选正文",
      "site_name": "站点名",
      "date": "2026-11-01T00:00:00+00:00"
    }
  ]
}
```

```http
POST {base}/v1/tools/fetch
Authorization: Bearer <key>
Content-Type: application/json

{"url": "https://example.com/a"}
```

```json
{"title": "页面标题", "content": "# Markdown 正文"}
```

> 响应用 UTF-8 解析；`results` 里 `url` 为空的条目会被丢弃。

## 6. 排查

| 现象 | 原因 / 处理 |
| --- | --- |
| 「联网服务请求失败：… 401」 | Key 无效或没填对；DeepSeek 留空会复用平台 Key，其它服务必须填 |
| 「402 余额不足」 | 外部账户没余额：充值，或把「联网方式」切回服务端（免费） |
| 「429 请求太频繁」 | 超过服务 QPS：稍后再试 |
| 「联网服务超时」 | 网络/服务端慢（客户端 40s 超时）：重试或换服务 |
| 带文档仍报 32768 | 外部服务没配好 → 自动回退到了服务端；补全 Key/地址 |
| 模型只给摘要、没读链接 | 当前服务不支持读链接（博查 / Brave）；换 DeepSeek / Tavily |
| 想完全不花钱 | 「联网方式」选服务端（免费）；带文档会失败（32768 限制） |

## 7. 加新服务

1. 在 `lib/core/search/web_search.dart` 实现 `WebSearchService`
   （可继承 `HttpWebSearchService`，只需给 `authHeaders` + `search`；
   不支持抓取时 `supportsFetch => false`、`fetchPage` 抛错即可）；
2. 在 `lib/core/search/search_config.dart` 加 `serviceId` 常量、默认基址、显示名；
3. `webSearchServiceFor` 里加一个 `case`；
4. 设置页下拉会自动出现新选项（`searchServiceLabel`）。
