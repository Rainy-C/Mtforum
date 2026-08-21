import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/portal_parser.dart';

void main() {
  const parser = PortalParser();
  const baseUrl = 'https://bbs.binmt.cc';

  test('积分商城列表解析', () {
    const html = '''
    <ul>
      <li class="col-xs-12 bg_f">
        <div class="mall-pro-main clearfix">
          <a href="keke_integralmall-view.html?tid=170285">
            <div class="listpic">
              <img src="forum.php?mod=image&aid=369160&size=170x170">
            </div>
          </a>
          <div class="mall-info">
            <a href="keke_integralmall-view.html?tid=170285">
              <h4>MT管理器月费卡密（第六十五期）</h4>
              <p class="mrl-discount">
                <span class="discount-price">抢购价<em><i>200</i> 金币</em></span>
              </p>
              <span class="price-sell">￥9.00</span>
              <span class="time" endTime="2026-10-31 00:36:00"></span>
              <p class="mall-count">
                <span class="count-r">仅剩149件</span>
                <span class="count-l">已抢购151件</span>
              </p>
            </a>
          </div>
        </div>
      </li>
    </ul>
    ''';

    final items = parser.parseMallList(html, baseUrl: baseUrl);

    expect(items, hasLength(1));
    expect(items.single.tid, '170285');
    expect(items.single.title, contains('MT管理器'));
    expect(items.single.priceGold, 200);
    expect(items.single.remaining, 149);
    expect(items.single.purchased, 151);
    expect(items.single.endTime, '2026-10-31 00:36:00');
    expect(items.single.imageUrl, startsWith(baseUrl));
  });

  test('积分商城详情按钮解析', () {
    const html = '''
    <html>
      <head><title>MT管理器月费卡密（第六十五期） - MT论坛</title></head>
      <body>
        <span class="price-real">抢购价 <i>200金币</i></span>
        <span class="price-sell">市价￥9.00</span>
        <div class="item-btn">
          <a class="buy-btn"
             href="plugin.php?id=keke_integralmall:show_win&tid=170285&ac=xd&formhash=590fe629&mobile=2">
             立即抢购
          </a>
          <a class="detail-btn"
             href="plugin.php?id=keke_integralmall:show_win&tid=170285&ac=km&formhash=590fe629&mobile=2">
             查看卡密状态
          </a>
        </div>
      </body>
    </html>
    ''';

    final detail = parser.parseMallDetail(
      html,
      tid: '170285',
      baseUrl: baseUrl,
    );

    expect(detail.tid, '170285');
    expect(detail.priceGold, 200);
    expect(detail.buyUrl, contains('ac=xd'));
    expect(detail.cardStatusUrl, contains('ac=km'));
  });

  test('社区版块分组解析', () {
    const html = '''
    <ul>
      <li class="comiis_fxpostlistkey" fid="1">
        <a href="javascript:;">MT专区</a>
      </li>
      <li>
        <a href="https://bbs.binmt.cc/forum-2-1.html" class="b_b b_r">
          <em>
            <img src="https://cdn-bbs.mt2.cn/data/attachment/common/c8/common_2_icon.png"
                 alt="版本发布" />
          </em>
          <p>版本发布</p>
        </a>
      </li>
      <li class="comiis_fxpostlistkey" fid="36">
        <a href="javascript:;">交流与讨论</a>
      </li>
      <li>
        <a href="https://bbs.binmt.cc/forum-41-1.html">
          <img src="icon.png" alt="逆向交流" />
          <p>逆向交流</p>
        </a>
      </li>
    </ul>
    ''';

    final groups = parser.parseForumGroups(
      html,
      baseUrl: baseUrl,
    );

    expect(groups, hasLength(2));
    expect(groups[0].id, '1');
    expect(groups[0].name, 'MT专区');
    expect(groups[0].boards.single.fid, '2');
    expect(groups[0].boards.single.name, '版本发布');
    expect(groups[1].id, '36');
    expect(groups[1].boards.single.fid, '41');
  });
}
