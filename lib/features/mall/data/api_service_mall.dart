part of '../../../services/api_service.dart';

extension _ApiServiceMallPart on ApiService {
  Future<List<MallItem>> getMallItems({
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      '/keke_integralmall-keke_integralmall.html',
      queryParameters: {
        'page': page,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _portalParser.parseMallList(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }
  Future<MallDetail> getMallDetail(String tid) async {
    final response = await _dio.get<String>(
      '/keke_integralmall-view.html',
      queryParameters: {
        'tid': tid,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _portalParser.parseMallDetail(
      response.data ?? '',
      tid: tid,
      baseUrl: baseUrl,
    );
  }
  Future<String?> _getMallFormhash(String tid) async {
    try {
      final hash = await getFormhash();
      if (hash.isNotEmpty) {
        return hash;
      }
    } catch (_) {
      // 通用 formhash 刷新失败时，继续从商城自己的真实页面取值。
    }

    final candidates = <({String path, Map<String, dynamic> query})>[
      (
        path: '/keke_integralmall-view.html',
        query: <String, dynamic>{'tid': tid, 'mobile': 2},
      ),
      (
        path: '/keke_integralmall-keke_integralmall.html',
        query: <String, dynamic>{'mobile': 2},
      ),
    ];

    for (final candidate in candidates) {
      try {
        final response = await _dio.get<String>(
          candidate.path,
          queryParameters: candidate.query,
          options: Options(
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
        // 单个商城页面失败时继续尝试下一个来源。
      }
    }

    return null;
  }
  Future<MallExchangeResult> exchangeMallItem({
    required String tid,
    String address = '',
  }) async {
    if (!isLoggedIn) {
      return const MallExchangeResult(
        success: false,
        message: '请先登录后再兑换',
      );
    }

    try {
      final hash = await _getMallFormhash(tid);
      if (hash == null || hash.isEmpty) {
        return const MallExchangeResult(
          success: false,
          message: '兑换信息获取失败，请刷新商品详情后重试',
        );
      }

      final popupPath =
          '/plugin.php?id=keke_integralmall:show_win'
          '&tid=$tid&ac=xd&formhash=$hash&mobile=2';

      // 保留论坛原本的确认弹窗请求流程，同时让后续 POST Referer 完全一致。
      await _dio.get<String>(
        popupPath,
        options: Options(
          headers: const {
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final response = await _dio.post<String>(
        '/plugin.php',
        queryParameters: const {
          'id': 'keke_integralmall:actions',
        },
        data: {
          'formhash': hash,
          'ac': 'xd',
          'tid': tid,
          'addr': address,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl$popupPath',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final decoded = jsonDecode(response.data ?? '{}');
      if (decoded is! Map) {
        return const MallExchangeResult(
          success: false,
          message: '兑换响应格式异常',
        );
      }

      final err = int.tryParse('${decoded['err'] ?? 1}') ?? 1;
      final message = '${decoded['msg'] ?? ''}'.trim();
      final url = '${decoded['url'] ?? ''}'.trim();

      return MallExchangeResult(
        success: err == 0,
        message: message.isEmpty
            ? (err == 0 ? '兑换成功' : '兑换失败')
            : message,
        url: url.isEmpty ? null : url,
      );
    } on DioException {
      return const MallExchangeResult(
        success: false,
        message: '兑换请求失败，请检查网络后重试',
      );
    } on FormatException {
      return const MallExchangeResult(
        success: false,
        message: '兑换响应格式异常，请稍后重试',
      );
    } catch (_) {
      return const MallExchangeResult(
        success: false,
        message: '兑换失败，请稍后重试',
      );
    }
  }
  Future<List<MallCardRecord>> _getMallCardRecords({
    required String tid,
    required String formhash,
  }) async {
    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: {
        'id': 'keke_integralmall:show_win',
        'tid': tid,
        'ac': 'km',
        'formhash': formhash,
        'mobile': 2,
      },
      options: Options(
        headers: const {
          'X-Requested-With': 'XMLHttpRequest',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    return _portalParser.parseMallCardRecords(response.data ?? '');
  }
  Future<MallCardStatus> getMallCardStatus(String tid) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final hash = await _getMallFormhash(tid);
    if (hash == null || hash.isEmpty) {
      throw StateError('卡密信息获取失败，请刷新后重试');
    }

    try {
      // 论坛真实“我购买的订单”页会列出所有可查看卡密的订单。
      // 先拿完整订单列表，再按每个订单自己的 tid 并发读取卡密内容，
      // 避免商品详情页只能看到当前 tid 的一条历史记录。
      final buyListResponse = await _dio.get<String>(
        '/keke_integralmall-show_win.html',
        queryParameters: {
          'tid': 0,
          'ac': 'buylist',
          'formhash': hash,
          'type': 1,
        },
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
          headers: {
            'Referer': '$baseUrl/keke_integralmall-keke_integralmall.html',
          },
        ),
      );

      final html = buyListResponse.data ?? '';
      final purchases = _portalParser.parseMallCardPurchases(html);

      if (purchases.isEmpty) {
        // 确实拿到了 buylist 容器时，空列表就是用户没有卡密订单。
        if (html.contains('id="buylist"') || html.contains("id='buylist'")) {
          return const MallCardStatus();
        }
        throw const FormatException('未识别购买记录');
      }

      final loaded = await Future.wait(
        purchases.map((purchase) async {
          try {
            final records = await _getMallCardRecords(
              tid: purchase.tid,
              formhash: hash,
            );
            return purchase.copyWith(records: records);
          } catch (_) {
            return purchase.copyWith(loadFailed: true);
          }
        }),
      );

      if (loaded.every((purchase) => purchase.loadFailed)) {
        throw StateError('卡密记录加载失败');
      }

      return MallCardStatus(purchases: loaded);
    } catch (_) {
      // buylist 页面异常时保留当前商品的单条查询作为最后兜底，
      // 避免论坛模板临时变化导致已有功能完全不可用。
      final records = await _getMallCardRecords(
        tid: tid,
        formhash: hash,
      );
      if (records.isEmpty) {
        return const MallCardStatus();
      }
      return MallCardStatus(
        purchases: [
          MallCardPurchase(
            tid: tid,
            title: '当前商品',
            records: records,
          ),
        ],
      );
    }
  }
}
