import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/brain/brain_entities.dart';
import 'package:keepsake/core/brain/brain_entities_store.dart';
import 'package:keepsake/core/db/database.dart';

/// 实体 store 的单测（v0.4.35，对应 dsh-brain 的 entity.test.mjs）。
///
/// 用 drift 内存库，不碰文件、不联网。
void main() {
  late AppDatabase db;
  late BrainEntityStore store;

  setUp(() async {
    db = AppDatabase.memory();
    store = BrainEntityStore(db);
    // 实体表带 characterId 隔离，但没有外键，所以不需要真实角色卡。
    await db.createCharacter(name: '测试角色', id: 'c1');
  });

  tearDown(() async {
    await db.close();
  });

  Future<IngestMessage> ingest(
    String id,
    String user, {
    String assistant = '',
    DateTime? at,
  }) async {
    final message = IngestMessage(
      messageId: id,
      userText: user,
      assistantText: assistant,
      at: at ?? DateTime(2026, 11, 27, 10, 0),
    );
    await store.ingestMessages(
      characterId: 'c1',
      sessionId: 's1',
      messages: <IngestMessage>[message],
    );
    return message;
  }

  test('upsert 幂等：同名不重复建号', () async {
    final first = await store.upsert(characterId: 'c1', kind: 'patient', name: '张三');
    final second = await store.upsert(characterId: 'c1', kind: 'patient', name: '张三');
    expect(second.id, first.id);
    expect((await store.listForCharacter('c1')).length, 1);
  });

  test('不同角色卡之间不串号', () async {
    await db.createCharacter(name: '另一个角色', id: 'c2');
    await store.upsert(characterId: 'c1', kind: 'patient', name: '张三');
    await store.upsert(characterId: 'c2', kind: 'patient', name: '张三');
    expect((await store.findByName('c1', '张三'))?.characterId, 'c1');
    expect((await store.findByName('c2', '张三'))?.characterId, 'c2');
  });

  test('ingestMessages：抽对象 + 关联消息 + 记要点', () async {
    await ingest('m1', '患者张三，咳嗽三天，夜间加重');
    final entity = await store.findByName('c1', '张三');
    expect(entity, isNotNull);
    expect(entity!.kind, 'patient');

    final view = await store.profile(characterId: 'c1', entityId: entity.id);
    expect(view, isNotNull);
    expect(view!.facts.isNotEmpty, true);
    expect(view.turns.length, 1);
    expect(view.turns.first.text.contains('咳嗽三天'), true);
  });

  test('只提到名字的既有对象也会被挂上（接着上次说）', () async {
    await ingest('m1', '患者张三，咳嗽三天');
    final again = await ingest('m2', '张三复诊，咳嗽好转');
    expect(again.userText.contains('患者'), false);
    final entity = await store.findByName('c1', '张三');
    final view = await store.profile(
      characterId: 'c1',
      entityId: entity!.id,
      turnLimit: 5,
    );
    expect(view!.turns.length, 2);
  });

  test('activate spreading：同段出现过的对象互相关联', () async {
    await ingest('m1', '患者张三，咳嗽三天');
    await ingest('m2', '患者李四，和上次那个张三一样咳嗽');
    final zhangsan = await store.findByName('c1', '张三');
    final related = await store.related('c1', <String>[zhangsan!.id]);
    expect(related.any((item) => item.name == '李四'), true);
  });

  test('表意识槽位：记住「眼下在说谁」', () async {
    final entity = await store.upsert(characterId: 'c1', kind: 'patient', name: '张三');
    await store.rememberFocus('c1', 's-focus', <String>[entity.id]);
    final focused = await store.focusEntities('c1', 's-focus');
    expect(focused.length, 1);
    expect(focused.first.name, '张三');
  });

  test('槽位有 TTL：隔太久不接旧对象', () async {
    final entity = await store.upsert(characterId: 'c1', kind: 'patient', name: '张三');
    await store.rememberFocus('c1', 's-expired', <String>[entity.id]);
    final expired = await store.focusEntities(
      'c1',
      's-expired',
      ttl: Duration.zero,
    );
    expect(expired, isEmpty);
  });

  test('resolveForTurn：点名优先，没点名用焦点', () async {
    await ingest('m1', '患者张三，咳嗽三天');
    final named = await store.resolveForTurn(
      characterId: 'c1',
      sessionId: 's-r1',
      text: '张三今天复诊',
    );
    expect(named.profiles.first.name, '张三');
    expect(named.viaFocus, false);
    expect(named.related.any((item) => item.name == '李四'), false);

    final pronoun = await store.resolveForTurn(
      characterId: 'c1',
      sessionId: 's-r1',
      text: '他今天怎么样？',
    );
    expect(pronoun.profiles.first.name, '张三');
    expect(pronoun.viaFocus, true);

    final orphan = await store.resolveForTurn(
      characterId: 'c1',
      sessionId: 's-never',
      text: '他今天怎么样？',
    );
    expect(orphan.profiles, isEmpty);
  });

  test('结构化字段写回（睡眠期巩固）', () async {
    await ingest('m1', '患者张三，咳嗽三天');
    final entity = await store.findByName('c1', '张三');
    final created = await store.applyExtraction(
      characterId: 'c1',
      name: '张三',
      facts: const <ExtractedFact>[
        ExtractedFact(kind: '主诉', text: '咳嗽三天，夜间加重'),
        ExtractedFact(kind: '处方', text: '止嗽散加减'),
      ],
    );
    expect(created, 2);
    // 重复写同一字段不再新增
    final again = await store.applyExtraction(
      characterId: 'c1',
      name: '张三',
      facts: const <ExtractedFact>[
        ExtractedFact(kind: '主诉', text: '咳嗽三天，夜间加重'),
      ],
    );
    expect(again, 0);

    final view = await store.profile(
      characterId: 'c1',
      entityId: entity!.id,
      factLimit: 10,
    );
    final kinds = view!.facts.map((item) => item.kind).toList();
    expect(kinds.contains('主诉'), true);
    expect(kinds.contains('处方'), true);
  });

  test('不在名单里的对象不会被抽取写回', () async {
    final created = await store.applyExtraction(
      characterId: 'c1',
      name: '查无此人',
      facts: const <ExtractedFact>[
        ExtractedFact(kind: '主诉', text: 'x'),
      ],
    );
    expect(created, 0);
  });

  test('普通句子不产生对象（不造假）', () async {
    final result = await store.ingestMessages(
      characterId: 'c1',
      sessionId: 's1',
      messages: <IngestMessage>[
        IngestMessage(
          messageId: 'm9',
          userText: '今天天气不错，我们先吃饭',
          at: DateTime(2026, 11, 27, 12),
        ),
      ],
    );
    expect(result.created, 0);
    expect(await store.listForCharacter('c1'), isEmpty);
  });
}
