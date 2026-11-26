/// App 内「自带大脑」的**角色层**（v0.4.35，移植自 dsh-brain 的 `character.js`）。
///
/// 与「角色卡人设」的区别：
/// - `characters.prompt`：**用户写的**人设（静态，设置页可改）；
/// - `characters.definition`：**模型从对话里长出来的**自我定义（bootstrap 一次，
///   之后每攒够 N 轮新证据修订一次，带版本历史）。
///
/// 为什么要分开：用户填的"人设"是期望，模型写的"我是谁"是实际长成的样子——
/// 两者会漂移，漂移本身就是信息，别混成一个字段。
library;

import 'package:drift/drift.dart';

import '../api/chat_backend.dart';
import '../db/database.dart';
import 'brain_entities.dart' show flattenText;

/// 自我定义的注入标题。
const String kCharacterSectionTitle = '【我是谁】';

/// bootstrap 的 system prompt。
const String kCharacterBootstrapPrompt = '你在为「长期陪伴型 AI 助手」写一份自我定义。\n'
    '依据：用户给这张角色卡起的名字、用户写下的人设（可能为空）、以及最近几轮真实对话。\n'
    '要求：\n'
    '- 用第一人称写 120–260 字，像"我是谁、我怎么说话、我在意什么"；\n'
    '- 只写对话里**有证据**的特质，没有证据就别编；\n'
    '- 不要罗列对话内容，不要写成总结；\n'
    '- 不要提到"角色卡""系统提示"这类词；\n'
    '- 直接输出正文，不要标题、不要 Markdown。';

/// 修订的 system prompt。
const String kCharacterRevisePrompt = '你在修订一份「AI 助手的自我定义」。\n'
    '给你当前的定义、用户写的人设、以及最近几轮新对话。\n'
    '要求：\n'
    '- 保留仍然成立的部分，只把**有证据**的新特质写进去，删掉明显不再成立的；\n'
    '- 第一人称、120–300 字；\n'
    '- 不要罗列对话内容；直接输出正文，不要标题、不要 Markdown。';

/// 一轮对话样本。
typedef CharacterTurn = ({String user, String assistant});

String _renderTurns(List<CharacterTurn> turns, {int maxTurns = 6}) {
  final lines = <String>[];
  for (final turn in turns.take(maxTurns)) {
    lines.add('用户：${flattenText(turn.user, maxChars: 220)}');
    lines.add('助手：${flattenText(turn.assistant, maxChars: 220)}');
    lines.add('');
  }
  return lines.join('\n').trim();
}

String _cardPromptLine(String? cardPrompt) {
  final persona = (cardPrompt ?? '').trim();
  return persona.isEmpty ? '（用户没有写人设）' : flattenText(persona, maxChars: 400);
}

/// 组装 bootstrap 的 system + user（纯函数）。
({String system, String user}) buildCharacterBootstrapMessages({
  required String name,
  String? cardPrompt,
  List<CharacterTurn> turns = const <CharacterTurn>[],
}) {
  final who = name.trim().isEmpty ? '未命名角色' : name.trim();
  final body = <String>[
    '角色名：$who',
    '用户写的人设：${_cardPromptLine(cardPrompt)}',
    '',
    '最近几轮对话：',
    turns.isEmpty ? '（还没有对话）' : _renderTurns(turns),
  ].join('\n');
  return (system: kCharacterBootstrapPrompt, user: body);
}

/// 组装修订的 system + user（纯函数）。
({String system, String user}) buildCharacterReviseMessages({
  required String current,
  required String name,
  String? cardPrompt,
  List<CharacterTurn> turns = const <CharacterTurn>[],
}) {
  final who = name.trim().isEmpty ? '未命名角色' : name.trim();
  final body = <String>[
    '角色名：$who',
    '用户写的人设：${_cardPromptLine(cardPrompt)}',
    '',
    '当前定义：',
    flattenText(current, maxChars: 800),
    '',
    '最近几轮新对话：',
    turns.isEmpty ? '（没有新对话）' : _renderTurns(turns),
  ].join('\n');
  return (system: kCharacterRevisePrompt, user: body);
}

/// 清洗模型输出：去围栏、去标题行、去「自我定义：」前缀，压到 [maxChars]。
String normalizeCharacterDefinition(String? text, {int maxChars = 600}) {
  var value = (text ?? '').replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '').trim();
  if (value.isEmpty) return '';
  final kept = <String>[];
  for (final rawLine in value.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (RegExp(r'^#{1,6}\s').hasMatch(line)) continue;
    // 「自我定义：……」只去前缀，正文要留下（整行丢掉是最早版本的 bug）。
    line = line.replaceFirst(RegExp(r'^(自我定义|角色定义|定义)\s*[:：]\s*'), '');
    if (line.isEmpty) continue;
    kept.add(line);
  }
  value = kept.join('\n').trim();
  if (value.isEmpty) return '';
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars - 1)}…';
}

/// 无模型/模型失败时的规则兜底（**不编造**：只用人设与名字）。
String fallbackCharacterDefinition({
  required String name,
  String? cardPrompt,
  int maxChars = 600,
}) {
  final who = name.trim().isEmpty ? '未命名角色' : name.trim();
  final persona = (cardPrompt ?? '').trim();
  final base = persona.isEmpty
      ? '我是「$who」，一个长期陪在用户身边的助手。我会记住我们聊过的事，说话直接，不绕弯子。'
      : '我是「$who」，一个长期陪在用户身边的助手。我的设定是：'
          '${flattenText(persona, maxChars: 260)}';
  return normalizeCharacterDefinition(base, maxChars: maxChars);
}

