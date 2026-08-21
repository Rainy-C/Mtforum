import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/user_center_parser.dart';

void main() {
  const parser = UserCenterParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('最近来访精确解析，不把加好友当用户名', () {
    const html = '''
    <div class="comiis_friend_boxs">
      <div class="comiis_userlist01 cl">
        <li class="b_t">
          <p class="ytit f_d">
            <a href="home.php?mod=spacecp&ac=friend&op=add&uid=23428">加好友</a>
            <a href="home.php?mod=spacecp&ac=follow&op=add&fuid=23428&hash=abc">关注</a>
          </p>
          <a href="home.php?mod=space&uid=23428&do=profile"
             class="list01_limg">
            <img src="avatar.php?uid=23428&size=middle" />
          </a>
          <p class="tit">
            <a href="home.php?mod=space&uid=23428&do=profile">远去的故人</a>
          </p>
        </li>
      </div>
    </div>
    ''';

    final users = parser.parseSocialUsers(
      html,
      baseUrl: baseUrl,
    );

    expect(users, hasLength(1));
    expect(users.single.uid, '23428');
    expect(users.single.username, '远去的故人');
    expect(users.single.username, isNot(contains('加好友')));
  });

  test('用户主页解析', () {
    const html = '''
    <div class="comiis_space_info">
      <div class="comiis_space_tx comiis_space_txv1">
        <div class="comiis_space_flw">
          <a id="followmod"
             href="home.php?mod=spacecp&ac=follow&op=add&hash=abc&fuid=125878&mobile=2">
             关注
          </a>
        </div>
        <div class="user_img">
          <img src="uc_server/avatar.php?uid=125878&size=middle" />
        </div>
        <h2 class="fyy">Tbs</h2>
        <p>
          <span>4625 人气</span>
          <span>|</span>
          <span>0 关注</span>
          <span>|</span>
          <span>445 粉丝</span>
        </p>
        <p>
          <span class="kmlevs bg_0 kmlv f_f">Lv.6</span>
          <span class="kmlev f_f">硕士生</span>
        </p>
      </div>
    </div>
    <a href="home.php?mod=spacecp&ac=friend&op=add&uid=125878">加好友</a>
    <a href="home.php?mod=spacecp&ac=poke&op=send&uid=125878">打招呼</a>
    <a href="home.php?mod=space&do=pm&subop=view&touid=125878">发消息</a>
    ''';

    final p = parser.parseSpaceProfile(
      html,
      uid: '125878',
      baseUrl: baseUrl,
    );

    expect(p.username, 'Tbs');
    expect(p.popularity, 4625);
    expect(p.following, 0);
    expect(p.followers, 445);
    expect(p.level, 'Lv.6');
    expect(p.userGroup, '硕士生');
    expect(p.avatarUrl, contains('uid=125878'));
    expect(p.followUrl, contains('fuid=125878'));
  });

  test('账号工具过滤导航与图标垃圾', () {
    const html = '''
    <html>
      <head><title>资料设置 - MT论坛</title></head>
      <body>
        <div class="comiis_space_tx">Cynnie Lv.3 初中生积分:261</div>
        <nav>□ 首页 □ 社区 □ 导读 □ 签到 □ 排行 □ 标签 □ 搜索</nav>
        <form>
          <p>数据加载中</p>
          <label>个人签名</label>
          <p>这里是可展示的正文</p>
        </form>
      </body>
    </html>
    ''';

    final page = parser.parseTextPage(
      html,
      fallbackTitle: '资料设置',
    );

    expect(page.lines, contains('个人签名'));
    expect(page.lines, contains('这里是可展示的正文'));
    expect(page.lines.join(' '), isNot(contains('数据加载中')));
    expect(page.lines.join(' '), isNot(contains('首页')));
    expect(page.lines.join(' '), isNot(contains('□')));
  });
}
