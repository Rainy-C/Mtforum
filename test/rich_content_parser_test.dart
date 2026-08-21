import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';
import 'package:mtforum/models/models.dart';

void main() {
  const parser = ForumParser();

  test('Discuz HTML 富文本解析', () {
    const html = r'''
<html>
<head><title>富文本测试 - MT论坛</title></head>
<body class="forum-viewforum-fid-44">
<script>var formhash = '590fe629';</script>
<form id="fastpostform">
<input name="noticeauthor" value="token">
</form>
<div id="pid100">
  <a class="top_user" href="home.php?mod=space&uid=1">Tester</a>
  <a class="top_lev">Lv.3</a>
  <span class="kmtime">刚刚</span>
  <div class="comiis_a comiis_message_table cl">
    普通文字<br>
    <strong>加粗</strong>
    <a href="https://www.baidu.com">文字链接</a>
    <div class="comiis_blockcode"><ol><li>int main()</li><li>{ return 0; }</li></ol></div>
    <div class="comiis_quote">你好</div>
    <img src="https://www.example.com/1.jpg">
    [audio]https://www.example.com/1.mp3[/audio]
    [media=x,500,375]https://www.example.com/1.mp4[/media]
    [flash]https://www.flash.com/test.swf[/flash]
    [free]购买前可免费浏览的内容[/free]
  </div>
  <a href="forum.php?mod=post&action=reply&fid=44&tid=1&repquote=100">回复</a>
</div>
</body>
</html>
''';

    final detail = parser.parseThreadDetail(
      html,
      tid: '1',
      page: 1,
      baseUrl: 'https://bbs.binmt.cc',
    );

    expect(detail.posts, hasLength(1));

    final types = detail.posts.single.richContent
        .map((item) => item.type)
        .toList();

    expect(types, contains(PostContentType.bold));
    expect(types, contains(PostContentType.link));
    expect(types, contains(PostContentType.code));
    expect(types, contains(PostContentType.quote));
    expect(types, contains(PostContentType.image));
    expect(types, contains(PostContentType.audio));
    expect(types, contains(PostContentType.video));
    expect(types, contains(PostContentType.flash));
    expect(types, contains(PostContentType.free));

    final code = detail.posts.single.richContent
        .firstWhere((item) => item.type == PostContentType.code)
        .text;

    expect(code, contains('int main()'));
    expect(code, contains('return 0'));
  });

  test('原始 BBCode 兜底解析', () {
    const html = r'''
<html>
<head><title>BBCode - MT论坛</title></head>
<body class="forum-viewforum-fid-44">
<script>var formhash = '590fe629';</script>
<input name="noticeauthor" value="token">
<div id="pid101">
  <a class="top_user">Tester</a>
  <div class="comiis_message_table">
    [url=https://www.baidu.com]百度[/url]
    [img]https://www.example.com/1.jpg[/img]
    [quote]你好[/quote]
    [code]int main[/code]
    [free]免费信息[/free]
  </div>
</div>
</body>
</html>
''';

    final detail = parser.parseThreadDetail(
      html,
      tid: '1',
      page: 1,
      baseUrl: 'https://bbs.binmt.cc',
    );

    final types = detail.posts.single.richContent
        .map((item) => item.type)
        .toSet();

    expect(types.contains(PostContentType.link), isTrue);
    expect(types.contains(PostContentType.image), isTrue);
    expect(types.contains(PostContentType.quote), isTrue);
    expect(types.contains(PostContentType.code), isTrue);
    expect(types.contains(PostContentType.free), isTrue);
  });
}