/// 自我定义 → system prompt 追加段。
String characterDefinitionSection(String? definition, {int maxChars = 800}) {
  final value = (definition ?? '').trim();
  if (value.isEmpty) return '';
  final text = value.length <= maxChars ? value : '${value.substring(0, maxChars - 1)}…';
  return '$kCharacterSectionTitle\n$text';
}

// ---------------------------------------------------------------------------
// 存储
// ---------------------------------------------------------------------------

/// 角色定义的读写 + 版本历史（带 `characterId` 隔离）。
class CharacterDefinitionStore {
  CharacterDefinitionStore(this._db);

  final AppDatabase _db;

  Future<CharacterRow?> get(String characterId) => (_db.select(_db.characters)
        ..where((t) => t.id.equals(characterId)))
      .getSingleOrNull();

  Future<List<CharacterVersionRow>> versions(
    String characterId, {
    int limit = 5,
  }) {
    return (_db.select(_db.characterVersions)
          ..where((t) => t.characterId.equals(characterId))
          ..orderBy(<OrderClauseGenerator<$CharacterVersionsTable>>[
            (t) => OrderingTerm.desc(t.version),
          ])
          ..limit(limit))
        .get();
  }

  /// 存一版新定义（版本号自增，同时落版本历史与当前行）。
  Future<int> save({
    required String characterId,
    required String definition,
    required String source,
    required String reason,
    int evidence = 0,
  }) async {
    final current = await get(characterId);
    if (current == null) return 0;
    final version = current.definitionVersion + 1;
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.characters)..where((t) => t.id.equals(characterId)))
          .write(
        CharactersCompanion(
          definition: Value(definition),
          definitionVersion: Value(version),
          definitionSource: Value(source),
          definitionEvidence: Value(evidence),
          updatedAt: Value(now),
        ),
      );
      await _db.into(_db.characterVersions).insert(
            CharacterVersionRow(
              characterId: characterId,
              version: version,
              definition: definition,
              reason: reason,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
    return version;
  }

  /// 攒新证据（到阈值才修订）。
  Future<void> addEvidence(String characterId, {int delta = 1}) async {
    final current = await get(characterId);
    if (current == null) return;
    await (_db.update(_db.characters)..where((t) => t.id.equals(characterId)))
        .write(
      CharactersCompanion(
        definitionEvidence:
            Value(current.definitionEvidence + (delta < 0 ? 0 : delta)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 是否需要写新一版：还没 bootstrap，或证据攒够了。
  Future<bool> needsRevision(String characterId, {int everyTurns = 6}) async {
    final current = await get(characterId);
    if (current == null) return false;
    if (current.definitionVersion == 0) return true;
    return current.definitionEvidence >= (everyTurns < 1 ? 1 : everyTurns);
  }
}

// ---------------------------------------------------------------------------
// 后台跑一次（不 await，失败静默）
// ---------------------------------------------------------------------------

/// 一次一次性模型调用：拿完整正文（失败抛异常）。
///
/// 对话之外的低频后台任务（角色 bootstrap/修订、实体字段抽取）都复用它，
/// 这样"怎么发请求"只有一处。
Future<String> completeOnceText({
  required ChatBackend backend,
  required String system,
  required String user,
  int maxTokens = 420,
}) async {
  final request = ChatRequest(
    provider: backend.provider,
    messages: <ChatTurn>[ChatTurn.user(user)],
    systemPrompt: system,
    maxTokens: maxTokens,
    thinking: false,
  );
  final buffer = StringBuffer();
  await for (final event in backend.streamChat(request)) {
    if (event is TextDelta) {
      buffer.write(event.text);
    } else if (event is Failure) {
      throw StateError(event.error.message);
    } else if (event is Done) {
      break;
    }
  }
  return buffer.toString();
}

/// 首次 bootstrap：模型写第一版；失败时用规则兜底（标记 `fallback`）。
///
/// 返回是否写入了新版本。
Future<bool> runCharacterBootstrap({
  required AppDatabase db,
  required ChatBackend backend,
  required CharacterRow card,
  List<CharacterTurn> turns = const <CharacterTurn>[],
}) async {
  final store = CharacterDefinitionStore(db);
  final request = buildCharacterBootstrapMessages(
    name: card.name,
    cardPrompt: card.prompt,
    turns: turns,
  );
  String definition;
  var source = 'llm';
  try {
    final raw = await completeOnceText(
      backend: backend,
      system: request.system,
      user: request.user,
    );
    definition = normalizeCharacterDefinition(raw);
    if (definition.isEmpty) throw StateError('模型没有返回可用正文');
  } catch (_) {
    definition = fallbackCharacterDefinition(name: card.name, cardPrompt: card.prompt);
    source = 'fallback';
  }
  if (definition.isEmpty) return false;
  await store.save(
    characterId: card.id,
    definition: definition,
    source: source,
    reason: 'bootstrap',
  );
  return true;
}

/// 修订：带着当前定义与新对话再让模型写一版（同样失败不覆盖）。
Future<bool> runCharacterRevise({
  required AppDatabase db,
  required ChatBackend backend,
  required CharacterRow card,
  required String current,
  List<CharacterTurn> turns = const <CharacterTurn>[],
}) async {
  final store = CharacterDefinitionStore(db);
  final request = buildCharacterReviseMessages(
    current: current,
    name: card.name,
    cardPrompt: card.prompt,
    turns: turns,
  );
  String definition;
  try {
    final raw = await completeOnceText(
      backend: backend,
      system: request.system,
      user: request.user,
    );
    definition = normalizeCharacterDefinition(raw);
    if (definition.isEmpty) return false;
  } catch (_) {
    // 修订失败保留旧版（不降级成兜底，避免把已长成的定义冲掉）
    return false;
  }
  await store.save(
    characterId: card.id,
    definition: definition,
    source: 'llm',
    reason: 'revise',
  );
  return true;
}
