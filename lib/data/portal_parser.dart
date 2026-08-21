import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

class PortalParser {
  const PortalParser();

  List<MallItem> parseMallList(
    String html, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(html);
    final result = <MallItem>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll('li.col-xs-12.bg_f')) {
      final link = item.querySelector(
        'a[href*="keke_integralmall-view.html?tid="]',
      );
      final href = link?.attributes['href'] ?? '';
      final tid = RegExp(r'tid=(\d+)').firstMatch(href)?.group(1);

      if (tid == null || !seen.add(tid)) {
        continue;
      }

      final title = _clean(item.querySelector('.mall-info h4')?.text ?? '');
      final image = _absoluteUrl(
        item.querySelector('.listpic img')?.attributes['src'],
        baseUrl,
      );
      final price = _firstInt(
        item.querySelector('.discount-price i')?.text ?? '',
      );
      final marketPrice = _nullable(
        _clean(item.querySelector('.price-sell')?.text ?? ''),
      );
      final remaining = _firstInt(
        item.querySelector('.count-r')?.text ?? '',
      );
      final purchased = _firstInt(
        item.querySelector('.count-l')?.text ?? '',
      );
      final endTimeElement = item.querySelector('[endtime]');
      final endTime = (
        endTimeElement?.attributes['endtime'] ??
        endTimeElement?.attributes['endTime']
      )?.trim();

      result.add(
        MallItem(
          tid: tid,
          title: title.isEmpty ? '未命名商品' : title,
          imageUrl: image,
          priceGold: price,
          marketPrice: marketPrice,
          remaining: remaining,
          purchased: purchased,
          endTime: endTime,
        ),
      );
    }

