import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/user_center_parser.dart';

void main() {
  const parser = UserCenterParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('基本资料表单解析', () {
    const html = '''
    <form>
      <input name="realname" value="范宇晨">
      <select name="privacy[realname]">
        <option value="0">公开</option>
        <option value="3" selected>仅自己</option>
      </select>
      <select name="gender">
        <option value="0" selected>保密</option>
      </select>
      <select name="privacy[gender]">
        <option value="0" selected>公开</option>
      </select>
      <select name="birthyear"><option value="0" selected>0</option></select>
      <select name="birthmonth"><option value="0" selected>0</option></select>
      <select name="birthday"><option value="0" selected>0</option></select>
      <select name="privacy[birthday]">
        <option value="0" selected>公开</option>
      </select>
      <input name="resideprovince" value="">
      <select name="privacy[residecity]">
        <option value="0" selected>公开</option>
      </select>
      <input name="occupation" value="开发">
      <select name="privacy[occupation]">
        <option value="1" selected>好友</option>
      </select>
    </form>
    ''';

    final form = parser.parseBasicProfile(html);

    expect(form.realname, '范宇晨');
    expect(form.privacyRealname, 3);
    expect(form.gender, 0);
    expect(form.occupation, '开发');
    expect(form.privacyOccupation, 1);
  });

  test('积分总览解析', () {
    const html = '''
    <html><head><title>积分 - MT论坛</title></head>
    <body>
      <h2>积分: <span>261</span></h2>
      <p>总积分=金币X0.2+主题数X3+发帖数X1.5+精华帖数X30+好评X5+(信誉-100)X5</p>
      <ul>
        <li>金币: 141</li>
        <li>好评: 0</li>
        <li>信誉: 100</li>
      </ul>
    </body></html>
    ''';

    final summary = parser.parseCreditSummary(html);

    expect(summary.total, 261);
    expect(summary.gold, 141);
    expect(summary.praise, 0);
    expect(summary.reputation, 100);
    expect(summary.formula, contains('总积分='));
  });

  test('关注与粉丝列表通用用户解析', () {
    const html = '''
    <ul>
      <li>
        <a href="home.php?mod=space&uid=123">
          <img src="uc_server/avatar.php?uid=123&size=middle">
        </a>
        <p class="tit">
          <a href="home.php?mod=space&uid=123">Tester</a>
        </p>
        <a href="home.php?mod=space&do=pm&subop=view&touid=123">发消息</a>
      </li>
    </ul>
    ''';

    final users = parser.parseSocialUsers(
      html,
      baseUrl: baseUrl,
    );

    expect(users, hasLength(1));
    expect(users.single.uid, '123');
    expect(users.single.username, 'Tester');
    expect(users.single.avatarUrl, startsWith(baseUrl));
  });

  test('好友请求解析通过与忽略链接', () {
    const html = '''
    <li>
      <a href="home.php?mod=space&uid=88">Alice</a>
      <img src="uc_server/avatar.php?uid=88&size=middle">
      <a href="home.php?mod=spacecp&ac=friend&op=add&uid=88">通过</a>
      <a href="home.php?mod=spacecp&ac=friend&op=ignore&uid=88">忽略</a>
    </li>
    ''';

    final requests = parser.parseFriendRequests(
      html,
      baseUrl: baseUrl,
    );

    expect(requests, hasLength(1));
    expect(requests.single.uid, '88');
    expect(requests.single.username, 'Alice');
    expect(requests.single.acceptUrl, contains('op=add'));
    expect(requests.single.ignoreUrl, contains('op=ignore'));
  });

  test('无好友请求返回空列表', () {
    final requests = parser.parseFriendRequests(
      '<root><![CDATA[没有新的好友请求]]></root>',
      baseUrl: baseUrl,
    );

    expect(requests, isEmpty);
  });
}
