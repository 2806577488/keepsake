import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/brain/brain_profile.dart';

/// 规范层（v0.4.35）单测：只测纯函数，不碰 DB / 网络。
void main() {
  group('renderSpecialtySection', () {
    test('空规范不注入', () {
      expect(renderSpecialtySection(null), '');
      expect(renderSpecialtySection(''), '');
      expect(renderSpecialtySection('   \n  '), '');
    });

    test('非空规范带固定标题', () {
      final section = renderSpecialtySection('只做中医辨证，不猜西医诊断。');
      expect(section.startsWith(kSpecialtySectionTitle), true);
      expect(section.contains('只做中医辨证'), true);
    });

    test('多行条目原样保留', () {
      final section = renderSpecialtySection('- 先望闻问切\n- 不给具体剂量');
      expect(section.contains('\n- 先望闻问切\n- 不给具体剂量'), true);
    });

    test('超长截断并加省略号', () {
      final section = renderSpecialtySection('字' * 3000, maxChars: 100);
      expect(section.length <= kSpecialtySectionTitle.length + 1 + 101, true);
      expect(section.endsWith('…'), true);
    });

    test('过小的 maxChars 有下限，不会渲染出空标题', () {
      final section = renderSpecialtySection('内容', maxChars: 1);
      expect(section.startsWith(kSpecialtySectionTitle), true);
      expect(section.contains('内容'), true);
    });
  });
}