    return result;
  }

  MallDetail parseMallDetail(
    String html, {
    required String tid,
    required String baseUrl,
  }) {
    final document = html_parser.parse(html);

    var title = _clean(document.querySelector('title')?.text ?? '');
    title = title.replaceAll(RegExp(r'\s*-\s*MT论坛.*$'), '').trim();

    final h = _clean(
      document.querySelector(
            '.mall-info h4, .item-info h4, h1, h2',
          )?.text ??
          '',
    );
    if (h.isNotEmpty) {
      title = h;
    }

    final image = _absoluteUrl(
      document.querySelector(
            '.listpic img, .item-pic img, .mall-pro-main img',
          )?.attributes['src'],
      baseUrl,
    );

    final price = _firstInt(
      document.querySelector('.price-real i')?.text ??
          document.querySelector('.discount-price i')?.text ??
          '',
    );

    final marketPrice = _nullable(
      _clean(document.querySelector('.price-sell')?.text ?? ''),
    );

    final buyUrl = _absoluteUrl(
      document.querySelector('.item-btn a.buy-btn')?.attributes['href'],
      baseUrl,
    );

    final cardStatusUrl = _absoluteUrl(
      document.querySelector('.item-btn a.detail-btn')?.attributes['href'],
      baseUrl,
    );

    return MallDetail(
      tid: tid,
      title: title.isEmpty ? '商品详情' : title,
      imageUrl: image,
      priceGold: price,
      marketPrice: marketPrice,
      buyUrl: buyUrl,
      cardStatusUrl: cardStatusUrl,
    );
  }

  String parsePopupText(String html) {
    final document = html_parser.parseFragment(html);
    return _clean(document.text ?? '');
  }

  static List<ForumGroup> defaultForumGroups() {
    return const [
      ForumGroup(
        id: '1',
        name: 'MT专区',
        boards: [
          ForumBoard(fid: '2', name: '版本发布'),
          ForumBoard(fid: '37', name: '插件交流'),
          ForumBoard(fid: '38', name: '建议反馈'),
        ],
      ),
      ForumGroup(
        id: '36',
        name: '交流与讨论',
        boards: [
          ForumBoard(fid: '41', name: '逆向交流'),
          ForumBoard(fid: '39', name: '玩机交流'),
          ForumBoard(fid: '42', name: '编程开发'),
          ForumBoard(fid: '40', name: '求助问答'),
          ForumBoard(fid: '44', name: '综合交流'),
          ForumBoard(fid: '50', name: '休闲灌水'),
        ],
      ),
      ForumGroup(
        id: '45',
        name: '论坛事务',
        boards: [
          ForumBoard(fid: '46', name: '官方公告'),
          ForumBoard(fid: '53', name: '申诉举报'),
        ],
      ),
    ];
  }

  List<ForumGroup> parseForumGroups(
    String html, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(html);

    // 先扫描整页所有 forum-{fid}-*.html。
    // 论坛模板即使把版块 li 包进额外容器，依然可以拿到版块信息。
    final discovered = <String, ForumBoard>{};

    for (final link in document.querySelectorAll('a[href*="forum-"]')) {
      final href = link.attributes['href'] ?? '';
      final fid = RegExp(r'forum-(\d+)(?:-\d+)?\.html')
              .firstMatch(href)
              ?.group(1) ??
          RegExp(r'forum-(\d+)').firstMatch(href)?.group(1);

      if (fid == null || discovered.containsKey(fid)) {
        continue;
      }

      final parent = link.parent;
      var name = _clean(
        link.querySelector('p')?.text ??
            parent?.querySelector('p')?.text ??
            '',
      );

      final img = link.querySelector('img') ?? parent?.querySelector('img');
      if (name.isEmpty) {
        name = _clean(img?.attributes['alt'] ?? '');
      }
      if (name.isEmpty) {
        name = _clean(link.text);
      }

      discovered[fid] = ForumBoard(
        fid: fid,
        name: name,
        iconUrl: _absoluteUrl(img?.attributes['src'], baseUrl),
      );
    }

    // 再尝试按模板里的分组标题顺序解析，方便未来新增未知版块。
    final parsedGroups = <ForumGroup>[];
    String? currentId;
    String? currentName;
    var boards = <ForumBoard>[];
    final assigned = <String>{};

    void flush() {
      final id = currentId;
      final name = currentName;
      if (id == null || name == null || boards.isEmpty) {
        return;
      }

      parsedGroups.add(
        ForumGroup(
          id: id,
          name: name,
          boards: List<ForumBoard>.unmodifiable(boards),
        ),
      );
    }

    for (final li in document.querySelectorAll('li')) {
      if (li.classes.contains('comiis_fxpostlistkey')) {
        flush();
        currentId = li.attributes['fid']?.trim();
        currentName = _clean(li.querySelector('a')?.text ?? '');
        boards = <ForumBoard>[];
        continue;
      }

      if (currentId == null || currentName == null) {
        continue;
      }

      final link = li.querySelector('a[href*="forum-"]');
      if (link == null) {
        continue;
      }

      final href = link.attributes['href'] ?? '';
      final fid = RegExp(r'forum-(\d+)(?:-\d+)?\.html')
              .firstMatch(href)
              ?.group(1) ??
          RegExp(r'forum-(\d+)').firstMatch(href)?.group(1);

      if (fid == null || !assigned.add(fid)) {
        continue;
      }

      final fromScan = discovered[fid];
      if (fromScan != null) {
        boards.add(fromScan);
      }
    }
    flush();

    if (parsedGroups.isNotEmpty) {
      return parsedGroups;
    }

    // 最后使用已经抓包确认的稳定版块表作为兜底。
    // 这保证论坛 HTML 模板发生变化时，“社区”不会整页空白。
    return defaultForumGroups()
        .map(
          (group) => ForumGroup(
            id: group.id,
            name: group.name,
            boards: group.boards
                .map((fallback) {
                  final live = discovered[fallback.fid];
                  if (live == null) {
                    return fallback;
                  }

                  return ForumBoard(
                    fid: fallback.fid,
                    name: live.name.isEmpty ? fallback.name : live.name,
                    iconUrl: live.iconUrl,
                  );
                })
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  int? _firstInt(String value) {
    final raw = RegExp(r'(\d+)').firstMatch(value)?.group(1);
    return raw == null ? null : int.tryParse(raw);
  }

  String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _nullable(String value) => value.isEmpty ? null : value;

  String? _absoluteUrl(String? value, String baseUrl) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final raw = value.trim();
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      return raw;
    }

    return Uri.parse(baseUrl).resolve(raw).toString();
  }
}
