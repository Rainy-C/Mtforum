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

  List<MallCardPurchase> parseMallCardPurchases(String html) {
    final document = html_parser.parse(html);
    final buyList = document.querySelector('#buylist');
    if (buyList == null) {
      return const [];
    }

    final purchases = <MallCardPurchase>[];
    final seen = <String>{};

    for (final item in buyList.children) {
      final cardLink = item.querySelector('.views a[href*="ac=km"]');
      final href = cardLink?.attributes['href'] ?? '';
      final tid = RegExp(r'(?:[?&]|&amp;)tid=(\d+)')
          .firstMatch(href)
          ?.group(1);
      if (tid == null || !seen.add(tid)) {
        continue;
      }

      final title = _clean(item.querySelector('.mall-info h4 a')?.text ?? '');
      final orderedAt = _clean(
        item.querySelector('.sytime i')?.text ??
            item.querySelector('.sytime')?.text.replaceFirst('下单时间：', '') ??
            '',
      );
      final state = _nullable(_clean(item.querySelector('.sta')?.text ?? ''));

      purchases.add(
        MallCardPurchase(
          tid: tid,
          title: title.isEmpty ? '卡密订单' : title,
          orderedAt: orderedAt,
          status: state,
        ),
      );
    }

    return purchases;
  }

  List<MallCardRecord> parseMallCardRecords(String html) {
    final document = html_parser.parse(html);
    final records = <MallCardRecord>[];

    for (final row in document.querySelectorAll('.kmdis .kmlist p')) {
      final card = _clean(row.querySelector('.kmnr')?.text ?? '');
      if (card.isEmpty) {
        continue;
      }

      final exchangedAt = _clean(
        row.querySelector('.kmtime')?.text ??
            row.querySelector('.gmtime')?.text ??
            '',
      );
      final state = _nullable(
        _clean(row.querySelector('.gmstate')?.text ?? ''),
      );

      records.add(
        MallCardRecord(
          card: card,
          exchangedAt: exchangedAt,
          status: state,
        ),
      );
    }

    return records;
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

  /// 解析论坛会员排行榜（misc.php?mod=ranklist&type=member）。
  ///
  /// Comiis 模板会把前三名放在 `.comiis_rankhot` 中，后续名次使用另一套
  /// 列表 DOM；不同榜单/模板版本的 class 也并不完全一致。这里不再只依赖
  /// 一个固定 selector，而是查找“位于 rank 容器内、并包含 uid 链接”的
  /// li/dl/tr 行，再统一解析并按 uid 去重，这样前三名和后续排名都会保留。
  List<RankItem> parseRanklist(
    String html, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(html);
    final result = <RankItem>[];
    final seenUid = <String>{};

    bool isInsideRankArea(dynamic element) {
      dynamic current = element;
      for (var depth = 0; current != null && depth < 8; depth++) {
        final id = '${current.attributes?['id'] ?? ''}'.toLowerCase();
        final className = '${current.attributes?['class'] ?? ''}'.toLowerCase();
        if (id.contains('rank') || className.contains('rank')) {
          return true;
        }
        current = current.parent;
      }
      return false;
    }

    final rows = <dynamic>[];
    final seenRows = <dynamic>{};

    // 主路径：按 DOM 顺序扫描排行榜区域中的候选行，避免把前三名与普通
    // 排名拆成两个独立列表后顺序错乱。
    for (final row in document.querySelectorAll('li, dl, tr')) {
      if (row.querySelector('a[href*="uid="]') == null) continue;
      if (!isInsideRankArea(row)) continue;
      if (seenRows.add(row)) rows.add(row);
    }

    // 某些精简模板的父容器 class 不包含 rank，保留已知 selector 兜底。
    if (rows.isEmpty) {
      for (final selector in const [
        '.comiis_rankhot li',
        '.comiis_ranklist_box li',
        '.comiis_ranklist li',
        '.comiis_rank_list li',
        '.ranklist li',
        '#ranklist li',
      ]) {
        for (final row in document.querySelectorAll(selector)) {
          if (row.querySelector('a[href*="uid="]') == null) continue;
          if (seenRows.add(row)) rows.add(row);
        }
      }
    }

    for (final row in rows) {
      final profileAnchors = row.querySelectorAll('a[href*="uid="]');
      if (profileAnchors.isEmpty) continue;

      String? uid;
      dynamic profileAnchor;
      for (final anchor in profileAnchors) {
        final href = anchor.attributes['href'] ?? '';
        final parsedUid = RegExp(r'uid=(\d+)').firstMatch(href)?.group(1);
        if (parsedUid != null && parsedUid.isNotEmpty) {
          uid = parsedUid;
          profileAnchor = anchor;
          break;
        }
      }
      if (uid == null || !seenUid.add(uid)) continue;

      String username = '';
      for (final selector in const [
        '.top_user',
        'h2 a[href*="uid="]',
        '.user_name a[href*="uid="]',
        '.user_name',
        '.name a[href*="uid="]',
        '.name',
        'h2 span.vm',
        'h2 span',
      ]) {
        username = _clean(row.querySelector(selector)?.text ?? '');
        if (username.isNotEmpty) break;
      }
      if (username.isEmpty) {
        // 头像链接通常没有文字，优先从其它 uid 链接寻找可见用户名。
        for (final anchor in profileAnchors) {
          final text = _clean(anchor.text);
          if (text.isNotEmpty) {
            username = text;
            profileAnchor = anchor;
            break;
          }
        }
      }
      if (username.isEmpty) continue;

      // 排名：图片 alt / data-rank / 可见数字，最后才按解析顺序补位。
      var rank = int.tryParse(
            row.querySelector('em img')?.attributes['alt'] ?? '',
          ) ??
          int.tryParse(row.attributes['data-rank'] ?? '') ??
          0;
      if (rank <= 0) {
        for (final selector in const [
          '.rank_num',
          '.ranknum',
          '.num',
          '.order',
          'em',
        ]) {
          final text = _clean(row.querySelector(selector)?.text ?? '');
          final match = RegExp(r'(\d+)').firstMatch(text);
          final parsed = int.tryParse(match?.group(1) ?? '');
          if (parsed != null && parsed > 0) {
            rank = parsed;
            break;
          }
        }
      }
      if (rank <= 0) rank = result.length + 1;

      // 头像：先只认明确的用户头像节点。前三名区域常把奖牌图也放在
      // `.user_img` 内，不能把 `.user_img img` 的第一张图直接当头像。
      String? avatarSrc;
      final preferredAvatar = row.querySelector(
        'img.top_tximg, '
        'img[src*="avatar.php"], '
        'img[data-src*="avatar.php"], '
        'img[data-original*="avatar.php"]',
      );
      if (preferredAvatar != null) {
        avatarSrc = preferredAvatar.attributes['src'] ??
            preferredAvatar.attributes['data-src'] ??
            preferredAvatar.attributes['data-original'];
      }

      // 第 4 名以后如果模板使用了非 avatar.php 的头像地址，再从普通图片中
      // 兜底，但必须排除 <em> 中的排名/奖牌图片。前三名若没有明确头像，
      // 直接按 uid 生成 Discuz 头像地址，避免把奖牌或性别图标当成头像。
      if ((avatarSrc == null || avatarSrc.trim().isEmpty) && rank > 3) {
        for (final image in row.querySelectorAll('img')) {
          dynamic parent = image.parent;
          var insideRankEm = false;
          while (parent != null && parent != row) {
            if (parent.localName == 'em') {
              insideRankEm = true;
              break;
            }
            parent = parent.parent;
          }
          if (insideRankEm) continue;
          final src = image.attributes['src'] ??
              image.attributes['data-src'] ??
              image.attributes['data-original'];
          if (src != null && src.trim().isNotEmpty) {
            avatarSrc = src;
            break;
          }
        }
      }

      final avatarUrl = _absoluteUrl(avatarSrc, baseUrl) ??
          _absoluteUrl('/uc_server/avatar.php?uid=$uid&size=middle', baseUrl);

      String? gender;
      final genderEl = row.querySelector('.user_gender, [class*="gender"]');
      if (genderEl != null) {
        final cls = genderEl.classes.join(' ').toLowerCase();
        final text = _clean(genderEl.text);
        if (cls.contains('girl') || cls.contains('female') || text == '女') {
          gender = '女';
        } else if (cls.contains('boy') ||
            cls.contains('male') ||
            text == '男') {
          gender = '男';
        }
      }

      String value = '';
      for (final selector in const [
        '.user_txt',
        '.rank_value',
        '.rankvalue',
        '.user_value',
        '.user_num',
        '.xg1',
        '.f_d',
      ]) {
        final text = _clean(row.querySelector(selector)?.text ?? '');
        if (text.isNotEmpty && text != username && text != '$rank') {
          value = text;
          break;
        }
      }
      if (value.isEmpty) {
        // 最后从整行文本中移除用户名和纯排名，保留榜单数值/描述。
        var text = _clean(row.text);
        text = text.replaceFirst(username, '').trim();
        text = text.replaceFirst(RegExp('^${RegExp.escape('$rank')}\\s*'), '');
        value = _clean(text);
      }

      result.add(RankItem(
        uid: uid,
        username: username,
        avatarUrl: avatarUrl,
        rank: rank,
        gender: gender,
        value: value,
      ));
    }

    // 部分模板把后续列表放在前三名之前/之后但 rank 数字本身是准确的。
    // 只在 rank 唯一且有效时按名次排序，避免模板 DOM 顺序异常。
    final ranks = result.map((e) => e.rank).toList();
    if (ranks.length == ranks.toSet().length && ranks.every((e) => e > 0)) {
      result.sort((a, b) => a.rank.compareTo(b.rank));
    }

    return result;
  }

}
