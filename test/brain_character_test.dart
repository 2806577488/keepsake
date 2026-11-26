import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/brain/brain_character.dart';
import 'package:keepsake/core/db/database.dart';

/// 角色层单测（v0.4.35，对应 dsh-brain 的 character.test.mjs）。
void main() {
  group('prompt 组装', () {
    test('bootstrap 带上名字与人设', () {
      final request = buildCharacterBootstrapMessages(
        name: '小林',
        cardPrompt: '说话直接，别客套',
        turns: const <CharacterTurn>[
          (user: '今天有点累', assistant: '那早点睡'),
        ],
      );
      expect(request.system.contains('第一人称'), true);
      expect(request.user.contains('小林'), true);
      expect(request.user.contains('说话直接'), true);
      expect(request.user.contains('今天有点累'), true);
    });

    test('没有对话时也不编', () {
      final request = buildCharacterBootstrapMessages(name: '小林');
      expect(request.user.contains('还没有对话'), true);
      expect(request.user.contains('用户没有写人设'), true);
    });

    test('修订带上当前定义', () {
      final request = buildCharacterReviseMessages(
        current: '我是小林，说话直接。',
        name: '小林',
        turns: const <CharacterTurn>[(user: '在忙', assistant: '好')],
      );
      expect(request.system.contains('保留仍然成立的部分'), true);
      expect(request.user.contains('我是小林'), true);
    });
  });

  group('normalizeCharacterDefinition', () {
    test('去掉围栏、标题行与「自我定义：」前缀', () {
      final text = normalizeCharacterDefinition(
        '```\n# 自我定义\n自我定义：我是小林。\n\n我说话直接。\n```',
      );
      expect(text, '我是小林。\n我说话直接。');
    });

    test('空输出返回空', () {
      expect(normalizeCharacterDefinition(''), '');
      expect(normalizeCharacterDefinition('   \n  '), '');
    });

    test('超长截断', () {
      final text = normalizeCharacterDefinition('字' * 1000, maxChars: 100);
      expect(text.length, 100);
      expect(text.endsWith('…'), true);
    });
  });

  group('fallbackCharacterDefinition', () {
    test('只用人设与名字，不编造细节', () {
      final text = fallbackCharacterDefinition(
        name: '小林',
        cardPrompt: '说话直接，别客套',
      );
      expect(text.contains('小林'), true);
      expect(text.contains('说话直接'), true);
    });

    test('没人设时给通用自述', () {
      final text = fallbackCharacterDefinition(name: '');
      expect(text.contains('未命名角色'), true);
    });
  });

  group('characterDefinitionSection', () {
    test('空定义不注入', () {
      expect(characterDefinitionSection(''), '');
      expect(characterDefinitionSection(null), '');
    });

    test('非空定义带标题', () {
      final section = characterDefinitionSection('我是小林，说话直接。');
      expect(section.startsWith('【我是谁】'), true);
      expect(section.contains('说话直接'), true);
    });
  });

  group('CharacterDefinitionStore', () {
    late AppDatabase db;
    late CharacterDefinitionStore store;
    late CharacterRow card;

    setUp(() async {
      db = AppDatabase.memory();
      store = CharacterDefinitionStore(db);
      card = await db.createCharacter(name: '小林', id: 'c1');
    });

    tearDown(() async {
      await db.close();
    });

    test('第一次保存成为 v1，并写版本历史', () async {
      final version = await store.save(
        characterId: card.id,
        definition: '我是小林，说话直接。',
        source: 'llm',
        reason: 'bootstrap',
      );
      expect(version, 1);
      final reloaded = await store.get(card.id);
      expect(reloaded!.definitionVersion, 1);
      expect(reloaded.definitionSource, 'llm');
      expect(reloaded.definition, '我是小林，说话直接。');

      final versions = await store.versions(card.id);
      expect(versions.length, 1);
      expect(versions.first.version, 1);
      expect(versions.first.reason, 'bootstrap');
    });

    test('再保存一版版本号自增', () async {
      await store.save(
        characterId: card.id,
        definition: 'v1',
        source: 'llm',
        reason: 'bootstrap',
      );
      final second = await store.save(
        characterId: card.id,
        definition: 'v2',
        source: 'llm',
        reason: 'revise',
      );
      expect(second, 2);
      expect((await store.versions(card.id)).length, 2);
    });

    test('还没定义 → 需要 bootstrap；证据够 → 需要修订', () async {
      expect(await store.needsRevision(card.id), true);
      await store.save(
        characterId: card.id,
        definition: '我是小林。',
        source: 'llm',
        reason: 'bootstrap',
      );
      expect(await store.needsRevision(card.id), false);
      for (var i = 0; i < 6; i++) {
        await store.addEvidence(card.id);
      }
      expect(await store.needsRevision(card.id), true);
    });

    test('证据在保存新版本后清零', () async {
      await store.save(
        characterId: card.id,
        definition: 'v1',
        source: 'llm',
        reason: 'bootstrap',
        evidence: 0,
      );
      for (var i = 0; i < 6; i++) {
        await store.addEvidence(card.id);
      }
      await store.save(
        characterId: card.id,
        definition: 'v2',
        source: 'llm',
        reason: 'revise',
        evidence: 0,
      );
      expect((await store.get(card.id))!.definitionEvidence, 0);
    });
  });
}
