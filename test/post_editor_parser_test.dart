import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';

void main() {
  const parser = ForumParser();

  test('解析新主题表单的 formhash posttime 标题正文', () {
    const html = r'''
<form id="postform" action="forum.php?mod=post&action=newthread&fid=44&extra=&topicsubmit=yes&mobile=2">
  <input type="hidden" name="formhash" value="590fe629" />
  <input type="hidden" name="posttime" value="1787208663" />
  <input type="hidden" name="delete" value="0" />
  <input type="hidden" name="topicsubmit" value="yes" />
  <input name="subject" value="" />
  <textarea name="message"></textarea>
  <input name="allownoticeauthor" value="1" />
  <input name="usesig" value="1" />
</form>
''';

    final form = parser.parsePostEditorForm(html, fallbackFid: '44');
    expect(form.formhash, '590fe629');
    expect(form.posttime, '1787208663');
    expect(form.fid, '44');
    expect(form.tid, isEmpty);
    expect(form.pid, isEmpty);
  });

  test('解析编辑表单的定位字段和原始内容', () {
    const html = r'''
<form id="postform" action="forum.php?mod=post&action=edit&extra=&editsubmit=yes&mobile=2">
  <input type="hidden" name="formhash" value="590fe629" />
  <input type="hidden" name="posttime" value="1787209883" />
  <input type="hidden" name="delete" value="0" />
  <input type="hidden" name="fid" value="44" />
  <input type="hidden" name="tid" value="171458" />
  <input type="hidden" name="pid" value="11660491" />
  <input type="hidden" name="page" value="2" />
  <input name="subject" value="JsHook" />
  <textarea name="message">请问JsHook还在更新吗</textarea>
  <input name="allownoticeauthor" value="1" />
  <input name="usesig" value="1" />
</form>
''';

    final form = parser.parsePostEditorForm(
      html,
      fallbackFid: '1',
      fallbackTid: '2',
      fallbackPid: '3',
      fallbackPage: 1,
    );

    expect(form.fid, '44');
    expect(form.tid, '171458');
    expect(form.pid, '11660491');
    expect(form.page, 2);
    expect(form.subject, 'JsHook');
    expect(form.message, '请问JsHook还在更新吗');
  });
}
