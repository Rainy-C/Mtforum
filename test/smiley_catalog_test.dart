import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/smiley_catalog.dart';

void main() {
  test('QQ 表情列表数量与缺失编号正确', () {
    expect(SmileyCatalog.qq.length, 102);

    expect(
      SmileyCatalog.qq.first,
      'https://cdn-bbs.mt2.cn/static/image/smiley/qq/qq001.gif',
    );
    expect(
      SmileyCatalog.qq.last,
      'https://cdn-bbs.mt2.cn/static/image/smiley/qq/qq107.gif',
    );

    for (final missing in const [62, 93, 94, 95, 96]) {
      final number = missing.toString().padLeft(3, '0');
      expect(
        SmileyCatalog.qq.any((url) => url.endsWith('qq$number.gif')),
        isFalse,
      );
    }
  });

  test('COMCOM 只收录已确认存在的 1 到 30', () {
    expect(SmileyCatalog.comcom.length, 30);
    expect(
      SmileyCatalog.comcom.first,
      'https://cdn-bbs.mt2.cn/static/image/smiley/comcom/1.gif',
    );
    expect(
      SmileyCatalog.comcom.last,
      'https://cdn-bbs.mt2.cn/static/image/smiley/comcom/30.gif',
    );
  });

  test('表情包列表包含 QQ 与 COMCOM', () {
    expect(SmileyCatalog.packs.length, 2);
    expect(SmileyCatalog.packs[0].id, 'qq');
    expect(SmileyCatalog.packs[1].id, 'comcom');
  });
}
