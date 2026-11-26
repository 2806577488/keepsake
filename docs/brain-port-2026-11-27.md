# 把 dsh-brain 的三层移植进 App（0.4.35）

目标：App 的「自带大脑」不再只有记忆/情绪/人格，而是和 DSH 插件同一套语义——
**规范（人写）→ 角色（模型写）→ 实体（对象档案）→ 工作记忆（注入）**。

| 层 | 插件里的东西 | App 落点 | 关键约束 |
|---|---|---|---|
| 规范 | `role.js`（静态配置注入） | `Settings.specialtyRules` → `brain_profile.dart` 渲染 `【专业规范】` | 用户写、稳定内容、放 system 前缀 |
| 角色 | `character.js`（模型 bootstrap + 修订 + 版本） | `brain_character.dart` + `characters.definition*` + `character_versions` | 模型写、每 N 轮修订、失败不覆盖 |
| 实体 | `entities.js`（规则抽取 + 档案 + 槽位） | `brain_entities.dart`（纯规则）+ `brain_entities_store.dart`（库）+ `brain_entity_extract.dart`（低频 LLM 抽字段） | 按 `characterId` 隔离、宁缺毋滥、同文本去重 |
| 工作记忆 | `context.js`（组装这一轮看到什么） | `chat_controller`：`规范 → 角色 → 【当前对象】+ 召回 → 最后一轮 user` | 稳定内容进 system；易变内容挂最后一轮 user（保缓存） |

## 注入顺序

```
system:
  默认提示词 / 用户系统提示词
  【专业规范】      ← v0.4.35（Settings.specialtyRules）
  【角色设定】      ← v0.4.34（角色卡人设 prompt）
  【我是谁】        ← v0.4.35（模型写的 definition，bootstrap 之后才有）
last user turn:
  【当前对象 · 张三（患者）】+ 【相关对象】  ← 实体优先
  【关于你】【关于我】【当前心情】【表达倾向】+ 召回片段
  <用户这句话>
```

为什么这样分：system 是稳定前缀（改角色才变），最后一轮 user 是每轮都变的部分。
DeepSeek/OpenAI 的上下文缓存是前缀缓存，混在一起会让命中率掉到 18%–34%（0.4.28 实测）。

## 后台任务（都不 await、失败静默）

| 触发 | 做什么 | 频次 |
|---|---|---|
| 每轮结束 | 情绪/人格/事实/情节（原有）+ 实体抽取（规则） | 每轮 |
| 第 3、6、9… 轮 | 实体字段抽取（LLM：主诉/辨证/处方/复诊） | 每 3 轮 |
| 证据攒够（默认 6）或还没写过 | 角色 bootstrap / 修订（LLM） | 低频 |

## DB（schema 6）

- `characters` 加 4 列：`definition` / `definition_version` / `definition_source` / `definition_evidence`
- 新表：`character_versions`、`entities`、`entity_facts`、`entity_turns`、`brain_wm_state`
- 迁移：`from < 6` 用 `_tryAddColumn` + `createTable`（不用 `createAll`，避免老库索引冲突）

## 验证

- `flutter analyze`：brain/chat 相关零新增问题（只剩改动前就有的 5 条）
- `flutter test`：**85/85**（规范 5 + 实体规则 16 + 实体 store 11 + 角色 14 + 原有 39）

## 没做

- 设计库还没补 App 版「规范/角色」的表单规范（`keepsake-design` 那边只到 v3.11 的角色卡）；
- 角色定义与角色卡人设冲突时以谁为准——目前是**都注入**（人设在先、模型定义在后），
  真实使用里如果发现打架，再定优先级。
