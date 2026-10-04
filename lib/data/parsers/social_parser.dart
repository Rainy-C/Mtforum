part of '../user_center_parser.dart';

extension _UserCenterParserSocialParserPart on UserCenterParser {
  List<SocialUser> parseSocialUsers(
    String raw, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final result = <SocialUser>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll('li.b_t')) {
      final nameLink = item.querySelector(
        '.tit a, h2 a, h3 a, h4 a, a.top_user',
      );
      final profileLink = nameLink ??
          item.querySelector(
            '.list01_limg[href*="uid="], '
            'a[href*="mod=space"][href*="uid="][href*="do=profile"]',
          );

      final href = profileLink?.attributes['href'] ?? '';
      final uid = RegExp(r'(?:^|[?&])uid=(\d+)')
          .firstMatch(href)
          ?.group(1);

      if (uid == null || uid == '0' || !seen.add(uid)) {
        continue;
      }

      final username = _sanitizeUsername(nameLink?.text ?? '');
      if (username.isEmpty) {
        continue;
      }

      final avatar = item.querySelector(
        '.list01_limg img, img[src*="avatar"], img[src*="uc_server"]',
      );
      final messageUrl = item
          .querySelector('a[href*="do=pm"][href*="touid=$uid"]')
          ?.attributes['href'];

      result.add(
        SocialUser(
          uid: uid,
          username: username,
          avatarUrl: _absoluteUrl(
            avatar?.attributes['src'],
            baseUrl,
          ),
          profileUrl: _absoluteUrl(href, baseUrl),
          messageUrl: _absoluteUrl(messageUrl, baseUrl),
        ),
      );
    }

    if (result.isNotEmpty) {
      return result;
    }

    for (final anchor in document.querySelectorAll(
      'a[href*="mod=space"][href*="uid="], '
      'a[href*="space&uid="]',
    )) {
      final href = anchor.attributes['href'] ?? '';

      if (href.contains('ac=friend') ||
          href.contains('ac=follow') ||
          href.contains('ac=poke') ||
          href.contains('do=pm')) {
        continue;
      }

      final uid =
          RegExp(r'(?:^|[?&])uid=(\d+)').firstMatch(href)?.group(1);

      if (uid == null || uid == '0' || !seen.add(uid)) {
        continue;
      }

      final container = _nearestContainer(anchor);
      final username = _sanitizeUsername(
        container?.querySelector(
              '.tit a, h2 a, h3 a, h4 a, a.top_user',
            )?.text ??
            anchor.text,
      );

      if (username.isEmpty) {
        continue;
      }

      final avatar = container?.querySelector(
        '.list01_limg img, img[src*="avatar"], '
        'img[src*="uc_server"], img',
      );
      final messageUrl = container
          ?.querySelector('a[href*="do=pm"][href*="touid=$uid"]')
          ?.attributes['href'];

      result.add(
        SocialUser(
          uid: uid,
          username: username,
          avatarUrl: _absoluteUrl(
            avatar?.attributes['src'],
            baseUrl,
          ),
          profileUrl: _absoluteUrl(href, baseUrl),
          messageUrl: _absoluteUrl(messageUrl, baseUrl),
        ),
      );
    }

