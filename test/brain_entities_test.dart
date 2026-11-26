import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/brain/brain_entities.dart';

/// 实体层规则单测（v0.4.35，移植自 dsh-brain 的 entity.test.mjs）。
void main() {
  group('身份前缀抽取', () {
    test('患者张三', () {
      final list = extractEntityCandidates('患者张三今天来复诊');
      expect(list.length, 1);
      expect(list.first.kind, 'patient');
      expect(list.first.name, '张三');
    });

    test('病人：李姐（冒号 + 单字敬称保留）', () {
      final list = extractEntityCandidates('病人：李姐，头晕');
      expect(list.first.name, '李姐');
    });

    test('客户王先生（多字敬称算代号）', () {
      final list = extractEntityCandidates('客户王先生来了');
      expect(list.first.name, '王先生');
      expect(list.first.kind, 'client');
    });

    test('项目/宠物不要求姓氏', () {
      final project = extractEntityCandidates('项目留声下个月上线');
      expect(project.first.kind, 'project');
      expect(project.first.name, '留声');
      final pet = extractEntityCandidates('宠物豆豆要打疫苗');
      expect(pet.first.kind, 'pet');
      expect(pet.first.name, '豆豆');
    });
  });

  group('敬称后缀抽取', () {
    test('张三先生 → 张三', () {
      final list = extractEntityCandidates('张三先生今天没来');
      expect(list.any((item) => item.name == '张三'), true);
    });

    test('「客户王先生」不会被抽成「户王」', () {
      final names = extractEntityCandidates('客户王先生').map((item) => item.name);
      expect(names.contains('户王'), false);
      expect(names.any((name) => name.contains('户王')), false);
    });
  });

  group('宁缺毋滥', () {
    test('普通句子不产生对象', () {
      expect(extractEntityCandidates('今天天气不错，我们先吃饭').isEmpty, true);
      expect(extractEntityCandidates('这个情况要怎么处理').isEmpty, true);
    });

    test('时间词不会被当人名', () {
      expect(extractEntityCandidates('患者今天来了').isEmpty, true);
    });
  });

  group('名字归一化与类型标签', () {
    test('归一化去空白与引号', () {
      expect(normalizeEntityName('「张三」 '), '张三');
      expect(normalizeEntityName('张 三'), '张三');
    });

    test('类型中文名', () {
      expect(kindLabelOf('patient'), '患者');
      expect(kindLabelOf('project'), '项目');
      expect(kindLabelOf('unknown'), '对象');
    });
  });

  group('渲染「当前对象」段', () {
    test('没有对象不注入', () {
      expect(renderEntitySection(const <EntityProfileView>[]), '');
    });

    test('带要点与最近聊到', () {
      final text = renderEntitySection(
        const <EntityProfileView>[
          EntityProfileView(
            name: '张三',
            kindLabel: '患者',
            facts: <EntityFactView>[
              EntityFactView(kind: '主诉', text: '咳嗽三天，夜间加重'),
            ],
            turns: <EntityTurnView>[
              EntityTurnView(text: '张三复诊，咳嗽好转'),
            ],
          ),
        ],
        related: const <EntityRelatedView>[
          EntityRelatedView(name: '李四', reason: '和张三在同一段对话里出现过'),
        ],
      );
      expect(text.contains('【当前对象 · 张三（患者）】'), true);
      expect(text.contains('咳嗽三天'), true);
      expect(text.contains('【相关对象】'), true);
      expect(text.contains('李四'), true);
    });

    test('超预算截断', () {
      final text = renderEntitySection(
        const <EntityProfileView>[EntityProfileView(name: '张三', kindLabel: '患者')],
        maxChars: 10,
      );
      expect(text.length <= 10, true);
      expect(text.endsWith('…'), true);
    });
  });

  group('结构化抽取（睡眠期巩固）', () {
    test('prompt 限字段并给名单', () {
      final request = buildEntityExtractMessages(
        turns: const <ExtractTurn>[
          ExtractTurn(user: '患者张三咳嗽三天', assistant: '开了止嗽散'),
        ],
        names: const <String>['张三'],
      );
      expect(request.system.contains('主诉'), true);
      expect(request.system.contains('处方'), true);
      expect(request.user.contains('张三'), true);
      expect(request.user.contains('止嗽散'), true);
    });

    test('解析容错 + kind 白名单兜底', () {
      final parsed = parseEntityExtraction(
        '```json\n{"entities":[{"name":"张三","facts":[{"kind":"主诉","text":"咳嗽三天"},{"kind":"乱写","text":"开了三剂"}]}]}\n```',
      );
      expect(parsed.length, 1);
      expect(parsed.first.name, '张三');
      expect(parsed.first.facts.first.kind, '主诉');
      expect(parsed.first.facts[1].kind, '备注');
    });

    test('坏 JSON 返回空', () {
      expect(parseEntityExtraction('不是 JSON'), isEmpty);
      expect(parseEntityExtraction('{"entities":"x"}'), isEmpty);
      expect(parseEntityExtraction(null), isEmpty);
    });
  });
}
