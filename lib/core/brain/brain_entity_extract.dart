/// 实体层的**睡眠期结构化巩固**（v0.4.35，移植自 dsh-brain 的
/// `maybeExtractEntityFacts`）：低频让模型把对话压成「主诉/辨证/处方/复诊」字段。
///
/// 规则抽取只存原话片段；字段化必须靠模型。这里保持插件的三条约束：
/// - 只接受**已知对象**（名单由调用方给，模型写别的直接丢）；
/// - 同文本去重；
/// - 失败静默（不覆盖、不阻塞）。
library;

import '../api/chat_backend.dart';
import '../db/database.dart';
import 'brain_character.dart' show completeOnceText;
import 'brain_entities.dart';
import 'brain_entities_store.dart';

/// 跑一次结构化抽取；返回写入了多少条新字段。
Future<int> runEntityExtraction({
  required AppDatabase db,
  required ChatBackend backend,
  required String characterId,
  required List<ExtractTurn> turns,
  int maxNames = 8,
}) async {
  if (turns.isEmpty) return 0;
  final store = BrainEntityStore(db);
  final roster = await store.listForCharacter(characterId, limit: 50);
  if (roster.isEmpty) return 0;

  // 只抽本批对话里真正提到的对象。
  final mentioned = <String>{};
  for (final turn in turns) {
    final text = '${turn.user}\n${turn.assistant}';
    for (final entity in await store.resolveMentions(characterId, text, limit: 5)) {
      mentioned.add(entity.name);
    }
  }
  if (mentioned.isEmpty) return 0;
  final names = mentioned.take(maxNames).toList(growable: false);

  final request = buildEntityExtractMessages(turns: turns, names: names);
  try {
    final raw = await completeOnceText(
      backend: backend,
      system: request.system,
      user: request.user,
      maxTokens: 700,
    );
    final parsed = parseEntityExtraction(raw);
    var applied = 0;
    for (final item in parsed) {
      if (!names.contains(item.name)) continue;
      applied += await store.applyExtraction(
        characterId: characterId,
        name: item.name,
        facts: item.facts,
      );
    }
    return applied;
  } catch (_) {
    // 抽取失败不影响任何东西（规则层已经记过原话）
    return 0;
  }
}
