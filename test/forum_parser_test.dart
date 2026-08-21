import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';

void main() {
  const parser = ForumParser();

  test('parses every pid floor and message table from MT detail HTML', () {
    const html = r'''
<html>
<head><title>LSPatch更新1.0 - MT论坛</title></head>
<body class="forum-viewforum-fid-44">
<script>var formhash = '1a1ca082'; var discuz_uid = '157080';</script>
<div id="pid11640673">
  <a href="home.php?mod=space&uid=157080" class="top_user">楼主</a>
  <a class="top_lev">Lv.4 高中生</a>
  <img class="top_tximg" src="uc_server/avatar.php?uid=157080">
  <span class="f_d y">楼主</span>
  <span class="kmtime">前天 09:43</span>
  <div class="comiis_a comiis_message_table cl">
    <script>replyreload += ',' + 11640673;</script>
    <i class="pstatus">本帖最后由...编辑</i>
    第一楼正文<br><strong>正文继续</strong>
    <span class="comiis_postimg"><img src="https://oss3-bbs.mt2.cn/a.jpg"></span>
  </div>
  <div class="comiis_rate">3人打赏</div>
  <a href="forum.php?mod=post&action=reply&fid=44&tid=1&repquote=11640673">回复</a>
</div>
<div id="pid11640674">
  <a href="home.php?mod=space&uid=2" class="top_user">春江水</a>
  <span class="f_d y">沙发</span>
  <span class="kmtime">昨天 10:00</span>
  <div class="comiis_a comiis_message_table cl">感谢分享！</div>
  <a href="forum.php?mod=post&action=reply&fid=44&tid=1&repquote=11640674">回复</a>
</div>
<div id="pid11640675">
  <a href="home.php?mod=space&uid=3" class="top_user">若幻</a>
  <span class="f_d y">板凳</span>
  <div class="comiis_a comiis_message_table cl">看看</div>
</div>
<form id="fastpostform">
  <input name="formhash" value="1a1ca082">
  <input name="noticeauthor" value="token123">
</form>
</body>
</html>
''';

    final detail = parser.parseThreadDetail(
      html,
      tid: '1',
      page: 1,
      baseUrl: 'https://bbs.binmt.cc',
    );

    expect(detail.formhash, '1a1ca082');
    expect(detail.fid, '44');
    expect(detail.noticeauthor, 'token123');
    expect(detail.currentUid, '157080');
    expect(detail.posts.first.page, 1);
    expect(detail.posts.length, 3);
    expect(detail.posts[0].content, contains('第一楼正文'));
    expect(detail.posts[0].content, contains('正文继续'));
    expect(detail.posts[0].images.single, 'https://oss3-bbs.mt2.cn/a.jpg');
    expect(detail.posts[1].authorName, '春江水');
    expect(detail.posts[1].content, '感谢分享！');
    expect(detail.posts[2].authorName, '若幻');
    expect(detail.posts[2].content, '看看');
  });
}
