import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/characters/character_service.dart';

/// v0.4.33 止血：名字规则的单测。
///
/// 背景：老实现直接把会话标题当角色名，于是「随便问个问题」会生成
/// 「妈的现在的中医熟地24g都开出来了」这种角色卡。这里把规则钉住。
void main() {
  group('characterNameFor（生成/导入用，严格）', () {
    test('整句标题不当作人名', () {
      expect(characterNameFor('妈的现在的中医熟地24g都开出来了'), kDefaultCharacterName);
    });

    test('短名字照用', () {
      expect(characterNameFor('张三'), '张三');
      expect(characterNameFor('小林'), '小林');
    });

    test('去掉包裹引号与句末标点', () {
      expect(characterNameFor('「小林」'), '小林');
      expect(characterNameFor('  阿杰。 '), '阿杰');
    });

    test('问句不当作人名', () {
      expect(characterNameFor('今天吃什么？'), kDefaultCharacterName);
      expect(characterNameFor('这个怎么看'), kDefaultCharacterName);
      expect(characterNameFor('是不是要复诊'), kDefaultCharacterName);
    });

    test('占位标题不当作人名', () {
      expect(characterNameFor('新对话'), kDefaultCharacterName);
      expect(characterNameFor('未命名会话'), kDefaultCharacterName);
      expect(characterNameFor(''), kDefaultCharacterName);
    });

    test('不像名字时退话题词', () {
      expect(
        characterNameFor('妈的现在的中医熟地24g都开出来了', topicTerms: ['中医', '熟地']),
        '中医 · 熟地',
      );
    });
  });

  group('isGenericCardTitle 长度阈值', () {
    test('12 个字以内不算占位', () {
      expect(isGenericCardTitle('一起打游戏的她'), false);
    });

    test('超过 12 字视为不是人名', () {
      expect(isGenericCardTitle('a' * 13), true);
    });
  });

  group('sanitizeManualName（手工输入用，宽松）', () {
    test('保留用户自己起的名字', () {
      expect(sanitizeManualName('  我的角色  '), '我的角色');
      expect(sanitizeManualName('一起读诗的那位'), '一起读诗的那位');
    });

    test('空名字退占位名', () {
      expect(sanitizeManualName('   '), kDefaultCharacterName);
    });

    test('超长名字截断但不改字', () {
      final name = sanitizeManualName('一' * 30);
      expect(name.length, 24);
      expect(name.endsWith('…'), true);
    });
  });
}
