/// Keepsake（留声）— drift 数据库（表结构 / 迁移 / 数据访问）。
///
/// **契约 B（冻结）**：表名、列名严格照 `reports/apk/db-schema.md` §2/§3
/// （列名来自 libapp.so 里 drift 生成的 SQL 字面量，[确定]）。
/// 生成文件：`database.g.dart`（`dart run build_runner build --delete-conflicting-outputs`）。
///
/// 命名约定（重要，给其它批次）：
/// - **表类**是复数：`Sessions` / `Messages` / `Attachments` / `SessionSummaries` / `SummaryCaches`
///   → 表访问器 `db.sessions` / `db.messages` / … → 表名 `sessions` / `messages` / …
/// - **行数据类**是单数：`Session` / `Message` / `Attachment` / `SessionSummary` / `SummaryCache`
///   （drift 默认把 `Sessions` 行类生成为 `Session`；这里用 `@DataClassName` 显式钉死，
///   `SessionSummaries`/`SummaryCaches` 必须显式，否则默认规则会截成 `SessionSummarie`）。
/// - 列名 snake_case 由 getter 名自动转换：`messageCount` → `message_count`、
///   `currentMessageId` → `current_message_id`、`index` → `index`（drift 生成时给列名加引号）。
/// - 时间列是 `DateTime`，drift 默认以 **unix 秒 int** 落库；原生 SQL 读出来要自己换算
///   （见 `SessionSearchHit` 的解析），写入时 `DateTime.now()` 即可。
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// 表定义（列清单逐字照 db-schema.md §2）
// ---------------------------------------------------------------------------

