import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/portal_parser.dart';

void main() {
  const parser = PortalParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('社区标准模板解析', () {
    const html = '''
    <ul>
      <li class="comiis_fxpostlistkey" fid="1">
        <a href="javascript:;">MT专区</a>
      </li>
      <li>
        <a href="https://bbs.binmt.cc/forum-2-1.html">
          <img src="https://cdn-bbs.mt2.cn/icon.png" alt="版本发布">
          <p>版本发布</p>
        </a>
      </li>
    </ul>
    ''';

    final groups = parser.parseForumGroups(html, baseUrl: baseUrl);

    expect(groups, hasLength(1));
    expect(groups.single.id, '1');
    expect(groups.single.boards.single.fid, '2');
    expect(groups.single.boards.single.name, '版本发布');
  });

  test('社区模板变化时不会返回空白', () {
    const html = '''
    <div class="totally-new-template">
      <a href="/forum-41-1.html">
        <img src="/icon41.png" alt="逆向交流">
      </a>
    </div>
    ''';

    final groups = parser.parseForumGroups(html, baseUrl: baseUrl);

    expect(groups, hasLength(3));
    expect(
      groups.expand((group) => group.boards).map((board) => board.fid),
      containsAll(['2', '37', '38', '41', '39', '42', '40', '44', '50', '46', '53']),
    );

    final board41 = groups
        .expand((group) => group.boards)
        .firstWhere((board) => board.fid == '41');

    expect(board41.name, '逆向交流');
    expect(board41.iconUrl, '$baseUrl/icon41.png');
  });

  test('空 HTML 仍回退到确认过的版块清单', () {
    final groups = parser.parseForumGroups('', baseUrl: baseUrl);
    expect(groups, hasLength(3));
    expect(groups.expand((group) => group.boards), hasLength(11));
  });

  test('商城 endTime 大小写经 HTML parser 规范化后仍能解析', () {
    const html = '''
    <li class="col-xs-12 bg_f">
      <a href="keke_integralmall-view.html?tid=170285">
        <div class="listpic"><img src="x.png"></div>
      </a>
      <div class="mall-info">
        <a href="keke_integralmall-view.html?tid=170285">
          <h4>测试商品</h4>
          <span class="discount-price"><i>200</i></span>
          <span class="time" endTime="2026-10-31 00:36:00"></span>
        </a>
      </div>
    </li>
    ''';

    final items = parser.parseMallList(html, baseUrl: baseUrl);
    expect(items.single.endTime, '2026-10-31 00:36:00');
  });
}
