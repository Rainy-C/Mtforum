import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';

void main() {
  const parser = ForumParser();

  test('post editor fields can be read even if mobile template moves them outside postform', () {
    const html = '''
      <html><body>
        <div id="loading-shell">数据加载中</div>
        <input name="formhash" value="590fe629" />
        <input name="posttime" value="1787208663" />
        <input name="delete" value="0" />
        <input name="allownoticeauthor" value="1" />
        <input name="usesig" value="1" />
        <input name="subject" value="标题" />
        <textarea name="message">正文</textarea>
      </body></html>
    ''';

    final form = parser.parsePostEditorForm(html, fallbackFid: '44');
    expect(form.formhash, '590fe629');
    expect(form.posttime, '1787208663');
    expect(form.fid, '44');
    expect(form.subject, '标题');
    expect(form.message, '正文');
  });
}