    return result;
  }

  List<FriendRequestItem> parseFriendRequests(
    String raw, {
    required String baseUrl,
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);
    final result = <FriendRequestItem>[];
    final seen = <String>{};

    void addRequest({
      required String uid,
      required html_dom.Element container,
      required html_dom.Element accept,
    }) {
      if (uid.isEmpty || !seen.add(uid)) return;
      // “通过”链接的 mod=spacecp 也包含 mod=space，不能与用户主页链接
      // 混用一个 CSS 并集，否则 DOM 顺序会让按钮文字被当成用户名。
      var profile = container.querySelector('p.tit > a, p.tit a');
      if (profile == null) {
        for (final link in container.querySelectorAll('a[href*="uid=$uid"]')) {
          final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
          final uri = Uri.tryParse(href);
          if (uri?.queryParameters['mod'] == 'space' ||
              RegExp(r'space-uid-\d+', caseSensitive: false).hasMatch(href)) {
            profile = link;
            break;
          }
        }
      }
      var username = _clean(profile?.text ?? '');
      if (username.isEmpty) {
        username = _clean(
          container.querySelector('p.tit a, .tit a, h4 a, .xw1')?.text ?? '',
        );
      }
      if (username.isEmpty) username = 'UID $uid';

      final ignore = container.querySelector(
        'a[href*="ac=friend"][href*="op=ignore"][href*="uid=$uid"]',
      );
      final avatar = container.querySelector(
        'a.list01_limg img, img[src*="avatar.php?uid=$uid"], '
        'img[src*="avatar"], img[src*="uc_server"], img',
      );
      result.add(
        FriendRequestItem(
          uid: uid,
          username: username,
          avatarUrl: _absoluteUrl(avatar?.attributes['src'], baseUrl),
          acceptUrl: _absoluteUrl(accept.attributes['href'], baseUrl),
          requestTime: _sanitizeVisibleText(
            container.querySelector('p.txt font, .txt .f_d')?.text ?? '',
          ),
          isOnline: _sanitizeVisibleText(
            container.querySelector('font.kmtit, .kmtit')?.text ?? '',
          ).contains('在线'),
          ignoreUrl: _absoluteUrl(ignore?.attributes['href'], baseUrl),
        ),
      );
    }

    // mobile=2 已确认的稳定结构，优先按容器 ID 解析，避免弹窗链接的
    // class/handlekey 因模板变化而导致整个申请列表为空。
    for (final item in document.querySelectorAll(
      'li.b_t[id^="comiis_friendbox_"], li[id^="comiis_friendbox_"]',
    )) {
      final uid = RegExp(r'^comiis_friendbox_(\d+)$')
              .firstMatch(item.id)
              ?.group(1) ??
          '';
      final accept = item.querySelector(
        'a[href*="ac=friend"][href*="op=add"][href*="uid=$uid"]',
      );
      if (uid.isNotEmpty && accept != null) {
        addRequest(uid: uid, container: item, accept: accept);
      }
    }

    // 兼容 AJAX/桌面模板没有 comiis_friendbox_* ID 的结构。
    for (final add in document.querySelectorAll(
      'a[href*="ac=friend"][href*="op=add"][href*="uid="]',
    )) {
      final href = add.attributes['href'] ?? '';
      final uid =
          RegExp(r'(?:^|[?&])uid=(\d+)').firstMatch(href)?.group(1);
      if (uid == null || seen.contains(uid)) continue;

      final container = _nearestContainer(add);
      if (container != null) {
        addRequest(uid: uid, container: container, accept: add);
      }
    }

    return result;
  }

  List<WallComment> parseWallComments(
    String raw, {
    required String baseUrl,
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);
    final result = <WallComment>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll(
      r'dl[id^="comment_"][id$="_li"], .comiis_plli dl[id^="comment_"]',
    )) {
      final cid = RegExp(r'^comment_(\d+)_li$')
          .firstMatch(item.id)
          ?.group(1);
      if (cid == null || !seen.add(cid)) continue;

      final profileLink = item.querySelector(
        'dt a[href*="mod=space"][href*="uid="], '
        'dt a[href*="space&uid="], '
        'a.rzlist_tximg[href*="uid="]',
      );
      final href = profileLink?.attributes['href'] ?? '';
      final uid = RegExp(r'(?:^|[?&])uid=(\d+)')
              .firstMatch(href)
              ?.group(1) ??
          '';

      var username = _sanitizeUsername(
        item.querySelector('#author_$cid, .top_user')?.text ?? '',
      );
      if (username.isEmpty) {
        username = uid.isEmpty ? '论坛用户' : 'UID $uid';
      }

      final avatar = item.querySelector(
        'a.rzlist_tximg img, img.top_tximg, '
        'img[src*="avatar.php"], img[src*="uc_server"]',
      );
      final time = _sanitizeVisibleText(
        item.querySelector('.top_time')?.text ?? '',
      );
      final content = _sanitizeVisibleText(
        item.querySelector('dd.plface')?.text ?? '',
      );

      // 没有正文的占位节点不是有效留言。
      if (content.isEmpty) continue;

      result.add(
        WallComment(
          cid: cid,
          uid: uid,
          username: username,
          avatarUrl: _absoluteUrl(
            avatar?.attributes['src'] ?? avatar?.attributes['data-src'],
            baseUrl,
          ),
          time: time,
          content: content,
        ),
      );
    }

    return result;
  }

  PokePageData parsePokePage(
    String raw, {
    required String baseUrl,
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);
    final formhash = document
            .querySelector('input[name="formhash"]')
            ?.attributes['value']
            ?.trim() ??
        '';

    String textFromAttributes(html_dom.Element? element) {
      if (element == null) return '';
      // 不取 img 的 alt：招呼图标的 alt 通常是缩写字母代码（如“cy”），
      // 不能作为显示名称。
      for (final name in const [
        'data-name', 'data-label', 'data-title', 'title',
      ]) {
        final value = _sanitizeVisibleText(element.attributes[name] ?? '');
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    String textFromScript(String value) {
      for (final pattern in <RegExp>[
        RegExp(r'''(?:note\.value|note\s*=)\s*['"]([^'"]+)'''),
        RegExp(r'''['"]([^'"]{1,24})['"]\s*;?\s*return'''),
      ]) {
        final valueMatch = pattern.firstMatch(value);
        final candidate = _sanitizeVisibleText(valueMatch?.group(1) ?? '');
        if (candidate.isNotEmpty) return candidate;
      }
      return '';
    }

    final options = <PokeOption>[];
    final seen = <int>{};

    for (final input in document.querySelectorAll('input[name="iconid"]')) {
      final id = int.tryParse(input.attributes['value'] ?? '');
      if (id == null || !seen.add(id)) continue;

      html_dom.Element? labelElement;
      final inputId = input.attributes['id']?.trim() ?? '';
      if (inputId.isNotEmpty) {
        labelElement = document.querySelector('label[for="$inputId"]');
      }
      if (labelElement == null && input.parent?.localName == 'label') {
        labelElement = input.parent;
      }

      html_dom.Element? row = labelElement ?? input.parent;
      for (var i = 0; i < 3 && row != null; i++) {
        final directInputs = row.querySelectorAll('input[name="iconid"]');
        if (directInputs.length <= 1) break;
        row = row.parent;
      }

      final image = labelElement?.querySelector('img') ??
          row?.querySelector('img') ??
          input.parent?.querySelector('img');

      // 优先取 label 元素的可见文字（招呼名称，如“打招呼”）。
      var label = _sanitizeVisibleText(labelElement?.text ?? '');
      if (label.isEmpty) label = textFromAttributes(input);
      if (label.isEmpty) label = textFromAttributes(labelElement);
      if (label.isEmpty) {
        label = textFromScript(
          '${input.attributes['onclick'] ?? ''} '
          '${labelElement?.attributes['onclick'] ?? ''} '
          '${row?.attributes['onclick'] ?? ''}',
        );
      }
      if (label.isEmpty && row != null) {
        final rowText = _sanitizeVisibleText(row.text);
        // 只有该容器确实只包含一个 iconid 时才允许取整行文字，
        // 防止把第一项“不要动作”错误复制给整组单选项。
        if (row.querySelectorAll('input[name="iconid"]').length == 1 &&
            rowText.length <= 32) {
          label = rowText;
        }
      }

      label = label
          .replaceAll(RegExp(r'^\d+[.、\s-]*'), '')
          .replaceAll(RegExp(r'^(?:选择|选中)\s*'), '')
          .trim();
      if (label.isEmpty || label.length > 32) {
        label = '招呼方式 $id';
      }

      options.add(
        PokeOption(
          iconId: id,
          label: label,
          iconUrl: _absoluteUrl(
            image?.attributes['src'] ?? image?.attributes['data-src'],
            baseUrl,
          ),
        ),
      );
    }

    options.sort((a, b) => a.iconId.compareTo(b.iconId));
    return PokePageData(formhash: formhash, options: options);
  }
}