/// `sessions` — 会话。
@DataClassName('Session')
@TableIndex(name: 'sessions_updated', columns: {#updatedAt})
class Sessions extends Table {
  /// 会话 id；导入的 DeepSeek 会话保留外部 id。
  TextColumn get id => text()();

  /// 标题（空串时 UI 显示「未命名会话」）。
  TextColumn get title => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// 列表按它排序（`touchSession` 更新）。
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  /// 该会话消息数（分支重生成时可能 > 可见链长度）。
  IntColumn get messageCount => integer().withDefault(const Constant(0))();

  /// 分支：当前消息节点。
  TextColumn get currentMessageId => text().nullable()();

  /// 分支：分支根节点。
  TextColumn get rootMessageId => text().nullable()();

  /// 位域（[推断] 置顶/归档/已读），见 `setSessionFlag`。
  IntColumn get flags => integer().withDefault(const Constant(0))();

  /// 手动排序（置顶用，升序，NULL 排最后）。
  IntColumn get sort => integer().nullable()();

  /// 会话级联网搜索开关。
  BoolColumn get searchEnabled => boolean().withDefault(const Constant(false))();

  /// 会话级「深度思考」覆盖值。
  ///
  /// `NULL` = 未覆盖（用全局设置里的默认值）；**聊天页只写这一列，不写全局设置**。
  BoolColumn get thinkingEnabled => boolean().nullable()();

  /// 会话级「思考强度」覆盖值（`ThinkingLevel.wireName`：`low`/`medium`/`high`）。
  ///
  /// `NULL` = 未覆盖（用全局默认档位）。
  TextColumn get thinkingLevel => text().nullable()();

  /// 会话级上下文预算覆盖值（保留最近 N 轮；`<= 0` = 不限制）。
  ///
  /// `NULL` = 未覆盖（用全局默认值）。
  IntColumn get contextKeepRounds => integer().nullable()();

  /// 所属角色卡（`characters.id`）。
  ///
  /// v3 及更早的老会话为 `NULL`：读取时按需建一张默认角色卡（`ensureCharacterForSession`），
  /// 因此这里**不使用 FK 级联**，避免删角色时误删会话；解绑由应用层显式写 `NULL`。
  TextColumn get characterId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// `messages` — 消息（树状分支：root_message_id / current_message_id）。
@DataClassName('Message')
@TableIndex(name: 'messages_session', columns: {#sessionId, #createdAt})
class Messages extends Table {
  /// 消息 id（`_StoredMessage`）。
  TextColumn get id => text()();

  /// 所属会话（FK → sessions.id，级联删除）。
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// `user` / `assistant` / `system`（展示文案「用户/助手」在 UI 层）。
  TextColumn get role => text()();

  /// 正文（可能是 blocks JSON，见 `core/chat/blocks.dart` 的 `encodeBlocks`）。
  TextColumn get content => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// 分支根。
  TextColumn get rootMessageId => text().nullable()();

  /// 当前分支指针。
  TextColumn get currentMessageId => text().nullable()();

  /// 同会话内序号（列名就是 `index`，drift 生成时加引号）。
  IntColumn get index => integer().withDefault(const Constant(0))();

  /// 位域（[推断] 已压缩/已总结/错误）。
  IntColumn get flags => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// `attachments` — 附件 / 图片。
@DataClassName('Attachment')
@TableIndex(name: 'attachments_session', columns: {#sessionId})
class Attachments extends Table {
  /// 本地 id（uuid）。
  TextColumn get id => text()();

  TextColumn get sessionId => text()();

  /// 所属消息（[推断]，导入时可能先落附件后落消息，故不加 FK）。
  TextColumn get messageId => text().nullable()();

  /// 原文件名（导出 ZIP 里保存原件）。
  TextColumn get fileName => text().withDefault(const Constant(''))();

  IntColumn get fileSize => integer().withDefault(const Constant(0))();

  TextColumn get mime => text().withDefault(const Constant(''))();

  /// 本地缓存路径。
  TextColumn get path => text().withDefault(const Constant(''))();

  /// 图片宽（`image_util.dart` 缩放用）。
  IntColumn get width => integer().nullable()();

  /// 图片高。
  IntColumn get height => integer().nullable()();

  /// DeepSeek Files API 返回的服务端 id（`attachmentByServerId`）。
  TextColumn get fileId => text().nullable()();

  /// 远程链接。
  TextColumn get url => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// `session_summaries` — 会话摘要（600 字内）。
@DataClassName('SessionSummary')
class SessionSummaries extends Table {
  /// 主键即会话 id（db-schema §1 的列名常量里没有独立 id 列 → [推断]）。
  TextColumn get sessionId => text()();

  /// 摘要正文。
  TextColumn get summary => text().withDefault(const Constant(''))();

  /// 摘要字符数（计入上下文预算）。
  IntColumn get summaryChars => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// 缓存失效判断用。
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{sessionId};
}

/// `summary_caches` — 上下文摘要缓存（`contextSummary` / `summaryCacheOf` / `saveSummaryCache`）。
@DataClassName('SummaryCache')
class SummaryCaches extends Table {
  TextColumn get sessionId => text()();

  /// 截断上下文用的摘要（注入 system 的「【以下是本会话更早对话的压缩摘要…】」）。
  TextColumn get contextSummary => text().withDefault(const Constant(''))();

  /// 与 contextSummary 同义冗余（db-schema §2 原表如此）。
  TextColumn get summary => text().withDefault(const Constant(''))();

  IntColumn get summaryChars => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{sessionId};
}

// ---------------------------------------------------------------------------
// 角色卡（schemaVersion 4）
//
// 一张角色卡 = 一个人设 + 一套**完全隔离**的记忆/情绪/人格。
// `sessions.character_id` 指向这里；导入的每个会话自动对应一张卡。
// 建卡规则在 `lib/core/characters/character_service.dart`（纯规则，不调 LLM）。
// ---------------------------------------------------------------------------

/// `characters` — 角色卡。
@DataClassName('CharacterRow')
@TableIndex(name: 'characters_updated', columns: {#updatedAt})
class Characters extends Table {
  TextColumn get id => text()();

  /// 角色名（会话列表 / 聊天页顶部展示）。
  TextColumn get name => text().withDefault(const Constant(''))();

  /// 人设 / 系统提示（默认模板见 `defaultCharacterPrompt`）。
  TextColumn get prompt => text().withDefault(const Constant(''))();

  /// 简介（导入时取首条 user 消息截断；可编辑，可空）。
  TextColumn get description => text().nullable()();

  /// 头像文本（一个 emoji；默认 🤖）。
  TextColumn get emoji => text().withDefault(const Constant('🤖'))();

  /// `manual` / `import` / `default`。
  TextColumn get source => text().withDefault(const Constant('manual'))();

  // ---- v0.4.35：角色层（移植自 dsh-brain 的自我定义） ----
  // 与 `prompt` 的区别：`prompt` 是**用户写的**人设；`definition` 是**模型从对话里
  // 长出来的**自我定义（bootstrap + 每 N 轮修订，带版本历史）。
  /// 自我定义正文（空串 = 还没 bootstrap）。
  TextColumn get definition => text().withDefault(const Constant(''))();

  /// 版本号（0 = 未 bootstrap；≥1 = 已写过几版）。
  IntColumn get definitionVersion =>
      integer().withDefault(const Constant(0))();

  /// `llm`（模型写的）/ `fallback`（无模型时的规则兜底）/ `''`（还没有）。
  TextColumn get definitionSource => text().withDefault(const Constant(''))();

  /// 上次修订后攒了多少轮新证据（到阈值才再修订）。
  IntColumn get definitionEvidence =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

// ---------------------------------------------------------------------------
// 「自带大脑」表（schemaVersion 4；纯本机、不依赖 DSH）
//
// **隔离规则**：下面每张表都带 `character_id`，读写一律按角色过滤——
// 跨角色绝不召回（见 `BrainStore`）。
// 原文永不丢：`messages.content` 仍是唯一原文来源，这里只存「整理后的结构」：
// - `memory_facts`       关于用户 / 关于助手自己的结构化事实；
// - `memory_episodes`    情节记忆（≤160 字小摘要 + 原文消息 id 指针）；
// - `memory_recall_stats`召回自学习统计（v1 只统计 injected / used）；
// - `mood_state`         单行情绪状态（`id = 1`）；
// - `mood_history`       情绪轨迹；
// - `persona_traits`     两侧表达倾向（key 是 string，不是 SQL 的 `key`）。
// ---------------------------------------------------------------------------

/// `memory_facts` — 结构化事实（按角色隔离）。
@DataClassName('MemoryFactRow')
@TableIndex(name: 'memory_facts_scope', columns: {#characterId, #side})
class MemoryFacts extends Table {
  TextColumn get id => text()();

  /// 所属角色卡（隔离键；`''` = 未绑定角色的历史数据，只有该角色能读到）。
  TextColumn get characterId => text().withDefault(const Constant(''))();

  /// `user`（关于用户）/ `self`（关于助手自己）。
  TextColumn get side => text()();

  /// 事实文本（`≤60 字`，已归一化掉引号/多余空白）。
  ///
  /// 列名必须是 `fact_text`：getter 叫 `text` 会和 drift 的 `Table.text()` 撞名，
  /// 生成器会递归解析成 `TextColumn` 不可调用。
  TextColumn get factText => text().withDefault(const Constant(''))();

  /// 0..1 权重（类型初值 + 重复看到时微增）。
  RealColumn get weight => real().withDefault(const Constant(0.5))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  /// 最近一次被召回的时间。
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  IntColumn get useCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// `memory_episodes` — 情节记忆（后台整理产出：小结 + 原文指针；按角色隔离）。
@DataClassName('MemoryEpisodeRow')
@TableIndex(name: 'memory_episodes_scope', columns: {#characterId, #createdAt})
class MemoryEpisodes extends Table {
  TextColumn get id => text()();

  /// 所属角色卡（隔离键）。
  TextColumn get characterId => text().withDefault(const Constant(''))();

  TextColumn get sessionId => text().withDefault(const Constant(''))();

  /// 涉及的原文消息 id（JSON 数组；原文仍在 `messages` 表里）。
  TextColumn get turnIdsJson => text().withDefault(const Constant('[]'))();

  /// `≤160 字`的小摘要（user 主句 + assistant 首句）。
  TextColumn get summary => text().withDefault(const Constant(''))();

  /// 当时的用户心情值（0..1，可空）。
  RealColumn get mood => real().nullable()();

  /// 0..1 重要度。
  RealColumn get salience => real().withDefault(const Constant(0.5))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// `memory_recall_stats` — 召回自学习（v1 只统计注入/用上/没用上；按角色隔离）。
@DataClassName('MemoryRecallStatRow')
class MemoryRecallStats extends Table {
  /// `turn` / `fact` / `episode`。
  TextColumn get kind => text()();

  /// 对应记忆 id（消息 id / 事实 id / episode id）。
  TextColumn get memoryId => text()();

  /// 所属角色卡（隔离键）。
  TextColumn get characterId => text().withDefault(const Constant(''))();

  IntColumn get injected => integer().withDefault(const Constant(0))();

  IntColumn get used => integer().withDefault(const Constant(0))();

  IntColumn get ignored => integer().withDefault(const Constant(0))();

  /// 0..1 有用度（`used / injected` 的平滑值）。
  RealColumn get usefulness => real().withDefault(const Constant(0.5))();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{kind, memoryId};
}

/// `mood_state` — 每个角色一行情绪状态（主键就是 `character_id`）。
@DataClassName('MoodStateRow')
class MoodStates extends Table {
  /// 角色卡 id（一个角色一行，所以它同时是主键）。
  TextColumn get characterId => text()();

  /// 一句状态（「平静」「专注」「心疼」…）。
  TextColumn get name => text().withDefault(const Constant('平静'))();

  RealColumn get valence => real().withDefault(const Constant(0.58))();

  RealColumn get affection => real().withDefault(const Constant(0.45))();

  RealColumn get energy => real().withDefault(const Constant(0.6))();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{characterId};
}

/// `mood_history` — 情绪轨迹（按角色隔离；裁剪到最近 200 条）。
@DataClassName('MoodHistoryRow')
@TableIndex(name: 'mood_history_scope', columns: {#characterId, #createdAt})
class MoodHistory extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属角色卡（隔离键）。
  TextColumn get characterId => text().withDefault(const Constant(''))();

  TextColumn get name => text().withDefault(const Constant('平静'))();

  RealColumn get valence => real().withDefault(const Constant(0.58))();

  RealColumn get affection => real().withDefault(const Constant(0.45))();

  RealColumn get energy => real().withDefault(const Constant(0.6))();

  /// 触发原因（`tired+decay` 之类）。
  TextColumn get reason => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
}

/// `persona_traits` — 两侧表达倾向。
///
/// 类名不能叫 `PersonaTraits`（`lib/core/brain/persona.dart` 已有同名模型），
/// 所以用 [tableName] 钉死表名。
@DataClassName('PersonaTraitRow')
class PersonaTraitRows extends Table {
  @override
  String get tableName => 'persona_traits';

  /// 所属角色卡（隔离键，进主键）。
  TextColumn get characterId => text().withDefault(const Constant(''))();

  /// `user` / `self`。
  TextColumn get side => text()();

  /// 倾向键（`directness` / `warmth` …）。
  TextColumn get key => text()();

  /// 0..1 当前值。
  RealColumn get value => real().withDefault(const Constant(0.5))();

  /// 0..1 基线（按天回归到这里）。
  RealColumn get baseline => real().withDefault(const Constant(0.5))();

  IntColumn get hitCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{characterId, side, key};
}

// ---------------------------------------------------------------------------
// v0.4.35：移植 dsh-brain 的角色版本 / 实体档案 / 表意识槽位（schemaVersion 6）
//
// 一律带 `characterId`：App 里「一张角色卡 = 一个记忆域」，实体和角色定义都不能
// 跨卡串。表意识槽位还带 `sessionId`（同一张卡下不同会话的"眼下在说谁"互不干扰）。
// ---------------------------------------------------------------------------

/// 角色定义的版本历史（模型每修订一次落一版，可回溯）。
@DataClassName('CharacterVersionRow')
@TableIndex(name: 'character_versions_at', columns: {#characterId, #version})
class CharacterVersions extends Table {
  TextColumn get characterId => text()();

  IntColumn get version => integer()();

  TextColumn get definition => text().withDefault(const Constant(''))();

  /// `bootstrap` / `revise` / `fallback`。
  TextColumn get reason => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{characterId, version};
}

/// 实体档案（患者 / 客户 / 项目 / 宠物）。
@DataClassName('EntityRow')
@TableIndex(name: 'entities_scope', columns: {#characterId, #name})
@TableIndex(name: 'entities_updated', columns: {#characterId, #updatedAt})
class Entities extends Table {
  TextColumn get id => text()();

  TextColumn get characterId => text().withDefault(const Constant(''))();

  /// `patient` / `client` / `project` / `pet`。
  TextColumn get kind => text().withDefault(const Constant('patient'))();

  /// 归一化后的名字（`患者张三` → `张三`）。
  TextColumn get name => text()();

  /// 别名 JSON 数组（同一个人被叫过的其他名字）。
  TextColumn get aliasesJson => text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 挂在实体上的要点（`kind` 白名单见 brain_entities.dart：主诉/辨证/处方…）。
@DataClassName('EntityFactRow')
@TableIndex(name: 'entity_facts_scope', columns: {#entityId, #createdAt})
class EntityFacts extends Table {
  TextColumn get id => text()();

  TextColumn get characterId => text().withDefault(const Constant(''))();

  TextColumn get entityId => text()();

  TextColumn get kind => text().withDefault(const Constant('备注'))();

  /// `≤120 字`（列名带前缀，避免和 drift 的 `text()` 撞名）。
  TextColumn get factText => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 实体 ↔ 消息（哪些原文聊到过这个对象；原文仍在 `messages` 里）。
@DataClassName('EntityTurnRow')
@TableIndex(name: 'entity_turns_scope', columns: {#entityId})
class EntityTurns extends Table {
  TextColumn get characterId => text().withDefault(const Constant(''))();

  TextColumn get entityId => text()();

  TextColumn get messageId => text()();

  /// 当时用户那句话的片段（`≤80 字`）。存一份是为了注入时显示「聊到：…」，
  /// 不必再去解 `messages.content`（那可能是 blocks JSON）。
  TextColumn get snippet => text().withDefault(const Constant(''))();

  DateTimeColumn get at => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{entityId, messageId};
}

/// 表意识槽位：「眼下在说谁」（每个会话最多 3 个实体 id + 时间，带 TTL）。
@DataClassName('BrainWmStateRow')
class BrainWmState extends Table {
  TextColumn get characterId => text().withDefault(const Constant(''))();

  TextColumn get sessionId => text()();

  /// JSON：`{"ids":["e1"],"at":"2026-11-27T..."}`。
  TextColumn get dataJson => text().withDefault(const Constant('{}'))();

  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{sessionId};
}

// ---------------------------------------------------------------------------
// 数据库
// ---------------------------------------------------------------------------

/// 应用数据库。DB 文件 `keepsake.sqlite`，位于 `getApplicationSupportDirectory()`。
@DriftDatabase(
  tables: <Type>[
    Sessions,
    Messages,
    Attachments,
    SessionSummaries,
    SummaryCaches,
    Characters,
    MemoryFacts,
    MemoryEpisodes,
    MemoryRecallStats,
    MoodStates,
    MoodHistory,
    PersonaTraitRows,
    CharacterVersions,
    Entities,
    EntityFacts,
    EntityTurns,
    BrainWmState,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] 只用于测试注入；生产走 `driftDatabase(name: 'keepsake')`。
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// 测试/备用：内存库。
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // 逐版本 ALTER TABLE ADD COLUMN（老库来自 Keepsake 0.4.2 之前的版本）。
          if (from < 2) {
            // v1 → v2：消息分支 + 附件服务端 id + 摘要表。
            await _tryAddColumn(m, messages, messages.rootMessageId);
            await _tryAddColumn(m, messages, messages.currentMessageId);
            await _tryAddColumn(m, sessions, sessions.rootMessageId);
            await _tryAddColumn(m, sessions, sessions.currentMessageId);
            await _tryAddColumn(m, attachments, attachments.fileId);
            await _tryAddColumn(m, attachments, attachments.width);
            await _tryAddColumn(m, attachments, attachments.height);
            await m.createTable(sessionSummaries);
            await m.createTable(summaryCaches);
          }
          if (from < 3) {
            // v2 → v3：会话级联网搜索开关 + 手动排序。
            await _tryAddColumn(m, sessions, sessions.searchEnabled);
            await _tryAddColumn(m, sessions, sessions.sort);
            await _tryAddColumn(m, sessionSummaries, sessionSummaries.summaryChars);
            await _tryAddColumn(m, summaryCaches, summaryCaches.summary);
            await _tryAddColumn(m, summaryCaches, summaryCaches.summaryChars);
          }
          if (from < 4) {
            // v3 → v4：角色卡 + App 内「自带大脑」（记忆 / 情绪 / 人格）。
            // `createTable` 用 `CREATE TABLE IF NOT EXISTS`，重复执行安全。
            await m.createTable(characters);
            await m.createTable(memoryFacts);
            await m.createTable(memoryEpisodes);
            await m.createTable(memoryRecallStats);
            await m.createTable(moodStates);
            await m.createTable(moodHistory);
            await m.createTable(personaTraitRows);
            // 老会话没有角色：先留 NULL，读取时按需建默认卡（不在这里批量建卡，
            // 避免一次导入几千会话时启动卡死）。
            await _tryAddColumn(m, sessions, sessions.characterId);
          }
          if (from < 5) {
            // v4 → v5：会话级思考/上下文覆盖值（`NULL` = 未覆盖，回落全局默认）。
            // 只在聊天页写入，设置页仍是全局默认值。
            await _tryAddColumn(m, sessions, sessions.thinkingEnabled);
            await _tryAddColumn(m, sessions, sessions.thinkingLevel);
            await _tryAddColumn(m, sessions, sessions.contextKeepRounds);
          }
          if (from < 6) {
            // v5 → v6（v0.4.35）：移植 dsh-brain 的三层 —— 角色自我定义（模型写、
            // 带版本历史）、实体档案（患者/客户/项目）、表意识槽位（"眼下在说谁"）。
            await _tryAddColumn(m, characters, characters.definition);
            await _tryAddColumn(m, characters, characters.definitionVersion);
            await _tryAddColumn(m, characters, characters.definitionSource);
            await _tryAddColumn(m, characters, characters.definitionEvidence);
            await m.createTable(characterVersions);
            await m.createTable(entities);
            await m.createTable(entityFacts);
            await m.createTable(entityTurns);
            await m.createTable(brainWmState);
          }
          // 兜底：缺表/缺索引补齐。注意不能直接 `m.createAll()`：
          // 老库的索引已经存在，createAll 会再次 CREATE INDEX 报
          // `index sessions_updated already exists`（真机迁移红屏的根因）。
          for (final entity in allSchemaEntities) {
            try {
              if (entity is TableInfo) {
                await m.createTable(entity as TableInfo<Table, dynamic>);
              } else if (entity is Index) {
                await m.createIndex(entity as Index);
              }
            } catch (_) {
              // 已存在 / 不适用：迁移是尽力而为，不阻塞启动。
            }
          }
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _tryAddColumn(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    try {
      await m.addColumn(table, column);
    } catch (_) {
      // 列已存在 / 表不存在：迁移是尽力而为，不阻塞启动。
    }
  }

  // -------------------------------------------------------------------------
  // 会话
  // -------------------------------------------------------------------------

  /// 新建会话并返回 id。可传外部 id（导入的 DeepSeek 会话保留原 id）。
  ///
  /// [presetId] / [model] 目前仅**接收**不落库：db-schema §2 的 sessions 表没有这两列
  /// （会话级平台/模型由 ChatController 在内存里持有）。
  ///
  /// [searchEnabled] 是会话级联网搜索的**初始值**：调用方传设置页「对话默认」里的
  /// 默认值，新会话才会一开始就是打开的。这一列非空、DDL 默认 `false`，不传就等于
  /// 「关」；`ChatController` 读到 `false` 会当成会话级选择，不再回落到全局设置。
  Future<String> createSession({
    String? id,
    String? title,
    String? presetId,
    String? model,
    String? characterId,
    bool? searchEnabled,
  }) async {
    final sessionId = (id == null || id.isEmpty) ? const Uuid().v4() : id;
    final now = DateTime.now();
    await into(sessions).insertOnConflictUpdate(
      SessionsCompanion.insert(
        id: sessionId,
        title: Value(title ?? ''),
        createdAt: Value(now),
        updatedAt: Value(now),
        characterId: Value(characterId),
        searchEnabled: searchEnabled == null
            ? const Value<bool>.absent()
            : Value<bool>(searchEnabled),
      ),
    );
    return sessionId;
  }

  /// 删除会话及其消息 / 附件 / 摘要（messages 有 FK 级联，其余显式删）。
  Future<void> deleteSession(String id) async {
    await transaction(() async {
      await (delete(attachments)..where((t) => t.sessionId.equals(id))).go();
      await (delete(messages)..where((t) => t.sessionId.equals(id))).go();
      await (delete(sessionSummaries)..where((t) => t.sessionId.equals(id))).go();
      await (delete(summaryCaches)..where((t) => t.sessionId.equals(id))).go();
      await (delete(sessions)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 批量删除会话及其消息 / 附件 / 摘要（一个事务，按块规避 SQLite 变量上限）。
  ///
  /// 逐条调用 [deleteSession] 时每条都开一个事务（4 张表 + 级联），会话上千条
  /// 就会慢到几十秒甚至十几分钟——用户看到的就是「点了删除按钮没反应」。
  /// 整批放进同一个事务后，几千条也是秒级。
  Future<void> deleteSessions(
    Iterable<String> ids, {
    void Function(int done, int total)? onProgress,
  }) async {
    final List<String> list =
        ids.where((id) => id.isNotEmpty).toList(growable: false);
    if (list.isEmpty) return;
    final int total = list.length;
    var done = 0;
    // SQLite 默认最多 999 个绑定变量，按 400 分块留余量。
    const int chunk = 400;
    await transaction(() async {
      for (var start = 0; start < list.length; start += chunk) {
        final int end =
            start + chunk < list.length ? start + chunk : list.length;
        final List<String> part = list.sublist(start, end);
        await (delete(attachments)..where((t) => t.sessionId.isIn(part))).go();
        await (delete(messages)..where((t) => t.sessionId.isIn(part))).go();
        await (delete(sessionSummaries)..where((t) => t.sessionId.isIn(part)))
            .go();
        await (delete(summaryCaches)..where((t) => t.sessionId.isIn(part))).go();
        await (delete(sessions)..where((t) => t.id.isIn(part))).go();
        done += part.length;
        onProgress?.call(done, total);
      }
    });
  }

  /// 更新 `updated_at`（可选同时改标题/消息数）。
  Future<void> touchSession(String id, {String? title, int? messageCount}) async {
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(
        updatedAt: Value(DateTime.now()),
        title: title == null ? const Value<String>.absent() : Value(title),
        messageCount: messageCount == null ? const Value<int>.absent() : Value(messageCount),
      ),
    );
  }

  Future<void> renameSession(String id, String title) async {
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setSessionSearchEnabled(String id, bool enabled) async {
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(searchEnabled: Value(enabled)),
    );
  }

  /// 写会话级「深度思考」覆盖值（`null` = 清空覆盖，回落全局默认）。
  Future<void> setSessionThinkingEnabled(String id, bool? enabled) async {
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(thinkingEnabled: Value<bool?>(enabled)),
    );
  }

  /// 写会话级「思考强度」覆盖值（传 `ThinkingLevel.wireName`；`null` = 清空覆盖）。
  Future<void> setSessionThinkingLevel(String id, String? wireName) async {
    final normalized = wireName?.trim() ?? '';
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(
        thinkingLevel: Value<String?>(
          normalized.isEmpty ? null : normalized,
        ),
      ),
    );
  }

  /// 写会话级上下文预算覆盖值（`null` = 清空覆盖，回落全局默认）。
  Future<void> setSessionContextKeepRounds(String id, int? rounds) async {
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(contextKeepRounds: Value<int?>(rounds)),
    );
  }

  Future<void> setSessionSort(String id, int? sort) async {
    await (update(sessions)..where((t) => t.id.equals(id))).write(
      SessionsCompanion(
        sort: sort == null ? const Value<int>.absent() : Value(sort),
      ),
    );
  }

  Future<bool> hasSession(String id) async {
    final row = await (select(sessions)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null;
  }

  Future<List<Session>> allSessions() => _orderedSessions().get();

  /// 会话列表流（置顶在前，再按 `updated_at` 倒序）。
  Stream<List<Session>> watchSessions() => _orderedSessions().watch();

  Selectable<Session> _orderedSessions() => select(sessions)
    ..orderBy(<OrderingTerm Function(Sessions)>[
      (t) => OrderingTerm(expression: t.sort, mode: OrderingMode.asc, nulls: NullsOrder.last),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);

  Future<Session?> sessionById(String id) =>
      (select(sessions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 把会话绑到某个角色（`null` = 解绑）。
  Future<void> setSessionCharacter(String sessionId, String? characterId) async {
    await (update(sessions)..where((t) => t.id.equals(sessionId))).write(
      SessionsCompanion(
        characterId: characterId == null || characterId.isEmpty
            ? const Value<String?>.absent()
            : Value<String?>(characterId),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 角色卡
  // -------------------------------------------------------------------------

  /// 新建角色卡并返回行。
  ///
  /// v0.4.35 起角色卡多了一层「模型写的自我定义」（`definition`），建卡时为空，
  /// 等第一次后台整理再 bootstrap。
  Future<CharacterRow> createCharacter({
    String? id,
    required String name,
    String prompt = '',
    String? description,
    String emoji = '🤖',
    String source = 'manual',
    String definition = '',
    int definitionVersion = 0,
    String definitionSource = '',
    int definitionEvidence = 0,
  }) async {
    final now = DateTime.now();
    final card = CharacterRow(
      id: (id == null || id.isEmpty) ? const Uuid().v4() : id,
      name: name.trim().isEmpty ? '未命名角色' : name.trim(),
      prompt: prompt,
      description: description,
      emoji: emoji.trim().isEmpty ? '🤖' : emoji.trim(),
      source: source,
      createdAt: now,
      updatedAt: now,
      definition: definition,
      definitionVersion: definitionVersion,
      definitionSource: definitionSource,
      definitionEvidence: definitionEvidence,
    );
    await into(characters).insert(card);
    return card;
  }

  /// 更新角色卡（只改传入的字段）。
  Future<void> updateCharacter(
    String id, {
    String? name,
    String? prompt,
    String? description,
    String? emoji,
  }) async {
    await (update(characters)..where((t) => t.id.equals(id))).write(
      CharactersCompanion(
        name: name == null ? const Value<String>.absent() : Value(name),
        prompt: prompt == null ? const Value<String>.absent() : Value(prompt),
        description: description == null
            ? const Value<String>.absent()
            : Value<String?>(description),
        emoji: emoji == null ? const Value<String>.absent() : Value(emoji),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<CharacterRow?> characterById(String id) =>
      (select(characters)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<CharacterRow>> allCharacters() => (select(characters)
        ..orderBy(<OrderingTerm Function(Characters)>[
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        ]))
      .get();

  /// 角色列表流（按 `updated_at` 倒序）。
  Stream<List<CharacterRow>> watchCharacters() => (select(characters)
        ..orderBy(<OrderingTerm Function(Characters)>[
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        ]))
      .watch();

  /// 每个角色的会话数（`characterId → count`）。
  Future<Map<String, int>> sessionCountsByCharacter() async {
    final rows = await customSelect(
      'SELECT character_id, COUNT(*) AS n FROM sessions '
      "WHERE character_id IS NOT NULL AND character_id <> '' "
      'GROUP BY character_id',
      readsFrom: <ResultSetImplementation>{sessions},
    ).get();
    return <String, int>{
      for (final row in rows)
        row.read<String>('character_id'): row.read<int>('n'),
    };
  }

  /// 某个角色下的会话 id（删角色时决定「删会话 / 仅解绑」用）。
  Future<List<String>> sessionIdsOfCharacter(String characterId) async {
    final rows = await (select(sessions)
          ..where((t) => t.characterId.equals(characterId)))
        .get();
    return <String>[for (final row in rows) row.id];
  }

  /// 删除角色卡本身（**不动**会话）：会话的 `character_id` 先解绑。
  Future<void> deleteCharacter(String id) async {
    await transaction(() async {
      await (update(sessions)..where((t) => t.characterId.equals(id)))
          .write(const SessionsCompanion(characterId: Value<String?>(null)));
      await (delete(characters)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 会话 flags 位域（[推断] 置顶/归档/已读）。
  Future<int> sessionFlags(String id) async {
    final row = await sessionById(id);
    return row?.flags ?? 0;
  }

  /// 置/清某个 flag 位。
  Future<void> setSessionFlag(String sessionId, int flag, {bool enabled = true}) async {
    final current = await sessionFlags(sessionId);
    final next = enabled ? (current | flag) : (current & ~flag);
    await (update(sessions)..where((t) => t.id.equals(sessionId)))
        .write(SessionsCompanion(flags: Value(next)));
  }

  /// 设置会话当前分支节点。
  Future<void> setSessionCurrentMessage(String sessionId, String? messageId) async {
    await (update(sessions)..where((t) => t.id.equals(sessionId))).write(
      SessionsCompanion(
        currentMessageId: messageId == null
            ? const Value<String>.absent()
            : Value(messageId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 消息
  // -------------------------------------------------------------------------

  /// 追加一条消息（自动维护 `message_count` / `updated_at`）。
  Future<void> addMessage({
    required String id,
    required String sessionId,
    required String role,
    required String content,
    DateTime? createdAt,
    String? rootMessageId,
    String? currentMessageId,
    int? index,
    int flags = 0,
  }) async {
    final session = await sessionById(sessionId);
    final nextIndex = index ?? (session?.messageCount ?? 0);
    await transaction(() async {
      await into(messages).insertOnConflictUpdate(
        MessagesCompanion.insert(
          id: id,
          sessionId: sessionId,
          role: role,
          content: Value(content),
          createdAt: Value(createdAt ?? DateTime.now()),
          rootMessageId: Value(rootMessageId),
          currentMessageId: Value(currentMessageId),
          index: Value(nextIndex),
          flags: Value(flags),
        ),
      );
      await touchSession(sessionId, messageCount: nextIndex + 1);
    });
  }

  /// Companion 版插入（同样维护 session 计数）。
  Future<void> insertMessage(MessagesCompanion message) async {
    final sessionId = message.sessionId.value;
    final session = await sessionById(sessionId);
    final nextIndex = session?.messageCount ?? 0;
    await transaction(() async {
      await into(messages).insertOnConflictUpdate(message);
      await touchSession(sessionId, messageCount: nextIndex + 1);
    });
  }

  Future<void> updateMessage(
    String id, {
    String? content,
    int? flags,
    String? rootMessageId,
    String? currentMessageId,
    int? index,
  }) async {
    await (update(messages)..where((t) => t.id.equals(id))).write(
      MessagesCompanion(
        content: content == null ? const Value<String>.absent() : Value(content),
        flags: flags == null ? const Value<int>.absent() : Value(flags),
        rootMessageId: rootMessageId == null
            ? const Value<String>.absent()
            : Value(rootMessageId),
        currentMessageId: currentMessageId == null
            ? const Value<String>.absent()
            : Value(currentMessageId),
        index: index == null ? const Value<int>.absent() : Value(index),
      ),
    );
  }

  /// Companion 版更新（按 id；id 必须在 companion 里）。
  Future<void> updateMessageRow(MessagesCompanion message) async {
    final id = message.id.value;
    await (update(messages)..where((t) => t.id.equals(id))).write(message);
  }

  Future<void> deleteMessage(String id) async {
    final row = await messageById(id);
    await (delete(messages)..where((t) => t.id.equals(id))).go();
    if (row != null) {
      final session = await sessionById(row.sessionId);
      final next = (session?.messageCount ?? 1) - 1;
      await touchSession(row.sessionId, messageCount: next < 0 ? 0 : next);
    }
  }

  Future<Message?> messageById(String id) =>
      (select(messages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Message>> messagesOf(String sessionId) => sortedMessages(sessionId);

  /// 按 `index` 升序（同序时按 created_at）。
  Future<List<Message>> sortedMessages(String sessionId) => (select(messages)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy(<OrderingTerm Function(Messages)>[
          (t) => OrderingTerm(expression: t.index, mode: OrderingMode.asc),
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
        ]))
      .get();

  /// 消息流（响应式，UI 用）。
  Stream<List<Message>> watchMessages(String sessionId) => streamMessages(sessionId);

  Stream<List<Message>> streamMessages(String sessionId) => (select(messages)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy(<OrderingTerm Function(Messages)>[
          (t) => OrderingTerm(expression: t.index, mode: OrderingMode.asc),
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
        ]))
      .watch();

  /// 会话第一条消息 id（无消息返回 null）。
  Future<String?> firstMessageIdOf(String sessionId) async {
    final row = await (select(messages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy(<OrderingTerm Function(Messages)>[
            (t) => OrderingTerm(expression: t.index, mode: OrderingMode.asc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  /// 分支：同一 `root_message_id` 下的兄弟消息（按 created_at 升序）。
  Future<List<Message>> branchesOf(String rootMessageId) => (select(messages)
        ..where((t) => t.rootMessageId.equals(rootMessageId))
        ..orderBy(<OrderingTerm Function(Messages)>[
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
        ]))
      .get();

  // -------------------------------------------------------------------------
  // 附件
  // -------------------------------------------------------------------------

  Future<List<Attachment>> attachmentsOfSession(String sessionId) =>
      (select(attachments)..where((t) => t.sessionId.equals(sessionId))).get();

  Future<List<Attachment>> allAttachments() => select(attachments).get();

  Future<Attachment?> attachmentById(String id) =>
      (select(attachments)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 按 DeepSeek Files API 的服务端 id 反查（导入去重 / 复用上传结果）。
  Future<Attachment?> attachmentByServerId(String fileId) =>
      (select(attachments)..where((t) => t.fileId.equals(fileId))).getSingleOrNull();

  Future<void> upsertAttachment({
    required String id,
    required String sessionId,
    String? messageId,
    required String fileName,
    int fileSize = 0,
    String mime = '',
    String path = '',
    int? width,
    int? height,
    String? fileId,
    String? url,
  }) async {
    await into(attachments).insertOnConflictUpdate(
      AttachmentsCompanion.insert(
        id: id,
        sessionId: sessionId,
        messageId: Value(messageId),
        fileName: Value(fileName),
        fileSize: Value(fileSize),
        mime: Value(mime),
        path: Value(path),
        width: Value(width),
        height: Value(height),
        fileId: Value(fileId),
        url: Value(url),
      ),
    );
  }

  Future<void> upsertAttachmentRow(AttachmentsCompanion attachment) async {
    await into(attachments).insertOnConflictUpdate(attachment);
  }

  Future<void> deleteAttachment(String id) async {
    await (delete(attachments)..where((t) => t.id.equals(id))).go();
  }

  // -------------------------------------------------------------------------
  // 摘要 / 摘要缓存
  // -------------------------------------------------------------------------

  Future<SummaryCache?> summaryCacheOf(String sessionId) =>
      (select(summaryCaches)..where((t) => t.sessionId.equals(sessionId)))
          .getSingleOrNull();

  Future<void> saveSummaryCache({
    required String sessionId,
    required String contextSummary,
    String? summary,
    int summaryChars = 0,
  }) async {
    await into(summaryCaches).insertOnConflictUpdate(
      SummaryCachesCompanion.insert(
        sessionId: sessionId,
        contextSummary: Value(contextSummary),
        summary: Value(summary ?? contextSummary),
        summaryChars: Value(summaryChars > 0 ? summaryChars : contextSummary.length),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<SessionSummary?> sessionSummaryOf(String sessionId) =>
      (select(sessionSummaries)..where((t) => t.sessionId.equals(sessionId)))
          .getSingleOrNull();

  Future<void> saveSessionSummary({
    required String sessionId,
    required String summary,
    int summaryChars = 0,
  }) async {
    final now = DateTime.now();
    await into(sessionSummaries).insertOnConflictUpdate(
      SessionSummariesCompanion.insert(
        sessionId: sessionId,
        summary: Value(summary),
        summaryChars: Value(summaryChars > 0 ? summaryChars : summary.length),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deleteSummaryOf(String sessionId) async {
    await (delete(sessionSummaries)..where((t) => t.sessionId.equals(sessionId))).go();
    await (delete(summaryCaches)..where((t) => t.sessionId.equals(sessionId))).go();
  }

  // -------------------------------------------------------------------------
  // 全局搜索（唯一一条完整业务 SQL，来自 libapp.so，[确定]）
  // -------------------------------------------------------------------------

  /// 按消息正文 LIKE 命中，返回消息 + 所属会话标题；
  /// 另外把「标题命中」作为 `messageId == ''` 的条目追加（UI 文案「标题匹配 · 」）。
  Future<List<SessionSearchHit>> searchSessions(String q, {int limit = 50}) async {
    final query = q.trim();
    if (query.isEmpty) return const <SessionSearchHit>[];
    final pattern = '%${_escapeLike(query)}%';

    // 原文 SQL（db-schema.md §1）：
    // SELECT m.id, m.session_id, m.content, m.created_at, s.title, s.updated_at
    // FROM messages m JOIN sessions s ON s.id = m.session_id
    // WHERE m.content LIKE ?1 ESCAPE '\'
    // ORDER BY m.created_at DESC LIMIT ?2
    final rows = await customSelect(
      "SELECT m.id, m.session_id, m.content, m.created_at, s.title, s.updated_at "
      'FROM messages m JOIN sessions s ON s.id = m.session_id '
      "WHERE m.content LIKE ?1 ESCAPE '\\' "
      'ORDER BY m.created_at DESC LIMIT ?2',
      variables: <Variable<Object>>[
        Variable<String>(pattern),
        Variable<int>(limit),
      ],
      readsFrom: <ResultSetImplementation>{messages, sessions},
    ).get();

    final hits = <SessionSearchHit>[
      for (final row in rows)
        SessionSearchHit(
          messageId: row.read<String>('id'),
          sessionId: row.read<String>('session_id'),
          content: row.read<String>('content'),
          createdAt: _secondsToDate(row.read<int>('created_at')),
          sessionTitle: row.read<String>('title'),
          sessionUpdatedAt: _secondsToDate(row.read<int>('updated_at')),
        ),
    ];

    // 标题命中（与正文命中不重复）。
    final titleRows = await customSelect(
      'SELECT s.id, s.title, s.updated_at FROM sessions s '
      "WHERE s.title LIKE ?1 ESCAPE '\\' "
      'ORDER BY s.updated_at DESC LIMIT ?2',
      variables: <Variable<Object>>[
        Variable<String>(pattern),
        Variable<int>(limit),
      ],
      readsFrom: <ResultSetImplementation>{sessions},
    ).get();
    for (final row in titleRows) {
      final sessionId = row.read<String>('id');
      if (hits.any((h) => h.sessionId == sessionId)) continue;
      final updatedAt = _secondsToDate(row.read<int>('updated_at'));
      hits.add(
        SessionSearchHit(
          messageId: '',
          sessionId: sessionId,
          content: '',
          createdAt: updatedAt,
          sessionTitle: row.read<String>('title'),
          sessionUpdatedAt: updatedAt,
        ),
      );
    }
    return hits;
  }

  static DateTime _secondsToDate(int? seconds) => seconds == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  /// LIKE 通配符转义（SQL 里 `ESCAPE '\'`）。
  static String _escapeLike(String input) => input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

/// 全量搜索的单条命中（符号证据：`SessionSearchHit`，db-schema.md §4）。
class SessionSearchHit {
  const SessionSearchHit({
    required this.messageId,
    required this.sessionId,
    required this.content,
    required this.createdAt,
    required this.sessionTitle,
    required this.sessionUpdatedAt,
  });

  /// 命中的消息 id；标题命中时为 `''`（会话级命中）。
  final String messageId;

  final String sessionId;

  /// 命中的消息正文；标题命中时为 `''`。
  final String content;

  final DateTime createdAt;

  final String sessionTitle;

  final DateTime sessionUpdatedAt;

  /// 是否只是标题命中。
  bool get isTitleHit => messageId.isEmpty;

  @override
  String toString() => 'SessionSearchHit($sessionId, $messageId)';
}

/// 会话 flags 位（[推断]：置顶 / 归档 / 已读）。位值可调，只有自洽性要求。
abstract final class SessionFlag {
  static const int pinned = 1 << 0;
  static const int archived = 1 << 1;
  static const int read = 1 << 2;
}

/// 消息 flags 位（[推断]：已压缩 / 已总结 / 错误）。
abstract final class MessageFlag {
  static const int summarized = 1 << 0;
  static const int error = 1 << 1;
}

/// 打开数据库：`keepsake.sqlite` 放在 `getApplicationSupportDirectory()`。
QueryExecutor _openConnection() => driftDatabase(
      name: 'keepsake',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
