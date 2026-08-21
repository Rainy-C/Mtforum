import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/smiley_catalog.dart';

void main() {
  test('编辑器表情 marker 不暴露 BBCode', () {
    final url = SmileyCatalog.qq.first;
    final marker = SmileyCatalog.markerForUrl(url);

    expect(marker, isNotNull);
    expect(marker, isNot(contains('[img]')));
    expect(marker!.length, 1);
  });

  test('发送前才转换成论坛 BBCode', () {
    final url1 = SmileyCatalog.qq.first;
    final url2 = SmileyCatalog.comcom.first;
    final marker1 = SmileyCatalog.markerForUrl(url1)!;
    final marker2 = SmileyCatalog.markerForUrl(url2)!;

    final wire = SmileyCatalog.toForumBbCode(
      '你好$marker1测试$marker2',
    );

    expect(
      wire,
      '你好[img]$url1[/img]测试[img]$url2[/img]',
    );
  });

  test('普通文字不会被转换', () {
    expect(
      SmileyCatalog.toForumBbCode('普通文本 123'),
      '普通文本 123',
    );
  });

  test('编辑旧帖子时论坛表情 BBCode 还原成 marker', () {
    final url = SmileyCatalog.qq.first;
    final editor = SmileyCatalog.fromForumBbCode('前缀[img]$url[/img]后缀');

    expect(editor, isNot(contains('[img]')));
    expect(SmileyCatalog.toForumBbCode(editor), '前缀[img]$url[/img]后缀');
  });
}
