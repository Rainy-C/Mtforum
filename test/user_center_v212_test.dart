import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/user_center_parser.dart';

void main() {
  const parser = UserCenterParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('密码安全页解析当前邮箱和安全提问', () {
    const html = '''
    <form>
      <input name="formhash" value="590fe629">
      <input name="emailnew" value="demo@example.com">
      <input name="secmobiccnew" value="">
      <input name="secmobilenew" value="">
      <select name="questionidnew">
        <option value="0">保持原有</option>
        <option value="7" selected>驾驶执照最后四位数字</option>
      </select>
    </form>
    ''';

    final data = parser.parsePasswordSecurity(html);
    expect(data.formhash, '590fe629');
    expect(data.email, 'demo@example.com');
    expect(data.questionId, 7);
    expect(data.questions, hasLength(2));
  });

  test('联系方式解析', () {
    const html = '''
    <form>
      <input name="qq" value="123456">
      <input type="radio" name="privacy[qq]" value="0" checked>
      <input name="mobile" value="13800138000">
      <input type="radio" name="privacy[mobile]" value="3" checked>
    </form>
    ''';

    final data = parser.parseContactProfile(html);
    expect(data.qq, '123456');
    expect(data.privacyQq, 0);
    expect(data.mobile, '13800138000');
    expect(data.privacyMobile, 3);
  });

  test('打招呼选项从页面解析，不硬编码名称', () {
    const html = '''
    <form>
      <input name="formhash" value="590fe629">
      <label><input type="radio" name="iconid" value="0">打招呼</label>
      <label>
        <input type="radio" name="iconid" value="4">
        <img src="static/image/magic/yb.gif">握把
      </label>
    </form>
    ''';

    final data = parser.parsePokePage(html, baseUrl: baseUrl);
    expect(data.formhash, '590fe629');
    expect(data.options.map((e) => e.iconId), containsAll([0, 4]));
  });

  test('邀请无权限页面结构化为无权限状态', () {
    const html = '''
    <div class="comiis_password_top">
      <p class="f_c">抱歉，您目前还没有权限邀请好友</p>
    </div>
    ''';

    final data = parser.parseInviteStatus(html);
    expect(data.canInvite, isFalse);
    expect(data.message, contains('暂无邀请好友权限'));
  });

  test('私信未知 wrapper 不再误判为自己消息', () {
    const html = '''
    <div class="comiis_pm_list">
      <div class="weird_message_wrapper">
        <div class="msg_mes">对方发来的历史消息</div>
        <div class="msg_time">上午 02:32:34</div>
      </div>
      <div class="comiis_my_msg">
        <div class="msg_mes">我发的消息</div>
        <div class="msg_time">上午 02:35:00</div>
      </div>
    </div>
    ''';

    final data = parser.parsePmConversation(
      html,
      touid: '137049',
      baseUrl: baseUrl,
    );
    expect(data.messages, hasLength(2));
    expect(data.messages.first.isMine, isFalse);
    expect(data.messages.last.isMine, isTrue);
  });
}
