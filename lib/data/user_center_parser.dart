import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

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
      final match = RegExp(
        '${RegExp.escape(label)}\\s*[:：]\\s*(\\d+)',
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

    int? stat(String label) {
      for (final text in <String>[headerText, pageText]) {
        // 资料明细多数是“积分 4165 / 帖子 94”，优先读标签后的数字，
        // 避免整页文本压平后把前一个统计值误当成当前字段。
        final afterLabel = RegExp(
          RegExp.escape(label) + r'\s*[:：]?\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(text);
        final labeledValue = int.tryParse(afterLabel?.group(1) ?? '');
        if (labeledValue != null) return labeledValue;

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
      final nameLink = item.querySelector('.tit a');
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
        container?.querySelector('.tit a, h4 a, h3 a')?.text ??
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
    if (_clean(html_parser.parseFragment(source).text ?? '')
        .contains('没有新的好友请求')) {
      return const [];
    }

    final document = html_parser.parse(source);
    final result = <FriendRequestItem>[];
    final seen = <String>{};

    for (final add in document.querySelectorAll(
      'a[href*="ac=friend"][href*="op=add"][href*="uid="]',
    )) {
      final href = add.attributes['href'] ?? '';
      final uid =
          RegExp(r'(?:^|[?&])uid=(\d+)').firstMatch(href)?.group(1);
      if (uid == null || !seen.add(uid)) {
        continue;
      }

      final container = _nearestContainer(add);
      final profile = container?.querySelector(
        'a[href*="mod=space"][href*="uid=$uid"], '
        'a[href*="space&uid=$uid"]',
      );

      var username = _clean(profile?.text ?? '');
      if (username.isEmpty) {
        username = _clean(
          container?.querySelector('.tit a, h4 a, .xw1')?.text ?? '',
        );
      }
      if (username.isEmpty) {
        username = 'UID $uid';
      }

      final ignore = container?.querySelector(
        'a[href*="ac=friend"][href*="op=ignore"][href*="uid=$uid"]',
      );
      final avatar = container?.querySelector(
        'img[src*="avatar"], img[src*="uc_server"], img',
      );

      result.add(
        FriendRequestItem(
          uid: uid,
          username: username,
          avatarUrl: _absoluteUrl(avatar?.attributes['src'], baseUrl),
          acceptUrl: _absoluteUrl(href, baseUrl),
          ignoreUrl: _absoluteUrl(
            ignore?.attributes['href'],
            baseUrl,
          ),
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
      for (final name in const [
        'data-name', 'data-label', 'data-title', 'title', 'alt',
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

      var label = textFromAttributes(input);
      if (label.isEmpty) label = textFromAttributes(labelElement);
      if (label.isEmpty) label = textFromAttributes(image);
      if (label.isEmpty && labelElement != null) {
        label = _sanitizeVisibleText(labelElement.text);
      }
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
      endTimestamp: endTimestamp,
      messages: messages,
    );
  }

  List<PmMessage> parsePmMessageFragment(
    String raw, {
    String? myUid,
    String? peerUid,
  }) {
    final document = html_parser.parse(_unwrapCdata(raw));
    return _parsePmMessages(
      document,
      myUid: myUid,
      peerUid: peerUid,
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

      final lastMessage = _nullableClean(
        container?.querySelector(
          '.msg_mes, .summary, .comiis_pm_txt, p',
        )?.text,
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
        ),
      );
    }

    return result;
  }
  List<PmMessage> _parsePmMessages(
    html_dom.Document document, {
    String? myUid,
    String? peerUid,
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

      final content = _sanitizeVisibleText(messageNode.text);
      if (content.isEmpty) return;

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

      final key = '$senderUid|$time|$content';
      if (result.any(
        (item) => '${item.senderUid}|${item.time}|${item.content}' == key,
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
      for (final messageNode in document.querySelectorAll('.msg_mes')) {
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
        addMessage(scope);
      }
    }

    return result;
  }

  bool _isCreditJunk(String value) {
    final text = _sanitizeVisibleText(value);
    if (text.isEmpty) {
      return true;
    }

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

    return exact.contains(text);
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
