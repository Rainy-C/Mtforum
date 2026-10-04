part of '../user_center_parser.dart';

extension UserCenterParserProfileParserPart on UserCenterParser {
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

  String _clean(String value) => HtmlText.inline(value);

  /// 统一走 [AppUrl.resolve]（保留 `../` 这类相对路径解析）。
  String? _absoluteUrl(String? raw, String baseUrl) =>
      AppUrl.resolve(raw, baseUrl, resolveRelative: true);
}
