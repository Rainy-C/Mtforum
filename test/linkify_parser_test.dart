import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';
import 'package:mtforum/models/models.dart';

void main() {
  const parser = ForumParser();

  test('正文裸链接会转换为可点击 PostContent.link', () {
    const html = r'''
<html>
<head><title>裸链接测试 - MT论坛</title></head>
<body class="forum-viewforum-fid-44">
<script>var formhash = '590fe629';</script>
<input name="noticeauthor" value="token">
<div id="pid101">
  <a class="top_user">Tester</a>
  <div class="comiis_message_table">
    官网：https://example.com/releases/app.apk
    镜像：www.example.org/download
    文档：docs.example.net/guide/index.html。
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

    expect(detail.posts, hasLength(1));

    final links = detail.posts.single.richContent
        .where((item) => item.type == PostContentType.link)
        .toList();

    expect(links, hasLength(3));
    expect(links[0].url, 'https://example.com/releases/app.apk');
    expect(links[1].url, 'https://www.example.org/download');
    expect(links[2].url, 'https://docs.example.net/guide/index.html');
    expect(links[2].text, 'docs.example.net/guide/index.html');
  });
}
