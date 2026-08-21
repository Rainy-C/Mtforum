import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/account_parser.dart';

void main() {
  const parser = AccountParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('解析我的帖子统计顺序', () {
    final result = parser.parseMyThreads(
      '''
      <html><body>
      <li class="forumlist_li comiis_znalist">
        <a class="top_user" href="home.php?mod=space&uid=154205">Cynnie</a>
        <span class="top_lev">Lv.3</span>
        <span class="f_d">2026-8-19</span>
        <div class="mmlist_li_box">
          <h2><a href="thread-171412-1-1.html">ProxyPin添加MCP功能</a></h2>
        </div>
        <div class="list_body"><a href="#">懒的介绍，自行下载查看</a></div>
        <div class="comiis_pyqlist_imgs">
          <img src="forum.php?mod=image&aid=371375&size=500x480">
        </div>
        <div class="comiis_xznalist_bottom">
          <span class="comiis_tm num-all_171412">0</span>
          <span class="comiis_tm">20</span>
          <span class="comiis_tm">460</span>
        </div>
      </li>
      </body></html>
      ''',
      baseUrl: baseUrl,
    );

    expect(result, hasLength(1));
    expect(result.single.tid, '171412');
    expect(result.single.title, 'ProxyPin添加MCP功能');
    expect(result.single.authorUid, '154205');
    expect(result.single.likeCount, '0');
    expect(result.single.replyCount, '20');
    expect(result.single.viewCount, '460');
    expect(result.single.thumbnails, hasLength(1));
    expect(
      result.single.thumbnails.single,
      startsWith('https://bbs.binmt.cc/'),
    );
  });

  test('解析收藏', () {
    final result = parser.parseFavorites(
      '''
      <li class="mysclist_li b_t">
        <a href="home.php?mod=spacecp&ac=favorite&op=delete&favid=634443&type=all">
          删除
        </a>
        <h2>
          <img src="static/image/feed/thread.gif" alt="thread" class="t">
          <a href="thread-161541-1-1.html">代码抽取壳</a>
        </h2>
      </li>
      ''',
    );

    expect(result, hasLength(1));
    expect(result.single.favid, '634443');
    expect(result.single.tid, '161541');
    expect(result.single.title, '代码抽取壳');
    expect(result.single.type, 'thread');
  });

  test('解析好友', () {
    final result = parser.parseFriends(
      '''
      <li class="b_t">
        <p class="ytit f_d">
          <a href="home.php?mod=space&do=pm&subop=view&touid=1">发消息</a>
        </p>
        <a href="home.php?mod=space&uid=1&do=profile" class="list01_limg">
          <img src="uc_server/avatar.php?uid=1&size=middle">
        </a>
        <p class="tit">
          <a href="home.php?mod=space&uid=1&do=profile">admin</a>
        </p>
      </li>
      ''',
      baseUrl: baseUrl,
    );

    expect(result, hasLength(1));
    expect(result.single.uid, '1');
    expect(result.single.username, 'admin');
    expect(
      result.single.avatarUrl,
      'https://bbs.binmt.cc/uc_server/avatar.php?uid=1&size=middle',
    );
    expect(result.single.messageUrl, contains('touid=1'));
  });
}
