import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/user_center_parser.dart';

void main() {
  const parser = UserCenterParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('私信同一 wrapper 通过气泡 y/z 正确判断双方方向', () {
    const html = '''
    <script>var discuz_uid = '154205';</script>
    <div class="comiis_pm_list">
      <div class="comiis_friend_msg cl">
        <a href="home.php?mod=space&uid=137049&do=profile">
          <img class="msg_avt" src="avatar.php?uid=137049">
        </a>
        <div class="dialog_white z">
          <div class="msg_mes">大佬 能分享一下莫奈验证码</div>
          <div class="msg_time">上午 02:32:34</div>
        </div>
      </div>
      <div class="comiis_friend_msg cl">
        <div class="dialog_blue y">
          <div class="msg_mes">什么东西</div>
          <div class="msg_time">下午 12:52:59</div>
        </div>
      </div>
    </div>
    ''';

    final data = parser.parsePmConversation(
      html,
      touid: '137049',
      baseUrl: baseUrl,
      myUid: '154205',
    );

    expect(data.messages, hasLength(2));
    expect(data.messages.first.isMine, isFalse);
    expect(data.messages.last.isMine, isTrue);
  });

  test('打招呼通过 label for 精确关联每个 iconid', () {
    const html = '''
    <form>
      <input name="formhash" value="abc12345">
      <div class="all-options">
        <input id="poke0" type="radio" name="iconid" value="0">
        <label for="poke0"><img src="0.gif">不用动作</label>
        <input id="poke1" type="radio" name="iconid" value="1">
        <label for="poke1"><img src="1.gif">踩一下</label>
        <input id="poke2" type="radio" name="iconid" value="2">
        <label for="poke2"><img src="2.gif">握个手</label>
      </div>
    </form>
    ''';

    final data = parser.parsePokePage(html, baseUrl: baseUrl);
    expect(data.options.map((e) => e.label).toList(), [
      '不用动作',
      '踩一下',
      '握个手',
    ]);
    expect(data.options[1].iconUrl, '$baseUrl/1.gif');
  });

  test('用户主页解析 Web 完整资料字段和已关注状态', () {
    const html = '''
    <div class="comiis_space_info" style="background-image:url(static/bg.jpg)">
      <div class="comiis_space_tx">
        <div class="user_img"><img src="avatar.php?uid=153466"></div>
        <h2>Xtne</h2>
        <p>768 人气 | 39 关注 | 54 粉丝</p>
        <span class="kmlevs">Lv.5</span><span class="kmlev">大学生</span>
      </div>
    </div>
    <a href="home.php?mod=spacecp&ac=follow&op=del&fuid=153466">取消关注</a>
    <a href="home.php?mod=spacecp&ac=poke&op=send&uid=153466">打招呼</a>
    <a href="home.php?mod=space&do=pm&subop=view&touid=153466">聊天</a>
    <ul class="comiis_space_box">
      <li>勋章荣誉 <span class="medal"><img src="medal1.gif"></span></li>
      <li>个人签名 520236.xyz</li>
      <li>自定义衔 哈哈</li>
      <li>帖子 94</li>
      <li>回复 1151</li>
      <li>好友 9</li>
      <li>积分 4165</li>
      <li>好评 6</li>
      <li>金币 1414</li>
      <li>信誉 100</li>
      <li>职业 学生</li>
      <li>居住地 广西壮族自治区 梧州市 苍梧县 广平镇</li>
      <li>生日 2011年2月28日</li>
      <li>性别 男</li>
      <li>在线时间 439 小时</li>
      <li>注册时间 2025-11-20 12:38</li>
      <li>最后访问 2026-8-20 13:13</li>
    </ul>
    ''';

    final p = parser.parseSpaceProfile(
      html,
      uid: '153466',
      baseUrl: baseUrl,
    );

    expect(p.username, 'Xtne');
    expect(p.posts, 94);
    expect(p.replies, 1151);
    expect(p.friends, 9);
    expect(p.credits, 4165);
    expect(p.gold, 1414);
    expect(p.signature, '520236.xyz');
    expect(p.occupation, '学生');
    expect(p.isFollowing, isTrue);
    expect(p.backgroundUrl, '$baseUrl/static/bg.jpg');
    expect(p.medalUrls.single, '$baseUrl/medal1.gif');
  });
}
