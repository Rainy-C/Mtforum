import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/forum_parser.dart';

void main() {
  const parser = ForumParser();

  test('帖子列表标题清理 icon font 私有字符和方框', () {
    const html = '''
    <li class="forumlist_li">
      <div class="mmlist_li_box">
        <h2><a href="thread-171999-1-1.html">\uE001□ MT管理器2.26.8正式版</a></h2>
      </div>
    </li>
    ''';

    final items = parser.parseThreadList(
      html,
      baseUrl: 'https://bbs.binmt.cc',
    );
    expect(items.single.title, 'MT管理器2.26.8正式版');
  });
}
