import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';
import 'smiley_catalog.dart';

class UserCenterParser {
  const UserCenterParser();

  BasicProfileForm parseBasicProfile(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));

    String valueOf(String name) {
      final input = document.querySelector(
        'input[name="$name"], textarea[name="$name"]',
      );
      if (input != null) {
        return (input.attributes['value'] ?? input.text).trim();
      }

      final select = document.querySelector('select[name="$name"]');
      if (select != null) {
        final selected = select.querySelector('option[selected]');
        if (selected != null) {
          return (selected.attributes['value'] ?? selected.text).trim();
        }

        final first = select.querySelector('option');
        if (first != null) {
          return (first.attributes['value'] ?? first.text).trim();
        }
      }

      final checked = document.querySelector(
        'input[name="$name"][checked]',
      );
      return checked?.attributes['value']?.trim() ?? '';
    }

    int intValue(String name, [int fallback = 0]) {
      return int.tryParse(valueOf(name)) ?? fallback;
    }

    return BasicProfileForm(
      realname: valueOf('realname'),
      privacyRealname: intValue('privacy[realname]', 3),
      gender: intValue('gender'),
      privacyGender: intValue('privacy[gender]'),
      birthyear: intValue('birthyear'),
      birthmonth: intValue('birthmonth'),
      birthday: intValue('birthday'),
      privacyBirthday: intValue('privacy[birthday]'),
      resideProvince: valueOf('resideprovince'),
      privacyResideCity: intValue('privacy[residecity]'),
      occupation: valueOf('occupation'),
      privacyOccupation: intValue('privacy[occupation]'),
    );
  }

  CreditSummary parseCreditSummary(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final text = _clean(document.body?.text ?? document.documentElement?.text ?? '');

    int? numberAfter(String label) {
      // 冒号可选：真实页面里标签与数值间可能没有冒号（如“<em>信誉</em>100”）。
      final match = RegExp(
        '${RegExp.escape(label)}\\s*[:：]?\\s*(\\d+)',
      ).firstMatch(text);
      return int.tryParse(match?.group(1) ?? '');
    }

    final total = RegExp(r'积分\s*[:：]\s*(\d+)')
        .firstMatch(text);
    final formulaMatch = RegExp(
      r'(总积分\s*=.+?)(?=(?:金币|好评|信誉)\s*[:：]|$)',
      dotAll: true,
    ).firstMatch(text);

    return CreditSummary(
      total: int.tryParse(total?.group(1) ?? ''),
      gold: numberAfter('金币'),
      praise: numberAfter('好评'),
      reputation: numberAfter('信誉'),
      formula: _clean(formulaMatch?.group(1) ?? ''),
    );
  }

  RemoteTextPageData parseTextPage(
    String raw, {
    String fallbackTitle = '详情',
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    var title = _clean(document.querySelector('title')?.text ?? '');
    title = title.replaceAll(RegExp(r'\s*-\s*MT论坛.*$'), '').trim();
    if (title.isEmpty) {
      title = fallbackTitle;
    }

    for (final selector in const [
      'script',
      'style',
      'noscript',
      'header',
      'footer',
      'nav',
      '.comiis_head',
      '.comiis_footer',
      '.comiis_nv',
      '.comiis_menu',
      '.comiis_space_tx',
      '.comiis_space_info',
      '#comiis_head',
      '#comiis_footer',
    ]) {
      for (final node in document.querySelectorAll(selector)) {
        node.remove();
      }
    }

    html_dom.Element? root;
    final forms = document.querySelectorAll('form');
    if (forms.isNotEmpty) {
      root = forms.first;
    } else {
      root = document.querySelector(
        '.comiis_space_box, .comiis_p12, .comiis_wzpost, #ct, .wp',
      );
    }
    root ??= document.body;

    final lines = <String>[];
    final seen = <String>{};

    for (final element in root?.querySelectorAll(
          'legend, h1, h2, h3, h4, label, p, li, td, th',
        ) ??
        const <html_dom.Element>[]) {
      final line = _sanitizeVisibleText(element.text);

      if (_isJunkAccountLine(line) ||
          line.length > 320 ||
          line == title ||
          !seen.add(line)) {
        continue;
      }

      lines.add(line);
    }

    return RemoteTextPageData(
      title: title,
      lines: lines,
    );
  }

  /// 当前登录用户的“我的”资料。
  ///
  /// 直接复用真实用户主页 DOM 解析，避免“我的”页另写一套简化解析后
  /// 帖子/回复/好友长期显示 0。UserProfile 中 threads=帖子数、posts=回复数。
  UserProfile parseCurrentProfile(
    String raw, {
    required String uid,
    required String baseUrl,
  }) {
    final space = parseSpaceProfile(raw, uid: uid, baseUrl: baseUrl);
    return UserProfile(
      uid: uid,
      username: space.username,
      avatarUrl: space.avatarUrl,
      userGroup: space.userGroup,
      credits: space.credits,
      gold: space.gold,
      threads: space.posts,
      posts: space.replies,
      friends: space.friends,
      regDate: space.registerTime,
      lastVisit: space.lastVisit,
    );
  }

  SpaceUserProfile parseSpaceProfile(
    String raw, {
    required String uid,
    required String baseUrl,
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    var username = _sanitizeVisibleText(
      document.querySelector('.comiis_space_tx h2')?.text ??
          document.querySelector('.comiis_space_info h2')?.text ??
          '',
    );
    if (username.isEmpty) username = 'UID $uid';

    final avatar = document.querySelector(
      '.comiis_space_tx .user_img img, .user_img img, '
      'img[src*="avatar.php?uid=$uid"], img[src*="avatar"][src*="$uid"]',
    );
    final headerText = _sanitizeVisibleText(
      document.querySelector('.comiis_space_tx')?.text ?? '',
    );
    final pageText = _sanitizeVisibleText(document.body?.text ?? '');

    // 优先用 DOM 精确解析积分区。两种结构：
    //   未登录: <ul class="pf_l"><li><em>标签</em>值</li></ul>   (标签前, 值后)
    //   登录态: <div class="comiis_space_profilejf"><ul><li>
    //           <span class="f_0">值</span>标签</li></ul></div>  (值前, 标签后)
    final statMap = <String, int>{};
    for (final li in document.querySelectorAll(
      '#psts li, .pf_l li, .comiis_psts li, ul.pf_l > li, '
      '.comiis_space_profilejf li, .comiis_space_jf li',
    )) {
      final fullText = _sanitizeVisibleText(li.text);
      if (fullText.isEmpty) continue;

      // 结构A: <em>标签</em>值 —— 取 em 文本为标签，剩余为值。
      final em = li.querySelector('em');
      if (em != null) {
        final label = _sanitizeVisibleText(em.text);
        if (label.isNotEmpty) {
          var valueText = fullText;
          if (valueText.startsWith(label)) {
            valueText = valueText.substring(label.length);
          }
          valueText = _sanitizeVisibleText(valueText);
          final numMatch = RegExp(r'(\d+)').firstMatch(valueText);
          final value = int.tryParse(numMatch?.group(1) ?? '');
          if (value != null) {
            statMap[label] = value;
          }
          continue;
        }
      }

      // 结构B: <span class="f_0">值</span>标签 —— 值在前, 标签在后。
      final span = li.querySelector('.f_0, span');
      if (span != null) {
        final valueText = _sanitizeVisibleText(span.text);
        final numMatch = RegExp(r'(\d+)').firstMatch(valueText);
        if (numMatch != null) {
          final value = int.tryParse(numMatch.group(1) ?? '');
          if (value != null) {
            // 标签 = li全文 去掉 span里的数字部分。
            var label = fullText;
            final spanText = _sanitizeVisibleText(span.text);
            if (label.contains(spanText)) {
              label = label.replaceAll(spanText, '');
            }
            label = _sanitizeVisibleText(label);
            if (label.isNotEmpty) {
              statMap[label] = value;
            }
          }
        }
      }
    }

    int? stat(String label) {
      // 1. DOM 精确匹配优先。
      final domValue = statMap[label];
      if (domValue != null) return domValue;
      // 2. afterLabel（标签后的数字）回退。
      for (final text in <String>[headerText, pageText]) {
        final afterLabel = RegExp(
          RegExp.escape(label) + r'\s*[:：]?\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(text);
        final labeledValue = int.tryParse(afterLabel?.group(1) ?? '');
        if (labeledValue != null) return labeledValue;
      }
      // 3. beforeLabel（数字在前，如"110 信誉"）—— 登录态积分区常见格式。
      //    限定在 headerText 和 profilejf 区域文本，避免误匹配 UID。
      for (final text in <String>[headerText, pageText]) {
        final beforeLabel = RegExp(
          r'(\d+)\s*' + RegExp.escape(label),
          caseSensitive: false,
        ).firstMatch(text);
        final leadingValue = int.tryParse(beforeLabel?.group(1) ?? '');
        if (leadingValue != null) return leadingValue;
      }
      return null;
    }

    String? fieldValue(List<String> labels) {
      for (final element in document.querySelectorAll(
        '.comiis_space_box li, .comiis_space_box tr, '
        '.comiis_space_list li, .comiis_space_info li, '
        '.comiis_space_info tr, .b_t, li, tr',
      )) {
        final text = _sanitizeVisibleText(element.text);
        if (text.isEmpty || text.length > 240) continue;
        for (final label in labels) {
          final match = RegExp(
            '^${RegExp.escape(label)}\\s*[:：]?\\s*(.+)\$',
            caseSensitive: false,
          ).firstMatch(text);
          final value = _sanitizeVisibleText(match?.group(1) ?? '');
          if (value.isNotEmpty && value != label) return value;
        }
      }
      return null;
    }

    String? action(String selector) => _absoluteUrl(
          document.querySelector(selector)?.attributes['href'],
          baseUrl,
        );

    String? backgroundUrl;
    for (final element in document.querySelectorAll(
      '.comiis_space_info[style], .comiis_space_top[style], '
      '.comiis_space_bg[style], [class*="space"][style*="background"]',
    )) {
      final style = element.attributes['style'] ?? '';
      final match = RegExp(
        r'''url\(['"]?([^'"\)]+)''',
        caseSensitive: false,
      ).firstMatch(style);
      backgroundUrl = _absoluteUrl(match?.group(1), baseUrl);
      if (backgroundUrl != null) break;
    }
    backgroundUrl ??= _absoluteUrl(
      document.querySelector(
        '.comiis_space_bg img, .comiis_space_banner img, '
        'img[class*="space_bg"], img[class*="cover"]',
      )?.attributes['src'],
      baseUrl,
    );

    final medalUrls = <String>[];
    for (final container in document.querySelectorAll(
      '[class*="medal"], [class*="xunzhang"], [class*="honor"]',
    )) {
      for (final image in container.querySelectorAll('img')) {
        final url = _absoluteUrl(
          image.attributes['src'] ?? image.attributes['data-src'],
          baseUrl,
        );
        if (url != null && !medalUrls.contains(url)) medalUrls.add(url);
      }
    }
    if (medalUrls.isEmpty) {
      for (final row in document.querySelectorAll('li, tr, .b_t')) {
        if (!_sanitizeVisibleText(row.text).contains('勋章')) continue;
        for (final image in row.querySelectorAll('img')) {
          final url = _absoluteUrl(
            image.attributes['src'] ?? image.attributes['data-src'],
            baseUrl,
          );
          if (url != null && !medalUrls.contains(url)) medalUrls.add(url);
        }
      }
    }

    final followAddUrl = action(
      'a[href*="ac=follow"][href*="op=add"][href*="fuid=$uid"]',
    );
    final unfollowAction = document.querySelector(
      'a[href*="ac=follow"][href*="op=del"][href*="fuid=$uid"]',
    );
    final followStatusText = _sanitizeVisibleText(
      document.querySelector(
            'a[href*="ac=follow"][href*="fuid=$uid"]',
          )?.text ??
          '',
    );
    final isFollowing = unfollowAction != null ||
        followStatusText.contains('取消关注') ||
        followStatusText.contains('已关注');

    return SpaceUserProfile(
      uid: uid,
      username: username,
      avatarUrl: _absoluteUrl(
        avatar?.attributes['src'] ?? avatar?.attributes['data-src'],
        baseUrl,
      ),
      backgroundUrl: backgroundUrl,
      popularity: stat('人气'),
      following: stat('关注'),
      followers: stat('粉丝'),
      posts: stat('帖子'),
      replies: stat('回复'),
      friends: stat('好友'),
      credits: stat('积分'),
      goodReview: stat('好评'),
      gold: stat('金币'),
      reputation: stat('信誉'),
      level: _nullableClean(document.querySelector('.kmlevs')?.text),
      userGroup: _nullableClean(document.querySelector('.kmlev')?.text),
      gender: fieldValue(const ['性别']),
      signature: fieldValue(const ['个人签名', '签名']),
      customTitle: fieldValue(const ['自定义衔', '自定义头衔']),
      occupation: fieldValue(const ['职业']),
      residence: fieldValue(const ['居住地']),
      birthday: fieldValue(const ['生日']),
      onlineTime: fieldValue(const ['在线时间']),
      registerTime: fieldValue(const ['注册时间']),
      lastVisit: fieldValue(const ['最后访问']),
      medalUrls: medalUrls,
      isFollowing: isFollowing,
      followUrl: followAddUrl,
      friendUrl: action(
        'a[href*="ac=friend"][href*="op=add"][href*="uid=$uid"]',
      ),
      pokeUrl: action(
        'a[href*="ac=poke"][href*="op=send"][href*="uid=$uid"]',
      ),
      messageUrl: action(
        'a[href*="do=pm"][href*="touid=$uid"]',
      ),
      reportUrl: action(
        'a[href*="misc.php"][href*="mod=report"]',
      ),
    );
  }

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

  SignatureProfileForm parseSignatureProfile(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));

    String valueOf(String name) {
      final field = document.querySelector(
        'textarea[name="$name"], input[name="$name"]',
      );
      if (field == null) {
        return '';
      }
      return (field.attributes['value'] ?? field.text).trim();
    }

    int privacyValue() {
      final select = document.querySelector(
        'select[name="privacy[bio]"]',
      );
      final selected = select?.querySelector('option[selected]');
      if (selected != null) {
        return int.tryParse(
              selected.attributes['value'] ?? '',
            ) ??
            0;
      }

      final checked = document.querySelector(
        'input[name="privacy[bio]"][checked]',
      );
      return int.tryParse(
            checked?.attributes['value'] ?? '',
          ) ??
          0;
    }

    return SignatureProfileForm(
      bio: valueOf('bio'),
      signature: valueOf('sightml'),
      privacyBio: privacyValue(),
    );
  }

  PasswordSecurityData parsePasswordSecurity(String raw) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    String valueOf(String name) {
      final input = document.querySelector(
        'input[name="$name"], textarea[name="$name"]',
      );
      if (input != null) {
        return (input.attributes['value'] ?? input.text).trim();
      }

      final select = document.querySelector('select[name="$name"]');
      final selected = select?.querySelector('option[selected]');
      return (selected?.attributes['value'] ?? '').trim();
    }

    final fromField = valueOf('formhash');
    final formhash = fromField.isNotEmpty
        ? fromField
        : RegExp(
              r'''formhash\s*[:=]\s*['"]([a-zA-Z0-9]+)['"]''',
              caseSensitive: false,
            ).firstMatch(source)?.group(1) ??
            '';

    final questions = <SecurityQuestionOption>[];
    final select = document.querySelector('select[name="questionidnew"]');

    for (final option in select?.querySelectorAll('option') ??
        const <html_dom.Element>[]) {
      final id = int.tryParse(option.attributes['value'] ?? '');
      final label = _sanitizeVisibleText(option.text);
      if (id == null || label.isEmpty) {
        continue;
      }
      questions.add(SecurityQuestionOption(id: id, label: label));
    }

    return PasswordSecurityData(
      formhash: formhash,
      email: valueOf('emailnew'),
      mobileCountryCode: valueOf('secmobiccnew'),
      mobile: valueOf('secmobilenew'),
      questionId: int.tryParse(valueOf('questionidnew')) ?? 0,
      questions: questions,
    );
  }

  ContactProfileForm parseContactProfile(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));

    String valueOf(String name) {
      final checked = document.querySelector(
        'input[name="$name"][checked]',
      );
      if (checked != null) {
        return checked.attributes['value']?.trim() ?? '';
      }

      final input = document.querySelector(
        'input[name="$name"], textarea[name="$name"]',
      );
      if (input != null) {
        return (input.attributes['value'] ?? input.text).trim();
      }

      final select = document.querySelector('select[name="$name"]');
      final selected = select?.querySelector('option[selected]');
      return (selected?.attributes['value'] ?? '').trim();
    }

    int privacy(String name) => int.tryParse(valueOf(name)) ?? 0;

    return ContactProfileForm(
      qq: valueOf('qq'),
      privacyQq: privacy('privacy[qq]'),
      mobile: valueOf('mobile'),
      privacyMobile: privacy('privacy[mobile]'),
    );
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

  InviteStatusData parseInviteStatus(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final text = _sanitizeVisibleText(document.body?.text ?? '');
    final denied = text.contains('没有权限邀请好友') ||
        text.contains('暂无权限邀请好友') ||
        text.contains('无权邀请好友');

    if (denied) {
      return const InviteStatusData(
        canInvite: false,
        message: '当前账号暂无邀请好友权限',
      );
    }

    final hasInviteUi = document.querySelector(
          'form[action*="ac=invite"], input[name*="invite"], '
          'a[href*="ac=invite"]',
        ) !=
        null;

    return InviteStatusData(
      canInvite: hasInviteUi,
      message: hasInviteUi ? '当前账号可访问邀请好友页面' : '未检测到邀请码功能',
    );
  }

  SmsBindingData parseSmsBinding(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));

    String? phone;

    for (final name in const [
      'comiis_tel',
      'secmobilenew',
      'mobile',
      'phone',
    ]) {
      final value = document
          .querySelector('input[name="$name"]')
          ?.attributes['value']
          ?.trim();

      if (value != null &&
          RegExp(r'^\d{7,15}$').hasMatch(value)) {
        phone = value;
        break;
      }
    }

    if (phone == null) {
      final text = _sanitizeVisibleText(
        document.body?.text ?? '',
      );
      phone = RegExp(r'\b(1\d{10})\b')
          .firstMatch(text)
          ?.group(1);
    }

    return SmsBindingData(
      phone: phone,
      canUnbind: phone != null && phone.isNotEmpty,
    );
  }

  PromotionData parsePromotion(
    String raw, {
    required String baseUrl,
  }) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    final username = _sanitizeVisibleText(
      document.querySelector('.comiis_tg_kmtit')?.text ?? '',
    );

    final uidText = _sanitizeVisibleText(
      document.querySelector('.comiis_tg_kmtxt')?.text ?? '',
    );
    final uid = RegExp(r'UID\s*[:：]\s*(\d+)')
            .firstMatch(uidText)
            ?.group(1) ??
        RegExp(r'fromuid=(\d+)').firstMatch(source)?.group(1) ??
        '';

    final link = RegExp(
          r'''text\s*:\s*["']([^"']*fromuid=\d+[^"']*)["']''',
          caseSensitive: false,
        ).firstMatch(source)?.group(1) ??
        (uid.isEmpty ? baseUrl : '$baseUrl/?fromuid=$uid');

    final reward = _sanitizeVisibleText(
      document.querySelector('.comiis_tg_box_tip')?.text ?? '',
    );

    return PromotionData(
      username: username,
      uid: uid,
      avatarUrl: _absoluteUrl(
        document
            .querySelector('.comiis_tg_tximg img')
            ?.attributes['src'],
        baseUrl,
      ),
      link: link,
      reward: reward,
    );
  }

  List<CreditRecord> parseCreditRecords(String raw) {
    final source = _unwrapCdata(raw);
    final document = html_parser.parse(source);

    for (final selector in const [
      'script',
      'style',
      'nav',
      'header',
      'footer',
      '.comiis_head',
      '.comiis_footer',
      '.comiis_space_tx',
    ]) {
      for (final node in document.querySelectorAll(selector)) {
        node.remove();
      }
    }

    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String value) {
      final line = _sanitizeVisibleText(value);
      if (line.isEmpty ||
          _isCreditJunk(line) ||
          !seen.add(line)) {
        return;
      }
      candidates.add(line);
    }

    for (final row in document.querySelectorAll('tr')) {
      addCandidate(row.text);
    }

    if (candidates.isEmpty) {
      for (final item in document.querySelectorAll('li')) {
        addCandidate(item.text);
      }
    }

    if (candidates.isEmpty) {
      for (final item in document.querySelectorAll('p, .b_t, .comiis_xif')) {
        addCandidate(item.text);
      }
    }

    final parsed = <CreditRecord>[];

    for (final line in candidates) {
      final timeMatch = RegExp(
        r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)',
      ).firstMatch(line);

      final deltaMatch = RegExp(
        r'([+-]\d+)',
      ).firstMatch(line);

      var type = '';
      final delta = deltaMatch?.group(1) ?? '';
      final time = timeMatch?.group(1) ?? '';
      var reason = line;

      if (deltaMatch != null) {
        type = line
            .substring(0, deltaMatch.start)
            .replaceAll(RegExp(r'[:：\s]+$'), '')
            .trim();
      } else if (timeMatch != null) {
        type = line
            .substring(0, timeMatch.start)
            .replaceAll(RegExp(r'[:：\s]+$'), '')
            .trim();
      }

      if (timeMatch != null) {
        reason = line.substring(timeMatch.end).trim();
      } else if (deltaMatch != null) {
        reason = line.substring(deltaMatch.end).trim();
      }

      if (type.length > 24) {
        type = '';
      }

      parsed.add(
        CreditRecord(
          type: type,
          delta: delta,
          time: time,
          reason: reason,
          raw: line,
        ),
      );
    }

    final bestByKey = <String, CreditRecord>{};
    final order = <String>[];

    int score(CreditRecord item) {
      var value = 0;
      if (item.delta.isNotEmpty) value += 4;
      if (item.type.isNotEmpty) value += 2;
      if (item.time.isNotEmpty) value += 1;
      return value;
    }

    for (final item in parsed) {
      final key = item.time.isNotEmpty && item.reason.isNotEmpty
          ? '${item.time}\u0000${item.reason}'
          : item.raw;

      final previous = bestByKey[key];
      if (previous == null) {
        bestByKey[key] = item;
        order.add(key);
        continue;
      }
      if (score(item) > score(previous)) {
        bestByKey[key] = item;
      }
    }

    return [
      for (final key in order)
        if (bestByKey[key] != null) bestByKey[key]!,
    ];
  }

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
          final rawUrl = node.attributes['zoomfile'] ??
              node.attributes['file'] ??
              node.attributes['data-original'] ??
              node.attributes['data-src'] ??
              node.attributes['src'];
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

  List<NoticeItem> parseNotices(
    String raw, {
    String baseUrl = 'https://bbs.binmt.cc',
  }) {
    return parseNoticePage(raw, baseUrl: baseUrl).items;
  }

  NoticePageData parseNoticePage(
    String raw, {
    String baseUrl = 'https://bbs.binmt.cc',
    int currentPage = 1,
  }) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final result = <NoticeItem>[];

    var noticeNodes = document.querySelectorAll('.comiis_notice_list li');
    if (noticeNodes.isEmpty) {
      // 某些主题模板不会保留 comiis_notice_list 外层，仍以 ntc_body
      // 作为真正的通知项标记，避免误解析页面上的普通导航 li。
      noticeNodes = document
          .querySelectorAll('li')
          .where((node) => node.querySelector('.ntc_body') != null)
          .toList();
    }

    for (final item in noticeNodes) {
      final body = item.querySelector('.ntc_body');
      if (body == null) continue;

      final avatarLink = item.querySelector('a.notice_img');
      final avatar = avatarLink?.querySelector('img');
      final systemIcon = item.querySelector('.notice_imgs');
      final bodyLinks = body.querySelectorAll('a[href]');
      final firstLink = bodyLinks.isEmpty ? null : bodyLinks.first;

      final firstHref =
          (firstLink?.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final firstIsUserLink = RegExp(
        r'(?:[?&]uid=\d+|space-uid-\d+)',
        caseSensitive: false,
      ).hasMatch(firstHref);
      var username = firstIsUserLink
          ? _sanitizeUsername(firstLink?.text ?? '')
          : '';
      final authorHref = avatarLink?.attributes['href'] ??
          (firstIsUserLink ? firstHref : '');
      final avatarSrc = avatar?.attributes['src'] ?? '';

      String uidFrom(String value) {
        final normalized = value.replaceAll('&amp;', '&');
        return RegExp(r'(?:^|[?&])uid=(\d+)')
                .firstMatch(normalized)
                ?.group(1) ??
            RegExp(r'space-uid-(\d+)', caseSensitive: false)
                .firstMatch(normalized)
                ?.group(1) ??
            '';
      }

      final uidFromAuthor = uidFrom(authorHref);
      final authorUid = uidFromAuthor.isNotEmpty
          ? uidFromAuthor
          : uidFrom(avatarSrc);

      html_dom.Element? targetLink;
      html_dom.Element? titleTarget;
      html_dom.Element? pidTarget;
      html_dom.Element? fallbackTarget;
      final noticeTargets = <html_dom.Element>[];

      for (final link in bodyLinks) {
        final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (!_looksLikeNoticeTarget(href)) continue;

        noticeTargets.add(link);
        fallbackTarget ??= link;

        if (pidTarget == null &&
            RegExp(
              r'(?:^|[?&])pid=\d+',
              caseSensitive: false,
            ).hasMatch(href)) {
          pidTarget = link;
        }

        final label = _sanitizeVisibleText(link.text);
        if (titleTarget == null &&
            label.isNotEmpty &&
            label != '查看' &&
            label != '详情') {
          titleTarget = link;
        }
      }

      // “回复了我”类通知经常同时包含帖子标题链接和 goto=findpost 链接。
      // 优先保留带 pid 的链接用于精确定位，但标题仍从可读链接取，避免 UI 退化。
      targetLink = pidTarget ?? titleTarget ?? fallbackTarget;

      final targetHref =
          (targetLink?.attributes['href'] ?? '').replaceAll('&amp;', '&');
      var targetUrl = _absoluteUrl(targetHref, baseUrl);
      final targetTitleSource = titleTarget ?? targetLink;
      final targetTitleRaw =
          _sanitizeVisibleText(targetTitleSource?.text ?? '');
      final targetTitle = targetTitleRaw.isEmpty ||
              targetTitleRaw == '查看' ||
              targetTitleRaw == '详情'
          ? null
          : targetTitleRaw;

      String? tidFrom(String href) {
        final normalized = href.replaceAll('&amp;', '&');
        return RegExp(r'(?:^|[?&])(?:ptid|tid)=(\d+)')
                .firstMatch(normalized)
                ?.group(1) ??
            RegExp(r'thread-(\d+)-', caseSensitive: false)
                .firstMatch(normalized)
                ?.group(1);
      }

      String? pidFrom(String href) {
        final normalized = href.replaceAll('&amp;', '&');
        return RegExp(r'(?:^|[?&])pid=(\d+)')
            .firstMatch(normalized)
            ?.group(1);
      }

      var tid = tidFrom(targetHref);
      var pid = pidFrom(targetHref);

      // 某些模板把 tid 放在标题链接、pid 放在“查看”链接里。
      // 两者分别从全部候选链接补齐，避免选中其中一个后丢失另一个参数。
      if (tid == null || pid == null) {
        for (final link in noticeTargets) {
          final href =
              (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
          tid ??= tidFrom(href);
          pid ??= pidFrom(href);
          if (tid != null && pid != null) break;
        }
      }

      // 少数通知模板把 findpost 参数藏在 onclick/data-* 或未被 DOM
      // 识别为链接的片段中，再从整条通知源码兜底提取。
      final itemSource = item.innerHtml.replaceAll('&amp;', '&');
      tid ??= tidFrom(itemSource);
      pid ??= pidFrom(itemSource);
      if (tid != null && pid != null) {
        // 标题链接往往只有 tid。统一构造 findpost 地址，确保预览请求和点击
        // 跳转都由论坛定位到 pid 所在页。
        targetUrl = _absoluteUrl(
          'forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid&mobile=2',
          baseUrl,
        );
      }

      final content = _sanitizeVisibleText(body.text);
      var actionText = content;
      if (username.isNotEmpty) {
        actionText = actionText.replaceFirst(username, '').trim();
      }
      if (targetTitle != null && targetTitle.isNotEmpty) {
        actionText = actionText.replaceFirst(targetTitle, '').trim();
      }
      actionText = actionText
          .replaceFirst(RegExp(r'^[：:]\s*'), '')
          .replaceAll(
            RegExp(
              r'(?:\s*[|丨]?\s*(?:查看|详情|回打招呼|忽略|屏蔽)\s*[|丨]?)+\s*$',
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\s|丨·•]+|[\s|丨·•]+$'), '')
          .trim();
      if (actionText.isEmpty) actionText = content;

      final timeNode = item.querySelector('h2.f_d, .f_d');
      final time = _sanitizeVisibleText(timeNode?.text ?? '')
          .replaceAll('屏蔽', '')
          .replaceAll('忽略', '')
          .replaceAll(RegExp(r'^[\s|丨·•]+|[\s|丨·•]+$'), '')
          .trim();
      var ignoreLink = item.querySelector(
        'h2 a[href*="op=ignore"], a[href*="ac=common"][href*="op=ignore"]',
      );
      if (ignoreLink == null) {
        for (final link in item.querySelectorAll('a[href]')) {
          final label = _sanitizeVisibleText(
            '${link.text} ${link.attributes['title'] ?? ''}',
          );
          if (label.contains('忽略') || label.contains('屏蔽')) {
            ignoreLink = link;
            break;
          }
        }
      }
      final ignoreHref =
          (ignoreLink?.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final ignoreUrl = _absoluteUrl(ignoreHref, baseUrl);
      final ignoreUri = Uri.tryParse(ignoreHref);
      final type = ignoreUri?.queryParameters['type'] ?? '';
      final idAttr = ignoreLink?.attributes['id'] ?? '';
      final noticeId = RegExp(r'(?:^|_)note_(\d+)$', caseSensitive: false)
              .firstMatch(idAttr)
              ?.group(1) ??
          RegExp(r'(\d+)$').firstMatch(idAttr)?.group(1) ??
          '';

      final isSystem = systemIcon != null ||
          type == 'system' ||
          (authorUid.isEmpty && avatarLink == null);
      if (username.isEmpty && authorUid.isNotEmpty && !isSystem) {
        username = 'UID $authorUid';
      }

      result.add(
        NoticeItem(
          id: noticeId,
          type: type,
          authorUid: authorUid,
          username: username,
          avatarUrl: _absoluteUrl(avatarSrc, baseUrl),
          content: content,
          actionText: actionText,
          time: time,
          targetTitle: targetTitle,
          targetUrl: targetUrl,
          tid: tid,
          pid: pid,
          ignoreUrl: ignoreUrl,
          isSystem: isSystem,
          // 通知 HTML 没有可靠的单项已读标记，新提醒由客户端对比通知 ID。
          isUnread: false,
        ),
      );
    }

    var hasMore = false;
    var totalPages = currentPage < 1 ? 1 : currentPage;

    // Comiis 通知页的移动模板主要用 #dumppage <select>
    // 表示分页，不一定输出 .comiis_page 的下一页链接。
    // 旧解析只查链接，因此第 1 页会被误判为最后一页。
    final pageOptions = document.querySelectorAll('#dumppage option');
    if (pageOptions.isNotEmpty) {
      var totalPage = pageOptions.length;
      for (final option in pageOptions) {
        final value = (option.attributes['value'] ?? '').replaceAll('&amp;', '&');
        final valueUri = Uri.tryParse(value);
        final queryPage =
            int.tryParse(valueUri?.queryParameters['page'] ?? '');
        int? textPage;
        for (final match in RegExp(r'\d+').allMatches(option.text)) {
          final candidate = int.tryParse(match.group(0) ?? '');
          if (candidate != null && candidate > (textPage ?? 0)) {
            textPage = candidate;
          }
        }
        final parsedPage = queryPage ?? textPage;
        if (parsedPage != null && parsedPage > totalPage) {
          totalPage = parsedPage;
        }
      }
      totalPages = totalPage > totalPages ? totalPage : totalPages;
      hasMore = currentPage < totalPage;
    }

    for (final link in document.querySelectorAll(
      '.comiis_page a[href*="page="], .pg a[href*="page="], '
      'a.nxt[href], a[rel="next"][href]',
    )) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final uri = Uri.tryParse(href);
      final page = int.tryParse(uri?.queryParameters['page'] ?? '') ??
          int.tryParse(
            RegExp(r'(?:[?&]|&amp;)page=(\d+)')
                    .firstMatch(href)
                    ?.group(1) ??
                '',
          );
      if (page != null && page > totalPages) totalPages = page;
      if ((page != null && page > currentPage) ||
          link.classes.contains('nxt') ||
          link.attributes['rel'] == 'next') {
        hasMore = true;
        if (totalPages <= currentPage) totalPages = currentPage + 1;
        break;
      }
    }

    return NoticePageData(
      items: result,
      hasMore: hasMore,
      totalPages: totalPages,
    );
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

  RenameStatusData parseRenameStatus(String raw) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final text = _sanitizeVisibleText(
      document.body?.text ?? document.documentElement?.text ?? '',
    );

    final costMatch = RegExp(
      r'每次改名需要消耗\s*(\d+)\s*金币',
      caseSensitive: false,
    ).firstMatch(text);
    final cost = int.tryParse(costMatch?.group(1) ?? '');
    final insufficient = text.contains('金币 余额不足') ||
        text.contains('金币余额不足') ||
        RegExp(r'金币\s*余额不足').hasMatch(text);

    final statusMatch = RegExp(
      r'每次改名需要消耗\s*\d+\s*金币[^。！？!]*余额不足[！!。]?',
    ).firstMatch(text);

    final renameForm = document.querySelector(
      'form[action*="nimba_rename"], form[id*="rename"], form[name*="rename"]',
    );

    var message = _sanitizeVisibleText(statusMatch?.group(0) ?? '');
    if (message.isEmpty && insufficient) {
      message = cost == null
          ? '当前金币余额不足，暂时无法改名。'
          : '每次改名需要消耗 $cost 金币，当前金币余额不足。';
    }
    if (message.isEmpty && renameForm != null) {
      message = '当前账号已满足改名页面条件。';
    }

    return RenameStatusData(
      costGold: cost,
      insufficientGold: insufficient,
      hasRenameForm: renameForm != null,
      message: message,
    );
  }

  bool _looksLikeNoticeTarget(String href) {
    if (href.isEmpty) return false;
    final value = href.toLowerCase();
    return value.contains('ptid=') ||
        value.contains('pid=') ||
        value.contains('tid=') ||
        value.contains('thread-') ||
        value.contains('ac=usergroup') ||
        value.contains('op=usergroup');
  }

  bool _isCreditJunk(String value) {
    final text = _sanitizeVisibleText(value);
    if (text.isEmpty) {
      return true;
    }

    // 移动版积分页会把分区标题拼成“/系统奖励”“丨系统奖励”等文本。
    // 这些只是导航/分隔标题，不是实际积分记录。先去掉首尾分隔符后再判断，
    // 避免它们落进记录列表。
    final normalized = text
        .replaceAll(RegExp(r'^[\/／|丨·•>›»—–\-\s]+'), '')
        .replaceAll(RegExp(r'[\/／|丨·•>›»—–\-\s]+$'), '')
        .trim();

    const exact = {
      '我的',
      '记录',
      '明细',
      '积分收益',
      '系统奖励',
      '积分记录',
      '积分明细',
      '积分规则',
    };

    return exact.contains(normalized);
  }

  html_dom.Element? _nearestContainer(html_dom.Element element) {
    html_dom.Element? current = element.parent;

    for (var i = 0; i < 6 && current != null; i++) {
      final tag = (current.localName ?? '').toLowerCase();
      if (tag == 'li' || tag == 'tr' || tag == 'tbody') {
        return current;
      }
      if (tag == 'div' && current.children.length <= 24) {
        return current;
      }
      current = current.parent;
    }

    return element.parent;
  }

  String _sanitizeUsername(String value) {
    var text = _sanitizeVisibleText(value);

    const actionWords = [
      '加好友',
      '关注',
      '打招呼',
      '发消息',
      '删除',
      '忽略',
      '通过',
    ];

    for (final word in actionWords) {
      if (text == word) {
        return '';
      }
      text = text.replaceAll(word, '').trim();
    }

    return text;
  }

  String _sanitizeVisibleText(String value) {
    return value
        .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD\u25A1]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _sanitizePmMessageText(String value) {
    return value
        .replaceAll(RegExp(r'[\uFFFD\u25A1]'), '')
        .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
        .trim();
  }

  bool _isJunkAccountLine(String value) {
    final line = _sanitizeVisibleText(value);
    if (line.isEmpty) {
      return true;
    }

    if (line == '数据加载中' ||
        line == '首页' ||
        line == '社区' ||
        line == '导读' ||
        line == '签到' ||
        line == '排行' ||
        line == '标签' ||
        line == '搜索' ||
        line == '访问推广' ||
        line == '基本资料' ||
        line == '联系方式') {
      return true;
    }

    if (RegExp(r'^.+Lv\.\d+$', caseSensitive: false).hasMatch(line) ||
        RegExp(r'^.+积分\s*[:：]\s*\d+$').hasMatch(line)) {
      return true;
    }

    return false;
  }

  String? _nullableClean(String? value) {
    if (value == null) {
      return null;
    }

    final cleaned = _sanitizeVisibleText(value);
    return cleaned.isEmpty ? null : cleaned;
  }

  String _unwrapCdata(String raw) {
    final match = RegExp(
      r'<!\[CDATA\[(.*?)\]\]>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(raw);

    return match?.group(1) ?? raw;
  }

  String _clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _absoluteUrl(String? raw, String baseUrl) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final value = raw.trim();
    if (value.startsWith('//')) {
      return 'https:$value';
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return value;
    }

    return Uri.parse(baseUrl).resolve(value).toString();
  }
}
