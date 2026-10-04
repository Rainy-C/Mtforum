part of '../user_center_parser.dart';

extension UserCenterParserMessageParserPart on UserCenterParser {
  PmConversationData parsePmConversation(
    String raw, {
    required String touid,
    required String baseUrl,
    String? myUid,
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    final form = document.querySelector('#pmform, form[id="pmform"]');
    final action = form?.attributes['action'] ?? '';

    final pmid = RegExp(r'(?:^|[?&])pmid=(\d+)')
            .firstMatch(action)
            ?.group(1) ??
        RegExp(r'(?:^|[?&])pmid=(\d+)')
            .firstMatch(source)
            ?.group(1) ??
        '';

    final formhash = form
            ?.querySelector('input[name="formhash"]')
            ?.attributes['value']
            ?.trim() ??
        '';

    final messages = _parsePmMessages(
      document,
      myUid: myUid,
      peerUid: touid,
      baseUrl: baseUrl,
    );

    final peerName = _sanitizeUsername(
      document.querySelector(
            '.comiis_pm_tit, .comiis_pm_user, .tit',
          )?.text ??
          '',
    );

    final peerAvatar = document.querySelector(
      '.comiis_friend_msg img.msg_avt, '
      '.comiis_friend_msg img',
    );

    bool? peerOnline;
    for (final status in document.querySelectorAll('h2.flex font.f14')) {
      final text = _clean(status.text);
      if (text.contains('(在线)') || text.contains('（在线）')) {
        peerOnline = true;
        break;
      }
      if (text.contains('(离线)') || text.contains('（离线）')) {
        peerOnline = false;
        break;
      }
    }

    final endTimestamp = int.tryParse(
          RegExp(
            r'comiis_msg_endtime[^0-9]{0,16}(\d{9,12})',
            caseSensitive: false,
          ).firstMatch(source)?.group(1) ??
              '',
        ) ??
        (DateTime.now().millisecondsSinceEpoch ~/ 1000);

    return PmConversationData(
      touid: touid,
      pmid: pmid,
      formhash: formhash,
      peerName: peerName,
      peerAvatarUrl: _absoluteUrl(
        peerAvatar?.attributes['src'],
        baseUrl,
      ),
      peerOnline: peerOnline,
      endTimestamp: endTimestamp,
      messages: messages,
    );
  }

  List<PmMessage> parsePmMessageFragment(
    String raw, {
    String? myUid,
    String? peerUid,
    String baseUrl = 'https://bbs.binmt.cc',
  }) {
    final document = html_parser.parse(_unwrapCdata(raw));
    return _parsePmMessages(
      document,
      myUid: myUid,
      peerUid: peerUid,
      baseUrl: baseUrl,
    );
  }

  List<PmConversationSummary> parsePmList(
    String raw, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final result = <PmConversationSummary>[];
    final seen = <String>{};

    String cleanName(
      String value, {
      String? lastTime,
      String? lastMessage,
    }) {
      var text = _sanitizeUsername(value);

      if (lastTime != null && lastTime.isNotEmpty) {
        text = text.replaceAll(lastTime, ' ');
      }
      if (lastMessage != null && lastMessage.isNotEmpty) {
        text = text.replaceAll(lastMessage, ' ');
      }

      text = text
          .replaceAll(
            RegExp(
              r'^(?:刚刚|半小时前|\d+\s*(?:分钟|小时|天)前)\s*',
            ),
            '',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      return text;
    }

    for (final link in document.querySelectorAll(
      'a[href*="do=pm"][href*="subop=view"][href*="touid="]',
    )) {
      final href = link.attributes['href'] ?? '';
      final touid = RegExp(r'(?:^|[?&])touid=(\d+)')
          .firstMatch(href)
          ?.group(1);

      if (touid == null || !seen.add(touid)) {
        continue;
      }

      final container = _nearestContainer(link);
      // MT 论坛真实私信列表用空的 span.kmnums 作为未读标记。
      // 不能读取其文本内容，因为未读时该 span 本身就是空字符串。
      final hasUnread = link.querySelector('span.kmnums') != null ||
          container?.querySelector('span.kmnums') != null;

      final rawLastMessage = container?.querySelector(
            '.msg_mes, .summary, .comiis_pm_txt, p',
          )?.text ??
          '';
      final lastMessage = _nullableClean(
        rawLastMessage.replaceAll(
          RegExp(
            r'\[img(?:=[^\]]+)?\][\s\S]*?\[/img\]',
            caseSensitive: false,
          ),
          '[图片]',
        ),
      );
      final lastTime = _nullableClean(
        container?.querySelector(
          '.msg_time, time, .f_d',
        )?.text,
      );

      var username = '';

      for (final selector in const [
        '.username',
        '.comiis_pm_user',
        '.tit a',
        '.tit',
        'h2',
        'h3',
        'h4',
        'strong',
      ]) {
        final candidate = cleanName(
          container?.querySelector(selector)?.text ?? '',
          lastTime: lastTime,
          lastMessage: lastMessage,
        );

        if (candidate.isNotEmpty &&
            candidate.length <= 48 &&
            !candidate.contains('UID:')) {
          username = candidate;
          break;
        }
      }

      if (username.isEmpty) {
        for (final profile in container?.querySelectorAll(
              'a[href*="mod=space"][href*="uid=$touid"]',
            ) ??
            const <html_dom.Element>[]) {
          final candidate = cleanName(
            profile.text,
            lastTime: lastTime,
            lastMessage: lastMessage,
          );
          if (candidate.isNotEmpty && candidate.length <= 48) {
            username = candidate;
            break;
          }
        }
      }

      if (username.isEmpty) {
        username = cleanName(
          link.text,
          lastTime: lastTime,
          lastMessage: lastMessage,
        );
      }

      if (username.isEmpty) {
        username = '用户 $touid';
      }

      final avatar = container?.querySelector(
        'img[src*="avatar"], img[src*="uc_server"], img',
      );

      result.add(
        PmConversationSummary(
          touid: touid,
          username: username,
          avatarUrl: _absoluteUrl(
            avatar?.attributes['src'],
            baseUrl,
          ),
          lastMessage: lastMessage,
          lastTime: lastTime,
          hasUnread: hasUnread,
        ),
      );
    }

    return result;
  }

  List<PmMessage> _parsePmMessages(
    html_dom.Document document, {
    String? myUid,
    String? peerUid,
    required String baseUrl,
  }) {
    final result = <PmMessage>[];
    final source = document.documentElement?.outerHtml ?? '';

    final resolvedMyUid = myUid ??
        RegExp(r'''discuz_uid\s*=\s*['"]?(\d+)''')
            .firstMatch(source)
            ?.group(1);

    void addMessage(
      html_dom.Element scope, {
      String date = '',
    }) {
      final messageNode = scope.classes.contains('msg_mes')
          ? scope
          : scope.querySelector('.msg_mes');
      if (messageNode == null) return;

      final bbImagePattern = RegExp(
        r'\[img(?:=[^\]]+)?\]\s*([^\[\]\r\n]+?)\s*\[/img\]',
        caseSensitive: false,
      );
      final imageUrls = <String>[];

      void addImage(String? rawUrl) {
        final value = rawUrl?.trim() ?? '';
        if (value.isEmpty ||
            value.startsWith('/storage/') ||
            value.startsWith('file:') ||
            value.startsWith('content:')) {
          return;
        }
        final url = _absoluteUrl(value, baseUrl);
        if (url != null && !imageUrls.contains(url)) imageUrls.add(url);
      }

      void appendText(String value, StringBuffer output) {
        var cursor = 0;
        for (final match in bbImagePattern.allMatches(value)) {
          if (match.start > cursor) {
            output.write(value.substring(cursor, match.start));
          }
          final rawUrl = match.group(1)?.trim() ?? '';
          final url = _absoluteUrl(rawUrl, baseUrl);
          final marker = url == null ? null : SmileyCatalog.markerForUrl(url);
          if (marker != null) {
            output.write(marker);
          } else if (url != null && SmileyCatalog.isForumSmileyUrl(url)) {
            output.write('[img]$url[/img]');
          } else {
            addImage(rawUrl);
          }
          cursor = match.end;
        }
        if (cursor < value.length) output.write(value.substring(cursor));
      }

      final orderedText = StringBuffer();
      void walkMessage(html_dom.Node node) {
        if (node is html_dom.Text) {
          appendText(node.text, orderedText);
          return;
        }
        if (node is! html_dom.Element) return;
        final tag = (node.localName ?? '').toLowerCase();
        if (tag == 'br') {
          orderedText.write('\n');
          return;
        }
        if (tag == 'img') {
          final rawUrl = _imageSourceOf(node);
          final url = _absoluteUrl(rawUrl, baseUrl);
          final marker = url == null ? null : SmileyCatalog.markerForUrl(url);
          if (marker != null) {
            orderedText.write(marker);
          } else if (url != null && SmileyCatalog.isForumSmileyUrl(url)) {
            orderedText.write('[img]$url[/img]');
          } else {
            addImage(rawUrl);
          }
          return;
        }
        for (final child in node.nodes) {
          walkMessage(child);
        }
      }
      for (final child in messageNode.nodes) {
        walkMessage(child);
      }

      final content = _sanitizePmMessageText(orderedText.toString());
      if (content.isEmpty && imageUrls.isEmpty) return;

      String? senderUid;
      for (final anchor in scope.querySelectorAll('a[href*="uid="]')) {
        final candidate = RegExp(r'(?:^|[?&])uid=(\d+)')
            .firstMatch(anchor.attributes['href'] ?? '')
            ?.group(1);
        if (candidate != null && candidate.isNotEmpty) {
          senderUid = candidate;
          break;
        }
      }
      senderUid ??= RegExp(r'(?:uid=|uid%3D)(\d+)')
          .firstMatch(scope.innerHtml)
          ?.group(1);

      final classText = <String>{
        ...scope.classes,
        ...?messageNode.parent?.classes,
      }.join(' ').toLowerCase();
      final bubble = messageNode.parent;

      final explicitMine = scope.classes.any(
            (c) => RegExp(
              r'(?:^|_)(?:my|mine|self|me)(?:_|$)',
              caseSensitive: false,
            ).hasMatch(c),
          ) ||
          scope.classes.contains('comiis_my_msg') ||
          bubble?.classes.contains('y') == true ||
          scope.querySelector(
                '.dialog_blue.y, .dialog_green.y, .dialog_primary.y, '
                '.comiis_my_msg, .comiis_self_msg, .comiis_msg_right',
              ) !=
              null ||
          classText.contains('msg_right');

      final explicitPeer = bubble?.classes.contains('z') == true ||
          (peerUid != null &&
              scope.querySelector('a[href*="uid=$peerUid"]') != null);

      var isMine = explicitMine;
      if (!isMine && resolvedMyUid != null && senderUid == resolvedMyUid) {
        isMine = true;
      }
      if (!isMine &&
          senderUid != null &&
          peerUid != null &&
          senderUid != peerUid &&
          !explicitPeer) {
        // 私信是两人会话：有明确发送者且不是对方 UID 时，就是当前账号。
        isMine = true;
      }
      if (senderUid == peerUid || explicitPeer) {
        isMine = false;
      }

      final time = _sanitizeVisibleText(
        scope.querySelector('.msg_time')?.text ??
            bubble?.querySelector('.msg_time')?.text ??
            '',
      );

      final key = '$senderUid|$time|$content|${imageUrls.join(',')}';
      if (result.any(
        (item) =>
            '${item.senderUid}|${item.time}|${item.content}|${item.imageUrls.join(',')}' ==
            key,
      )) {
        return;
      }

      result.add(
        PmMessage(
          pmid: RegExp(r'(?:^|[?&])pmid=(\d+)')
              .firstMatch(scope.innerHtml)
              ?.group(1),
          senderUid: senderUid,
          content: content,
          time: time,
          date: date,
          isMine: isMine,
          imageUrls: imageUrls,
        ),
      );
    }

    final list = document.querySelector('.comiis_pm_list');
    if (list != null) {
      var currentDate = '';
      for (final child in list.children) {
        if (child.classes.contains('comiis_msg_date')) {
          currentDate = _sanitizeVisibleText(
            child.querySelector('span')?.text ?? child.text,
          );
          continue;
        }
        if (child.querySelector('.msg_mes') != null ||
            child.classes.contains('msg_mes')) {
          addMessage(child, date: currentDate);
        }
      }
    } else {
      var currentDate = '';
      for (final node in document.querySelectorAll(
        '.comiis_msg_date, .msg_mes',
      )) {
        if (node.classes.contains('comiis_msg_date')) {
          currentDate = _sanitizeVisibleText(
            node.querySelector('span')?.text ?? node.text,
          );
          continue;
        }
        final messageNode = node;
        html_dom.Element scope = messageNode;
        html_dom.Element? fallbackWithTime;
        html_dom.Node? parentNode = messageNode.parentNode;

        // 先一直向上找真实消息 wrapper。旧逻辑遇到 msg_time 就提前停止，
        // 结果只拿到气泡内部 div，丢掉了头像 UID / 左右方向 class。
        for (var depth = 0;
            depth < 8 && parentNode is html_dom.Element;
            depth++) {
          final parent = parentNode as html_dom.Element;
          scope = parent;
          if (parent.querySelector('.msg_time') != null) {
            fallbackWithTime ??= parent;
          }
          if (parent.classes.contains('comiis_friend_msg') ||
              parent.classes.contains('comiis_my_msg') ||
              parent.classes.contains('comiis_self_msg') ||
              parent.classes.contains('comiis_msg_right')) {
            break;
          }
          if (parent.localName == 'body') {
            scope = fallbackWithTime ?? messageNode;
            break;
          }
          parentNode = parent.parentNode;
        }
        addMessage(scope, date: currentDate);
      }
    }

    return result;
  }

  /// 从不会清空提醒状态的普通论坛页面中提取 Discuz 全局未读标记。
  ///
  /// 标准 Discuz 模板会通过 `#pm_ntc` 的 `new` class 表示新私信，
  /// 通过 `#myprompt` 展示 `newprompt`。部分 Comiis 模板会直接输出数字，
  /// 也有模板只输出“new/unread”状态；后者保留为 count=null。
  MessageUnreadSummary parseGlobalMessageUnread(String raw) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    int? parseNumber(String value) {
      final text = _sanitizeVisibleText(value);
      final direct = RegExp(r'^\s*(\d{1,4})\s*$').firstMatch(text);
      if (direct != null) return int.tryParse(direct.group(1)!);

      final bracket = RegExp(r'[（(\[]\s*(\d{1,4})\s*[）)\]]')
          .firstMatch(text);
      if (bracket != null) return int.tryParse(bracket.group(1)!);

      final labelled = RegExp(
        r'(?:未读|新消息|新提醒|提醒|消息)\D{0,5}(\d{1,4})',
        caseSensitive: false,
      ).firstMatch(text);
      return int.tryParse(labelled?.group(1) ?? '');
    }

    int? sourceNumber(List<String> names) {
      for (final name in names) {
        final escaped = RegExp.escape(name);
        final patterns = <RegExp>[
          RegExp(
            "(?:\\b$escaped\\b|[\"']$escaped[\"'])\\s*[:=]\\s*[\"']?(\\d{1,4})",
            caseSensitive: false,
          ),
        ];
        for (final pattern in patterns) {
          final match = pattern.firstMatch(source);
          final value = int.tryParse(match?.group(1) ?? '');
          if (value != null) return value;
        }
      }
      return null;
    }

    UnreadBadgeInfo readSignal({
      required List<String> selectors,
      required List<String> sourceKeys,
    }) {
      int? count = sourceNumber(sourceKeys);
      var hasUnread = (count ?? 0) > 0;

      for (final selector in selectors) {
        final nodes = document.querySelectorAll(selector);
        for (final node in nodes) {
          count ??= parseNumber(node.text);
          if ((count ?? 0) > 0) hasUnread = true;

          for (final child in node.querySelectorAll(
            '.badge, .num, .number, .count, em, strong, span',
          )) {
            final childCount = parseNumber(child.text);
            if (childCount != null) {
              count ??= childCount;
              if (childCount > 0) hasUnread = true;
            }
          }

          final classes = <String>{
            ...node.classes,
            for (final child in node.querySelectorAll('*')) ...child.classes,
          }.join(' ').toLowerCase();
          if (RegExp(r'(^|\s|_|-)(?:new|unread|newpm|newprompt|hasnew)(\s|_|-|$)')
              .hasMatch(classes)) {
            hasUnread = true;
          }
        }
      }

      if (count != null && count <= 0 && !hasUnread) {
        return const UnreadBadgeInfo.none();
      }
      return UnreadBadgeInfo(count: count, hasUnread: hasUnread);
    }

    return MessageUnreadSummary(
      privateMessages: readSignal(
        selectors: const [
          '#pm_ntc',
          'a[href*="do=pm"]',
          '[class*="pm"][class*="new"]',
        ],
        sourceKeys: const ['newpm', 'new_pm', 'pmcount', 'pm_count'],
      ),
      notices: readSignal(
        selectors: const [
          '#myprompt',
          'a[href*="do=notice"]',
          '[class*="notice"][class*="new"]',
          '[class*="prompt"][class*="new"]',
        ],
        sourceKeys: const [
          'newprompt',
          'new_prompt',
          'noticecount',
          'notice_count',
          'promptcount',
        ],
      ),
    );
  }

  String _sanitizePmMessageText(String value) {
    return value
        .replaceAll(RegExp(r'[\uFFFD\u25A1]'), '')
        .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
        .trim();
  }
}
