import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

class AccountParser {
  const AccountParser();

  List<Thread> parseMyThreads(
    String body, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(body);
    final result = <Thread>[];

    for (final el in document.querySelectorAll('li.forumlist_li')) {
      final titleLink = el.querySelector(
        '.mmlist_li_box h2 a, h2 a[href*="thread-"]',
      );
      final href = titleLink?.attributes['href'] ?? '';
      final tid = RegExp(r'thread-(\d+)-')
          .firstMatch(href)
          ?.group(1);
      if (tid == null || tid.isEmpty) {
        continue;
      }

      final authorEl = el.querySelector('.top_user');
      final authorHref = authorEl?.attributes['href'] ?? '';
      final authorUid =
          RegExp(r'uid=(\d+)').firstMatch(authorHref)?.group(1);

      final stats = el.querySelectorAll(
        '.comiis_xznalist_bottom .comiis_tm',
      );

      String? likeCount = el
          .querySelector('.num-all_$tid')
          ?.text
          .trim();
      likeCount ??= stats.isNotEmpty ? _clean(stats[0].text) : null;

      final replyCount =
          stats.length > 1 ? _clean(stats[1].text) : null;
      final viewCount =
          stats.length > 2 ? _clean(stats[2].text) : null;

      final thumbnails = <String>[];
      for (final image in el.querySelectorAll(
        '.comiis_pyqlist_img img, .comiis_pyqlist_imgs img, .list_img img, .comiis_list_img img',
      )) {
        final src = image.attributes['file'] ??
            image.attributes['data-src'] ??
            image.attributes['data-original'] ??
            image.attributes['src'];
        final absolute = _absoluteUrl(src, baseUrl);
        if (absolute != null &&
            !absolute.contains('smiley') &&
            !absolute.contains('/static/image/') &&
            !thumbnails.contains(absolute)) {
          thumbnails.add(absolute);
          if (thumbnails.length >= 3) break;
        }
      }

      final itemText = _clean(el.text);
      final itemHtml = el.innerHtml.toLowerCase();
      final hasHiddenContent = itemText.contains('本内容被作者隐藏') ||
          itemText.contains('回复后可见') ||
          itemText.contains('回复可见') ||
          itemText.contains('查看隐藏内容') ||
          itemText.contains('隐藏内容') ||
          itemHtml.contains('showhide') ||
          itemHtml.contains('replyhide') ||
          itemHtml.contains('hidecontent');

      result.add(
        Thread(
          tid: tid,
          title: _nullable(titleLink?.text) ?? '未知标题',
          authorUid: authorUid,
          authorName: _nullable(authorEl?.text),
          replyCount: replyCount,
          viewCount: viewCount,
          likeCount: likeCount,
          lastReplyTime: _nullable(
            el.querySelector('.forumlist_li_time .f_d, span.f_d')?.text,
          ),
          excerpt: _cleanThreadExcerpt(el.querySelector('.list_body a')?.text),
          thumbnails: thumbnails,
          hasHiddenContent: hasHiddenContent,
        ),
      );
    }

    return result;
  }

  UserGroupData parseUserGroup(String body) {
    final document = html_parser.parse(body);
    final head = document.querySelector('.comiis_levhead');

    final heading = _clean(head?.querySelector('h2')?.text ?? '');
    final groupName = RegExp(r'我的等级\s*[:：]\s*(.+)')
            .firstMatch(heading)
            ?.group(1)
            ?.trim() ??
        heading.replaceFirst('我的等级', '').trim();

    final levelBar = head?.querySelector('.lev_x');
    final directLevelLabels = levelBar?.children
            .where((element) => element.localName == 'em')
            .map((element) => _clean(element.text))
            .where((value) => value.isNotEmpty)
            .toList() ??
        const <String>[];

    final currentLevel =
        directLevelLabels.isNotEmpty ? directLevelLabels.first : '';
    final nextLevel =
        directLevelLabels.length > 1 ? directLevelLabels.last : '';

    final progressStyle = levelBar
            ?.querySelector('span.flex em')
            ?.attributes['style'] ??
        '';
    final progressPercent = double.tryParse(
          RegExp(r'width\s*:\s*([\d.]+)%', caseSensitive: false)
                  .firstMatch(progressStyle)
                  ?.group(1) ??
              '',
        ) ??
        0;

    final upgrade = head?.querySelector('h3');
    final upgradeText = _clean(upgrade?.text ?? '');
    final pointsNeeded = _clean(upgrade?.querySelector('span')?.text ?? '');
    final nextGroupName = RegExp(r'升级到\s*(.+)$')
            .firstMatch(upgradeText)
            ?.group(1)
            ?.trim() ??
        '';

    final permissions = <UserGroupPermission>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('tr')) {
      final th = row.querySelector('th');
      final td = row.querySelector('td');
      if (th == null || td == null) continue;

      final name = _clean(th.text);
      if (name.isEmpty || !seen.add(name)) continue;

      final rawText = td.text;
      var value = _clean(rawText);
      bool? allowed;

      if (RegExp(r'[✓✔√]').hasMatch(rawText)) {
        allowed = true;
      } else if (RegExp(r'[✗✘×]').hasMatch(rawText)) {
        allowed = false;
      } else {
        final hint = [
          td.attributes['title'] ?? '',
          td.attributes['aria-label'] ?? '',
          ...td.querySelectorAll('[title], [alt], [aria-label]').expand(
                (element) => [
                  element.attributes['title'] ?? '',
                  element.attributes['alt'] ?? '',
                  element.attributes['aria-label'] ?? '',
                ],
              ),
        ].join(' ');
        final cleanHint = _clean(hint);
        if (RegExp(r'不允许|禁止|不可用|关闭|否').hasMatch(cleanHint)) {
          allowed = false;
        } else if (RegExp(r'允许|可用|开启|是|通过').hasMatch(cleanHint)) {
          allowed = true;
        }
      }

      // COMIIS 的布尔权限经常只输出 icon font，文本会在清洗后为空。
      // f_a 通常表示可用/强调，f_d 表示禁用/灰色；仅在纯图标值时兜底判断。
      if (allowed == null && value.isEmpty) {
        final iconClasses = td
            .querySelectorAll('i, em, span')
            .expand((element) => element.classes)
            .map((value) => value.toLowerCase())
            .toSet();
        if (iconClasses.contains('f_a')) {
          allowed = true;
        } else if (iconClasses.contains('f_d')) {
          allowed = false;
        }
      }

      if (allowed != null && value.isEmpty) {
        value = allowed ? '允许' : '不允许';
      }
      if (value.isEmpty) value = '—';

      permissions.add(
        UserGroupPermission(
          name: name,
          value: value,
          allowed: allowed,
        ),
      );
    }

