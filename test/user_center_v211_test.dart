import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/user_center_parser.dart';

void main() {
  const parser = UserCenterParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('签名资料解析', () {
    const html = '''
    <form>
      <select name="privacy[bio]">
        <option value="0" selected>公开</option>
      </select>
      <textarea name="bio">个人简介</textarea>
      <textarea name="sightml">个性签名</textarea>
    </form>
    ''';

    final data = parser.parseSignatureProfile(html);
    expect(data.bio, '个人简介');
    expect(data.signature, '个性签名');
    expect(data.privacyBio, 0);
  });

  test('密码安全提问解析', () {
    const html = '''
    <form>
      <input type="hidden" name="formhash" value="590fe629">
      <select name="questionidnew">
        <option value="0">保持原有的安全提问和答案</option>
        <option value="1">母亲的名字</option>
        <option value="7">驾驶执照最后四位数字</option>
      </select>
    </form>
    ''';

    final data = parser.parsePasswordSecurity(html);
    expect(data.formhash, '590fe629');
    expect(data.questions, hasLength(3));
    expect(data.questions.last.id, 7);
  });

  test('访问推广解析', () {
    const html = '''
    <div class="comiis_tg_box">
      <div class="comiis_tg_tximg">
        <img src="uc_server/avatar.php?uid=154205&size=middle" />
      </div>
      <div class="comiis_tg_kmtit">Cynnie</div>
      <div class="comiis_tg_kmtxt">UID: 154205</div>
      <div class="comiis_tg_box_tip">
        网友通过二维码访问，您将获得 金币+20
      </div>
    </div>
    <script>
      $('.comiis_tg_code_img').qrcode({
        text: "https://bbs.binmt.cc/?fromuid=154205"
      });
    </script>
    ''';

    final data = parser.parsePromotion(html, baseUrl: baseUrl);
    expect(data.username, 'Cynnie');
    expect(data.uid, '154205');
    expect(data.link, 'https://bbs.binmt.cc/?fromuid=154205');
    expect(data.reward, contains('金币+20'));
  });

  test('积分记录去掉重复摘要', () {
    const html = '''
    <ul>
      <li>金币 +2 2026-08-20 08:06 每日签到</li>
      <li>2026-08-20 08:06 每日签到</li>
    </ul>
    ''';

    final records = parser.parseCreditRecords(html);
    expect(records, hasLength(1));
    expect(records.single.delta, '+2');
    expect(records.single.time, '2026-08-20 08:06');
    expect(records.single.reason, '每日签到');
  });

  test('私信对话解析', () {
    const html = '''
    <div class="comiis_pm_list">
      <div class="comiis_msg_date"><span>2026-04-15</span></div>
      <div class="comiis_friend_msg cl">
        <a href="home.php?mod=space&uid=137049&do=profile">
          <img class="msg_avt"
               src="avatar.php?uid=137049&size=middle" />
        </a>
        <div class="dialog_white z">
          <div class="msg_mes">你好</div>
          <div class="msg_time f_d">上午 02:32:34</div>
        </div>
      </div>
    </div>
    <form id="pmform"
      action="home.php?mod=spacecp&ac=pm&op=send&pmid=239190&daterange=2">
      <input name="formhash" value="590fe629" />
      <input name="touid" value="137049" />
    </form>
    ''';

    final data = parser.parsePmConversation(
      html,
      touid: '137049',
      baseUrl: baseUrl,
    );

    expect(data.pmid, '239190');
    expect(data.formhash, '590fe629');
    expect(data.messages, hasLength(1));
    expect(data.messages.single.content, '你好');
    expect(data.messages.single.date, '2026-04-15');
    expect(data.messages.single.isMine, isFalse);
  });

  test('手机绑定优先读取完整 input', () {
    const html = '''
    <input name="comiis_tel" value="17856705503">
    ''';

    final data = parser.parseSmsBinding(html);
    expect(data.phone, '17856705503');
    expect(data.canUnbind, isTrue);
  });
}
