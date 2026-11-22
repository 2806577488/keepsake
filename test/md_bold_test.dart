import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/features/chat/widgets/markdown_view.dart';
import 'package:markdown/markdown.dart' as md;

bool hasStrong(Iterable<md.Node> nodes) {
  for (final node in nodes) {
    if (node is md.Element) {
      if (node.tag == 'strong') return true;
      if (hasStrong(node.children ?? const <md.Node>[])) return true;
    }
  }
  return false;
}

void main() {
  test('汉字紧贴 ** 且内容以引号开头也能加粗', () {
    const input = '而是针对**“水热胶结、玄府闭塞”这一特定结构**而言的。';
    final doc = md.Document(extensionSet: keepsakeMarkdownExtensionSetWithMath);
    expect(hasStrong(doc.parse(normalizeMarkdownBold(input))), isTrue);
  });

  test('普通加粗仍然加粗', () {
    const input = '都不具备的**分层作用**（皮水/胸烦）';
    final doc = md.Document(extensionSet: keepsakeMarkdownExtensionSetWithMath);
    expect(hasStrong(doc.parse(normalizeMarkdownBold(input))), isTrue);
  });

  test('代码块里的 ** 不改写', () {
    const input = '```\nconst a = **x**;\n```';
    expect(normalizeMarkdownBold(input).contains('**x**'), isTrue);
  });

  test('行内代码里的 ** 不改写', () {
    expect(normalizeMarkdownBold('看 `**x**` 这里').contains('**x**'), isTrue);
  });

  test('半截流式文本不吞掉 *', () {
    expect(normalizeMarkdownBold('**未闭合').contains('**未闭合'), isTrue);
  });
}