    return UserGroupData(
      groupName: groupName,
      currentLevel: currentLevel,
      nextLevel: nextLevel,
      progress: (progressPercent / 100).clamp(0.0, 1.0).toDouble(),
      pointsNeeded: pointsNeeded,
      nextGroupName: nextGroupName,
      permissions: permissions,
    );
  }

  List<FavoriteItem> parseFavorites(String body) {
    final document = html_parser.parse(body);
    final result = <FavoriteItem>[];

    for (final el in document.querySelectorAll('li.mysclist_li')) {
      final titleLink = el.querySelector('h2 a');
      if (titleLink == null) {
        continue;
      }

      final href = titleLink.attributes['href'] ?? '';
      final tid = RegExp(r'thread-(\d+)-')
          .firstMatch(href)
          ?.group(1);

      final deleteHref = el
              .querySelector('a[href*="ac=favorite"][href*="op=delete"]')
              ?.attributes['href'] ??
          '';
      final favid = RegExp(r'favid=(\d+)')
              .firstMatch(deleteHref)
              ?.group(1) ??
          '';

      final type = el.querySelector('img.t')?.attributes['alt'] ?? '';

      result.add(
        FavoriteItem(
          favid: favid,
          title: _clean(titleLink.text),
          type: type,
          href: href,
          tid: tid,
        ),
      );
    }

    return result;
  }

  List<FriendItem> parseFriends(
    String body, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(body);
    final result = <FriendItem>[];
    final seen = <String>{};

    for (final el in document.querySelectorAll('li.b_t')) {
      final nameLink = el.querySelector('.tit a');
      final username = _clean(nameLink?.text ?? '');
      if (username.isEmpty) {
        continue;
      }

      final candidates = <String>[
        nameLink?.attributes['href'] ?? '',
        el.querySelector('.list01_limg')?.attributes['href'] ?? '',
        el
                .querySelector('a[href*="do=pm"][href*="touid="]')
                ?.attributes['href'] ??
            '',
        el
                .querySelector('a[href*="ac=friend"][href*="op=ignore"]')
                ?.attributes['href'] ??
            '',
      ];

      String? uid;
      for (final href in candidates) {
        uid = RegExp(r'(?:uid|touid)=(\d+)')
            .firstMatch(href)
            ?.group(1);
        if (uid != null) {
          break;
        }
      }

      if (uid == null || uid.isEmpty || !seen.add(uid)) {
        continue;
      }

      final avatarRaw = el
          .querySelector('.list01_limg img')
          ?.attributes['src'];
      final messageUrl = el
          .querySelector('a[href*="do=pm"][href*="touid="]')
          ?.attributes['href'];

      result.add(
        FriendItem(
          uid: uid,
          username: username,
          avatarUrl: _absoluteUrl(avatarRaw, baseUrl),
          messageUrl: messageUrl,
        ),
      );
    }

    return result;
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD\u25A1]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String? _cleanThreadExcerpt(String? value) {
    if (value == null) {
      return null;
    }
    var clean = _clean(value);
    clean = clean
        .replaceAll(
          RegExp(r'[*＊\s]*本(?:帖)?内容被作者隐藏[*＊\s]*'),
          ' ',
        )
        .replaceAll(
          RegExp(r'[*＊\s]*本帖隐藏的内容\s*[:：]?[*＊\s]*'),
          ' ',
        )
        .replaceAll(
          RegExp(r'[*＊\s]*(?:回复后可见|回复可见|查看隐藏内容)[*＊\s]*'),
          ' ',
        );
    clean = _clean(clean);
    return clean.isEmpty ? null : clean;
  }

  String? _nullable(String? value) {
    if (value == null) {
      return null;
    }
    final clean = _clean(value);
    return clean.isEmpty ? null : clean;
  }

  String? _absoluteUrl(String? raw, String baseUrl) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    if (value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '$baseUrl$value';
    }
    return '$baseUrl/$value';
  }
}
