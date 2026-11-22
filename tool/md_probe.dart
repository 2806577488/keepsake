import 'package:markdown/markdown.dart' as md;

void dump(md.Node node, int depth) {
  final pad = '  ' * depth;
  final text = node is md.Text ? ' "${node.text}"' : '';
  print('$pad${node.runtimeType}$text');
  if (node is md.Element) {
    for (final child in node.children ?? const <md.Node>[]) {
      dump(child, depth + 1);
    }
  }
}

void main() {
  const whole =
      '在这个节点上，文蛤的“壳”与“肉”提供了石膏和麻黄都不具备的**分层作用**（皮水/胸烦）和**软坚开结**之力。它的“不可替代”，不是对整个“皮水”病证而言，而是针对**“水热胶结、玄府闭塞”这一特定结构**而言的。';
  const line =
      '而是针对**“水热胶结、玄府闭塞”这一特定结构**而言的。';
  for (final sample in <String>[line, whole]) {
    print('=== ${sample.length} chars ===');
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    for (final node in doc.parse(sample)) {
      dump(node, 0);
    }
    print('');
  }
}
