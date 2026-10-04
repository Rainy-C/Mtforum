part of '../../../services/api_service.dart';

extension ApiServiceProfilePart on ApiService {
  Future<UserProfile> getProfile() async {
    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {'mod': 'space', 'do': 'profile', 'mobile': 2},
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final body = response.data ?? '';
    final document = html_parser.parse(body);
    final uid = RegExp(r"discuz_uid\s*=\s*'?(\d+)")
            .firstMatch(body)
            ?.group(1) ??
        _currentUid ??
        '0';
    if (uid != '0') _currentUid = uid;

    // 先沿用旧链路读取当前页上一直稳定的基础字段，避免模板差异导致回归。
    var fallbackUsername =
        document.querySelector('.comiis_uinfo_a, .vh')?.text.trim();
    fallbackUsername ??= document.querySelector('h2')?.text.trim();
    final fallbackAvatar = _absoluteUrl(
      document.querySelector('img[src*="avatar"]')?.attributes['src'],
    );

    int? fallbackCredits;
    int? fallbackGold;
    final matches = RegExp(r'<em[^>]*>(\d+)</em>\s*<p[^>]*>([^<]+)')
        .allMatches(body);
    for (final match in matches) {
      final value = int.tryParse(match.group(1) ?? '');
      final label = match.group(2)?.trim() ?? '';
      if (value == null) continue;
      if (label.contains('积分')) fallbackCredits = value;
      if (label.contains('金币')) fallbackGold = value;
    }

    // “我的”与用户主页共享同一套真实 DOM 统计解析。之前这里只解析基础字段，
    // 导致帖子、回复、好友一直为 null，UI 再把 null 错误显示成了 0。
    var parsed = _userCenterParser.parseCurrentProfile(
      body,
      uid: uid,
      baseUrl: ApiService.baseUrl,
    );

    // 某些 Comiis 模板在“不带 uid 的自己的资料页”会省略统计栏。只在三个
    // 核心统计都缺失时，再请求一次明确 uid 的真实用户主页，避免每次多打一请求。
    if (uid != '0' &&
        parsed.threads == null &&
        parsed.posts == null &&
        parsed.friends == null) {
      try {
        final statsResponse = await _dio.get<String>(
          '/home.php',
          queryParameters: {
            'mod': 'space',
            'uid': uid,
            'do': 'profile',
            'mobile': 2,
          },
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
        parsed = _userCenterParser.parseCurrentProfile(
          statsResponse.data ?? '',
          uid: uid,
          baseUrl: ApiService.baseUrl,
        );
      } catch (_) {
        // 统计补充失败不影响“我的”基础资料；UI 用“—”表示未知，而不是伪造 0。
      }
    }

    final parsedUsername = parsed.username?.trim() ?? "";
    final parsedUsernameUsable = parsedUsername.isNotEmpty &&
        parsedUsername != 'UID $uid' &&
        parsedUsername != '未知用户';

    return UserProfile(
      uid: uid,
      username: parsedUsernameUsable
          ? parsedUsername
          : (fallbackUsername?.isNotEmpty == true
              ? fallbackUsername
              : '未知用户'),
      avatarUrl: parsed.avatarUrl ?? fallbackAvatar,
      userGroup: parsed.userGroup,
      credits: parsed.credits ?? fallbackCredits,
      gold: parsed.gold ?? fallbackGold,
      contribution: parsed.contribution,
      threads: parsed.threads,
      posts: parsed.posts,
      friends: parsed.friends,
      regDate: parsed.regDate,
      lastVisit: parsed.lastVisit,
    );
  }
  /// 读取签到页当前状态，同时顺便刷新页面里可能存在的 formhash。
  Future<bool> isSignedToday() async {
    if (!isLoggedIn) {
      return false;
    }

    try {
      final response = await _dio.get<String>(
        '/k_misign-sign.html',
        options: Options(
          headers: {
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=space&do=profile&mycenter=1',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      final body = response.data ?? '';
      final hash = _extractFormhash(body);
      if (hash != null && hash.isNotEmpty) {
        _rememberFormhash(hash);
      }

      final text = html_parser.parse(body).body?.text ?? '';
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (normalized.contains('今日已签到') ||
          normalized.contains('已签到')) {
        return true;
      }

      if (normalized.contains('尚未签到') ||
          normalized.contains('还未签到') ||
          normalized.contains('立即签到')) {
        return false;
      }

      return false;
    } catch (_) {
      return false;
    }
  }
  /// 获取签到使用的 formhash。
  ///
  /// 已登录状态下优先复用当前有效 formhash。k_misign 的签到页在“当天已签到”
  /// 等状态下不一定继续输出 formhash，因此不能把签到页作为唯一来源。
  Future<String> getSignFormhash() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final current = _formhash;
    if (current != null && current.isNotEmpty) {
      return current;
    }

    try {
      final response = await _dio.get<String>(
        '/k_misign-sign.html',
        options: Options(
          headers: {
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=space&do=profile&mycenter=1',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      final hash = _extractFormhash(response.data ?? '');
      if (hash != null && hash.isNotEmpty) {
        _rememberFormhash(hash);
        return hash;
      }
    } catch (_) {
      // 继续使用通用页面兜底。
    }

    return refreshFormhash();
  }
  Future<SignResult> signIn() async {
    if (!isLoggedIn) {
      return const SignResult(
        success: false,
        message: '请先登录',
      );
    }

    try {
      final hash = await getSignFormhash();
      var result = await _requestSign(hash);

      // 如果服务器明确提示凭证失效，刷新 formhash 后只重试一次。
      if (!result.success &&
          (result.message.contains('formhash') ||
              result.message.contains('非法') ||
              result.message.contains('请求错误'))) {
        _formhash = null;
        final freshHash = await refreshFormhash();
        result = await _requestSign(freshHash);
      }

      return result;
    } catch (e) {
      return SignResult(
        success: false,
        message: '签到失败：$e',
      );
    }
  }
  Future<SignResult> _requestSign(String hash) async {
    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: {
        'id': 'k_misign:sign',
        'operation': 'qiandao',
        'format': 'text',
        'formhash': hash,
      },
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${ApiService.baseUrl}/k_misign-sign.html',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    return _signParser.parseSignResponse(response.data ?? '');
  }
  Future<List<SignRecord>> getSignRank(
    String type, {
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: {
        'id': 'k_misign:sign',
        'operation': 'list',
        'op': type,
        'page': page,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _signParser.parseRank(
      response.data ?? '',
      baseUrl: ApiService.baseUrl,
    );
  }
  Future<BasicProfileForm> getBasicProfileForm() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'base',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseBasicProfile(
      response.data ?? '',
    );
  }
  Future<OperationResult> updateBasicProfile(
    BasicProfileForm form,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(
        success: false,
        message: '请先登录',
      );
    }

    try {
      // 先打开编辑页，让页面本身的 formhash 进入全局缓存。
      await getBasicProfileForm();
      final hash = await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'base',
        },
        data: FormData.fromMap({
          'formhash': hash,
          'realname': form.realname,
          'privacy[realname]': form.privacyRealname,
          'gender': form.gender,
          'privacy[gender]': form.privacyGender,
          'birthyear': form.birthyear,
          'birthmonth': form.birthmonth,
          'birthday': form.birthday,
          'privacy[birthday]': form.privacyBirthday,
          'resideprovince': form.resideProvince,
          'privacy[residecity]': form.privacyResideCity,
          'occupation': form.occupation,
          'privacy[occupation]': form.privacyOccupation,
          'profilesubmit': 'true',
          'profilesubmitbtn': 'true',
        }),
        options: Options(
          headers: {
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=profile&op=base',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final success = body.contains('parent.show_success') ||
          body.contains('show_success');

      return OperationResult(
        success: success,
        message: success ? '资料已保存' : '保存失败，请检查服务器返回',
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '保存失败：$e',
      );
    }
  }
  Future<CreditSummary> getCreditSummary() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'credit',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseCreditSummary(
      response.data ?? '',
    );
  }
  Future<RemoteTextPageData> getCreditSection(
    String op,
  ) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final query = <String, dynamic>{
      'mod': 'spacecp',
      'ac': 'credit',
      'op': op,
    };

    if (op == 'log') {
      query['inajax'] = 1;
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        headers: op == 'log'
            ? const {'X-Requested-With': 'XMLHttpRequest'}
            : null,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseTextPage(
      response.data ?? '',
      fallbackTitle: op == 'log' ? '积分记录' : '积分明细',
    );
  }
  Future<SpaceUserProfile> getSpaceUserProfile(
    String uid,
  ) async {
    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'uid': uid,
        'do': 'profile',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSpaceProfile(
      response.data ?? '',
      uid: uid,
      baseUrl: ApiService.baseUrl,
    );
  }
  Future<SignatureProfileForm> getSignatureProfile() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'info',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSignatureProfile(response.data ?? '');
  }
  Future<OperationResult> updateSignatureProfile(
    SignatureProfileForm form,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      await getSignatureProfile();
      final hash = await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'info',
        },
        data: FormData.fromMap({
          'formhash': hash,
          'privacy[bio]': form.privacyBio,
          'bio': form.bio,
          'sightml': form.signature,
          'profilesubmit': 'true',
          'profilesubmitbtn': 'true',
        }),
        options: Options(
          headers: {
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=profile&op=info',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final success = (response.data ?? '').contains('show_success');
      return OperationResult(
        success: success,
        message: success ? '简介与签名已保存' : '保存失败',
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '保存失败：$e',
      );
    }
  }
  Future<PasswordSecurityData> getPasswordSecurity() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'password',
        'from': 'contact',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parsePasswordSecurity(response.data ?? '');
  }
  Future<OperationResult> resendVerificationEmail() async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final page = await getPasswordSecurity();
      final hash = page.formhash.isNotEmpty
          ? page.formhash
          : await getFormhash();

      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'password',
          'resend': 1,
          'formhash': hash,
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=profile&op=password&from=contact',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final message = _extractAjaxMessage(response.data ?? '');
      final success = message.contains('邮件已发送');

      return OperationResult(
        success: success,
        message: success
            ? '验证邮件已发送，请稍后查收'
            : (message.isEmpty ? '发送失败' : message),
      );
    } catch (e) {
      return OperationResult(success: false, message: '发送失败：$e');
    }
  }
  Future<OperationResult> updatePasswordSecurity(
    PasswordSecurityUpdate update,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    if (update.oldPassword.isEmpty) {
      return const OperationResult(success: false, message: '请输入原密码');
    }
    if (update.newPassword != update.newPasswordConfirm) {
      return const OperationResult(success: false, message: '两次输入的新密码不一致');
    }

    try {
      final page = await getPasswordSecurity();
      final hash = page.formhash.isNotEmpty ? page.formhash : await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'handlekey': 'undefined',
          'inajax': 1,
        },
        data: {
          'formhash': hash,
          'oldpassword': update.oldPassword,
          'newpassword': update.newPassword,
          'newpassword2': update.newPasswordConfirm,
          'emailnew': update.email,
          'secmobiccnew': update.mobileCountryCode,
          'secmobilenew': update.mobile,
          'questionidnew': update.questionId,
          'answernew': update.answer,
          'passwordsubmit': 'true',
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=profile&op=password&from=contact',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final message = _extractAjaxMessage(body);
      final success = body.contains('个人资料保存成功') ||
          message.contains('个人资料保存成功');
      return OperationResult(
        success: success,
        message: success ? '安全设置保存成功' : (message.isEmpty ? '保存失败' : message),
      );
    } catch (e) {
      return OperationResult(success: false, message: '保存失败：$e');
    }
  }
  Future<ContactProfileForm> getContactProfile() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'contact',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseContactProfile(response.data ?? '');
  }
  Future<OperationResult> updateContactProfile(
    ContactProfileForm form,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final hash = await getFormhash();
      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'contact',
        },
        data: FormData.fromMap({
          'formhash': hash,
          'qq': form.qq,
          'privacy[qq]': form.privacyQq,
          'mobile': form.mobile,
          'privacy[mobile]': form.privacyMobile,
          'profilesubmit': 'true',
          'profilesubmitbtn': 'true',
        }),
        options: Options(
          headers: {
            'Referer': '${ApiService.baseUrl}/home.php?mod=spacecp&ac=profile&op=contact',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final success = (response.data ?? '').contains('show_success');
      return OperationResult(
        success: success,
        message: success ? '联系方式已保存' : '保存失败',
      );
    } catch (e) {
      return OperationResult(success: false, message: '保存失败：$e');
    }
  }
  Future<SmsBindingData> getSmsBinding() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'plugin',
        'id': 'comiis_sms:comiis_setup',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSmsBinding(response.data ?? '');
  }
  Future<SmsCodeResult> requestSmsCode({
    required String action,
    required String phone,
  }) async {
    if (!isLoggedIn) {
      return const SmsCodeResult(success: false, message: '请先登录');
    }
    final normalizedAction = action == 'Unbundling' ? 'Unbundling' : 'binding';

    try {
      final response = await _dio.get<String>(
        '/plugin.php',
        queryParameters: {
          'id': 'comiis_sms',
          'action': normalizedAction,
          'comiis_tel': phone.trim(),
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final match = RegExp(r'comiis_mob_reg\|(\d+)\|(\d+)').firstMatch(body);
      final success = match?.group(1) == '1';
      final cooldown = int.tryParse(match?.group(2) ?? '') ?? 0;
      return SmsCodeResult(
        success: success,
        message: success ? '验证码已发送' : '验证码发送失败',
        cooldownSeconds: cooldown,
      );
    } catch (e) {
      return SmsCodeResult(success: false, message: '验证码发送失败：$e');
    }
  }
  Future<OperationResult> confirmSmsBinding({
    required String action,
    required String phone,
    required String code,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    final normalizedAction = action == 'Unbundling' ? 'Unbundling' : 'binding';
    try {
      final hash = await getFormhash();
      final headerReferer = normalizedAction == 'Unbundling'
          ? '${ApiService.baseUrl}/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup'
          : '${ApiService.baseUrl}/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup&mobile=2';
      final bodyReferer = normalizedAction == 'Unbundling'
          ? '${ApiService.baseUrl}/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup&mods=rename'
          : '${ApiService.baseUrl}/plugin.php?id=comiis_sms:comiis_sms_post&action=Unbundling';

      final response = await _dio.post<String>(
        '/plugin.php',
        queryParameters: {
          'id': 'comiis_sms:comiis_sms_post',
          'action': normalizedAction,
        },
        data: FormData.fromMap({
          'formhash': hash,
          'comiis_mobile_bindingsubmit': 'true',
          'referer': bodyReferer,
          'comiis_tel': phone.trim(),
          'code': code.trim(),
        }),
        options: Options(
          headers: {'Referer': headerReferer},
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final success = normalizedAction == 'Unbundling'
          ? body.contains('解除绑定成功')
          : body.contains('绑定成功');
      return OperationResult(
        success: success,
        message: success
            ? (normalizedAction == 'Unbundling' ? '解除绑定成功' : '绑定成功')
            : (_extractAjaxMessage(body).isEmpty
                ? '操作失败，请检查验证码'
                : _extractAjaxMessage(body)),
      );
    } catch (e) {
      return OperationResult(success: false, message: '操作失败：$e');
    }
  }
  Future<OperationResult> uploadAvatarJpeg(List<int> jpegBytes) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    if (jpegBytes.isEmpty) {
      return const OperationResult(success: false, message: '图片数据为空');
    }

    try {
      final hash = await getFormhash();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
      final response = await _dio.post<String>(
        '/plugin.php',
        queryParameters: const {
          'id': 'comiis_app_avatar',
          'inajax': 1,
          'mobile': 2,
        },
        data: {
          'str': dataUrl,
          'formhash': hash,
          'comiis_submit': 'yes',
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=space&do=profile&set=comiis&mycenter=1',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final success = response.statusCode == 200;
      return OperationResult(
        success: success,
        message: success ? '头像更新成功' : '头像更新失败',
      );
    } catch (e) {
      return OperationResult(success: false, message: '头像更新失败：$e');
    }
  }
  Future<InviteStatusData> getInviteStatus() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'invite',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );
    return _userCenterParser.parseInviteStatus(response.data ?? '');
  }
  Future<PromotionData> getPromotion() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'promotion',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parsePromotion(
      response.data ?? '',
      baseUrl: ApiService.baseUrl,
    );
  }
  Future<List<CreditRecord>> getCreditRecords(String op) async {
    if (!isLoggedIn) throw StateError('请先登录');

    final query = <String, dynamic>{
      'mod': 'spacecp',
      'ac': 'credit',
      'op': op,
    };
    if (op == 'log') query['inajax'] = 1;

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        headers: op == 'log'
            ? const {'X-Requested-With': 'XMLHttpRequest'}
            : null,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseCreditRecords(response.data ?? '');
  }
  Future<UserGroupData> getUserGroupData() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'usergroup',
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _accountParser.parseUserGroup(response.data ?? '');
  }
  Future<RenameStatusData> getRenameStatus() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: const {
        'id': 'nimba_rename',
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseRenameStatus(response.data ?? '');
  }
  Future<RemoteTextPageData> getAccountToolPage(
    String key, {
    String? uid,
  }) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    late final String path;
    late final Map<String, dynamic> query;
    late final String fallbackTitle;

    switch (key) {
      case 'profile_info':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'info',
        };
        fallbackTitle = '详细资料';
        break;
      case 'contact':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'contact',
        };
        fallbackTitle = '联系方式';
        break;
      case 'password':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'password',
          'from': 'contact',
        };
        fallbackTitle = '修改密码';
        break;
      case 'invite':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'invite',
        };
        fallbackTitle = '邀请';
        break;
      case 'promotion':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'promotion',
        };
        fallbackTitle = '访问推广';
        break;
      case 'sms':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'plugin',
          'id': 'comiis_sms:comiis_setup',
        };
        fallbackTitle = '短信设置';
        break;
      case 'profile_view':
        path = '/home.php';
        query = {
          'mod': 'space',
          'do': 'profile',
          'view': 'me',
          'from': 'space',
        };
        fallbackTitle = '我的资料';
        break;
      default:
        throw ArgumentError.value(key, 'key');
    }

    final response = await _dio.get<String>(
      path,
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseTextPage(
      response.data ?? '',
      fallbackTitle: fallbackTitle,
    );
  }
}
