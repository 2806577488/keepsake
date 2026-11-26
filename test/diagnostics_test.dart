import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/core/db/database.dart';
import 'package:keepsake/core/diagnostics.dart';
import 'package:keepsake/core/settings.dart';

/// 诊断包单测（v0.4.39）：只验内容格式与"不泄露"。
void main() {
  test('诊断文本包含版本/设置/会话数，且不含 API Key', () async {
    final db = AppDatabase.memory();
    final settings = const Settings(
      providerId: 'deepseek',
      defaultModel: 'deepseek-chat',
      memoryEnabled: true,
      moodEnabled: false,
      personaEnabled: true,
      entityExtractEveryRounds: 0,
    );
    final text = await buildDiagnosticsText(db: db, settings: settings);
    await db.close();

    expect(text.contains('Keepsake 诊断信息'), true);
    expect(text.contains('设置（脱敏，不含 Key）'), true);
    expect(text.contains('平台：deepseek'), true);
    expect(text.contains('模型：deepseek-chat'), true);
    expect(text.contains('记忆/情绪/人格：开/关/开'), true);
    expect(text.contains('实体字段抽取：关'), true);
    expect(text.contains('会话数：'), true);

    // 绝不应该出现 Key 的值（这里只能断言没有常见的 key 形态）。
    expect(text.contains('api_key'), false);
    expect(text.contains('sk-'), false);
  });

  test('设置 JSON 往返保留实体抽取轮数', () {
    const settings = Settings(entityExtractEveryRounds: 6);
    final decoded = Settings.fromJson(settings.toJson());
    expect(decoded.entityExtractEveryRounds, 6);
    // 缺字段时回落到默认 3 轮
    expect(const Settings.defaults().entityExtractEveryRounds, 3);
  });
}
