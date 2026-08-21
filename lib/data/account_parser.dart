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
      for (final image
          in el.querySelectorAll('.comiis_pyqlist_imgs img')) {
        final src = image.attributes['src'] ??
            image.attributes['data-src'];
        final absolute = _absoluteUrl(src, baseUrl);
        if (absolute != null && !thumbnails.contains(absolute)) {
          thumbnails.add(absolute);
        }
      }

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
          excerpt: _nullable(el.querySelector('.list_body a')?.text),
          thumbnails: thumbnails,
        ),
      );
    }

    return result;
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
