# 角色卡止血（0.4.33）

现象（用户截图 + 导出件 `Keepsake-导出-20261126-1个会话.zip` 复现）：

- 一个普通问答会话（「社保公积金追缴现在是哪个局在负责？」「妈的现在的中医熟地24g
  都开出来了」）在列表里变成了一张「角色卡」，名字就是**整句会话标题**；
- 点开编辑弹窗，四个字段糊成一屏：胶囊输入框、label 掉在框外、简介是一整块 100dp 的
  空白、人设框里塞着「你是「妈的现在的中医熟地24g都开出来了」…」这种自动生成文本。

## 根因

| 表面 | 真实原因 |
|---|---|
| 每张卡名字都是一整句 | `characterNameFor()` 只做了 trim，**没有使用** `isGenericCardTitle`；17 字标题直接当人名 |
| 一聊天就长出一张卡 | `ensureForSession()` 对**每个会话**懒建一张卡（一次问答也算） |
| 人设框里那坨文本 | `defaultCharacterPrompt(name)` 把整句标题内插成「你是「…」」 |
| 弹窗像四个灰药丸 | 弹窗用了主题的 `rField = 999` 胶囊圆角 + `isDense`，label 被挤到框外；`maxLines` 没有 `minLines`，高度全凭内容 |

**最荒诞的一点**：`CharacterRow.prompt` 全仓库只有「写入」和「弹窗显示」两处读取，
**从来没有送进模型**（对话用的是设置里的全局 `resolvedSystemPrompt`）。所以那段人设既
是垃圾数据，又在误导用户以为它生效。

## 本次改动（App 侧止血）

1. **不再一会话一卡**：`ensureForSession` 在没给显式名字时，复用**同一张默认记忆域**
   （`source = default` 且没有人设文本），名字固定「未命名角色」，**不写人设**。
   记忆隔离仍在（卡=边界），但普通对话不再冒充"角色"。
2. **名字规则**：`characterNameFor()` 变严格 —— 去引号/句末标点、折叠空白、>12 字、
   问句（`?/？`、句内标点、疑问词）与占位词一律不当作人名，退话题词或「未命名角色」。
   手工输入走新增的 `sanitizeManualName()`（宽松：只 trim、最长 24 字），
   不会把用户自己起的名字改掉。
3. **展示不再偷改**：`labelOfSession` / `nameOfSession` 显示库里存的名字（空则占位名）。
   老的长句卡需要用户自己改，不静默改名。
4. **弹窗重做**（`characters_screen.dart`）：小圆角 + 1px 描边、框内小标题、
   名字/emoji 收窄并排、简介固定 3 行、人设 4–6 行、内容区 `maxHeight 60%`、
   名字为空时「保存」不可点、名字像会话标题时给一句提示。
5. **人设字段如实标注**：改名「人设备注（可选）」，并写明
   「只保存在这张卡上；当前版本不会替代设置里的全局 system prompt」。

## 没做（留给后续）

- **老数据迁移**：已存在的长句角色卡不会被自动改名（改名是用户的决定）。
  如果要做，建议先只统计、弹一次「有 N 张卡的名字像会话标题，要批量改成「未命名角色」吗？」。

## 后续：人设真正接上（0.4.34）

0.4.33 里那张卡的人设字段仍然是"只存不用"，所以我们把它接上了，同时精确清掉老 bug 造出来的垃圾：

1. **注入**：`characterPromptSection(prompt)` → 非空时把 `【角色设定】\n…` 拼进 **system prompt**
   （稳定内容，只在编辑卡时变，放 system 前缀不破坏缓存；情绪/召回这类每轮变的仍挂最后一轮 user）。
   超过 1200 字截断。
2. **清理**：`shouldClearAutoPrompt(name, prompt)` —— 只有「人设是老模板 `你是「<名字>」…`
   **且** 名字本身不是人名」的卡才清空 prompt；名字正常、模板未改的卡保留（那段模板是合理的默认人设）。
   清理是**惰性**的：在 `ensureForSession` 里顺手做（每轮都经过，无冷启动开销）。
3. **文案**：弹窗底部从「不会替代全局 system prompt」改成「会追加在全局 system prompt 之后；留空则不注入」。

为什么不是一次性迁移脚本：清理判据依赖「名字是不是人名」，纯 SQL 判不了；放在
`ensureForSession` 里既能覆盖到、又不会在冷启动时扫全表。

### 验证（0.4.34）

- `flutter analyze`：仅剩 `character_clustering.dart` 两条改动前就有的 info。
- `flutter test`：**39/39**（新增「人设注入」与「自动生成人设清理判据」两组）。

## 验证

- `flutter analyze lib/core/characters lib/features/settings/characters_screen.dart`：
  仅剩 `character_clustering.dart` 两条**改动前就有**的 `library_private_types_in_public_api`。
- `flutter test`：**34/34**（新增 `test/character_name_test.dart` 11 条，钉住命名规则）。
