import 'package:markdown/markdown.dart' as md;

String build(String unit, int times) =>
    List<String>.filled(times, unit).join('\n\n');

void main() {
  const unit =
      '办理健康证的核心体检项目全国大体一致，主要是为了筛查**消化道传染病**（如病毒性肝炎、痢疾）和'
      '**活动性肺结核**等影响公众健康的疾病。\n\n'
      '- 内科检查：包括询问病史，以及检查是否有渗出性、化脓性等皮肤病。\n'
      '- 抽血检验：主要查谷丙转氨酶（ALT），这是反映肝功能的关键指标。\n\n'
      '> 引用：粪便检查用于筛查肠道致病菌。\n\n'
      '```dart\nfinal x = 1;\n```\n\n';

  for (final target in <int>[5000, 12000, 27000]) {
    final times = (target / unit.length).ceil();
    final text = build(unit, times);
    // 预热一次
    md.Document(extensionSet: md.ExtensionSet.gitHubFlavored).parse(text);
    final sw = Stopwatch()..start();
    const runs = 5;
    for (var i = 0; i < runs; i += 1) {
      md.Document(extensionSet: md.ExtensionSet.gitHubFlavored).parse(text);
    }
    sw.stop();
    print('${text.length} chars: ${(sw.elapsedMilliseconds / runs).toStringAsFixed(1)} ms/次');
  }
}
