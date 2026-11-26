import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/brain/brain_entities.dart';
import 'package:keepsake/core/brain/brain_profile.dart';

/// 缓存友好性回归（v0.4.40）：
///
/// 注入分两类——
/// - **稳定内容**（规范/角色定义）进 system 前缀，逐轮不变；
/// - **易变内容**（当前对象/召回）挂最后一轮 user。
///
/// 前缀缓存要求稳定段**逐字节不变**，所以这里断言：同样的输入渲染两次 → 完全相同。
void main() {
  test('专业规范段渲染是确定性的（不掺时间/随机）', () {
    const rules = '- 先问清症状与病程\n- 不给具体剂量';
    final first = renderSpecialtySection(rules);
    final second = renderSpecialtySection(rules);
    expect(first, second);
    expect(first.startsWith('【专业规范】'), true);
  });

  test('实体段渲染是确定性的（同一批档案 → 同一段文本）', () {
    const profile = EntityProfileView(
      name: '张三',
      kindLabel: '患者',
      facts: <EntityFactView>[
        EntityFactView(kind: '主诉', text: '咳嗽三天，夜间加重'),
      ],
      turns: <EntityTurnView>[
        EntityTurnView(text: '张三复诊，咳嗽好转', at: '2026-11-26T10:00:00'),
      ],
    );
    final first = renderEntitySection(const <EntityProfileView>[profile]);
    final second = renderEntitySection(const <EntityProfileView>[profile]);
    expect(first, second);
    expect(first.contains('【当前对象 · 张三（患者）】'), true);
  });

  test('空注入不产生任何内容（空字符串不占前缀）', () {
    expect(renderSpecialtySection(''), '');
    expect(renderEntitySection(const <EntityProfileView>[]), '');
  });
}
