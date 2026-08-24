import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;

class ImageHostUploadResult {
  final String url;
  final String bbcode;

  const ImageHostUploadResult({
    required this.url,
    required this.bbcode,
  });
}

/// MT 图床匿名上传客户端。
///
/// 使用独立 Dio/CookieJar，绝不携带论坛登录 Cookie。每次会话先访问图床
/// 首页动态取得 Laravel CSRF 和匿名 Session，再提交图片，避免硬编码临时
/// Cookie 或 x-csrf-token。
class ImageHostService {
  ImageHostService._();

  static final ImageHostService instance = ImageHostService._();

  static const _baseUrl = 'https://img.binmt.cc';
  static const _strategyId = '2';

  Future<ImageHostUploadResult> uploadImage(String filePath) async {
    final cookieJar = CookieJar();
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: const {
          'User-Agent': 'okhttp/4.12.0',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
      ),
    )..interceptors.add(CookieManager(cookieJar));

    final home = await dio.get<String>(
      '/',
      options: Options(responseType: ResponseType.plain),
    );
    final csrfToken = _extractCsrfToken(home.data ?? '');
    if (csrfToken.isEmpty) {
      throw StateError('图床会话初始化失败：未获取到 CSRF Token');
    }

    final fileName = filePath
        .replaceAll('\\', '/')
        .split('/')
        .last
        .trim();
    final form = FormData.fromMap({
      'strategy_id': _strategyId,
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName.isEmpty ? 'image.jpg' : fileName,
      ),
    });

    final response = await dio.post<dynamic>(
      '/upload',
      data: form,
      options: Options(
        headers: {
          'x-requested-with': 'XMLHttpRequest',
          'x-csrf-token': csrfToken,
          'origin': _baseUrl,
          'referer': '$_baseUrl/',
        },
        responseType: ResponseType.json,
      ),
    );

    return parseUploadResponse(response.data);
  }

  static String _extractCsrfToken(String html) {
    final document = html_parser.parse(html);
    return document
            .querySelector('meta[name="csrf-token"]')
            ?.attributes['content']
            ?.trim() ??
        '';
  }

  static ImageHostUploadResult parseUploadResponse(dynamic raw) {
    if (raw is! Map) {
      throw StateError('图床返回格式异常');
    }
    final status = raw['status'] == true;
    final message = '${raw['message'] ?? ''}'.trim();
    final data = raw['data'];
    final links = data is Map ? data['links'] : null;
    final url = links is Map ? '${links['url'] ?? ''}'.trim() : '';
    final returnedBbcode =
        links is Map ? '${links['bbcode'] ?? ''}'.trim() : '';

    if (!status || url.isEmpty) {
      throw StateError(message.isEmpty ? '图片上传失败' : message);
    }
    return ImageHostUploadResult(
      url: url,
      bbcode: returnedBbcode.isEmpty ? '[img]$url[/img]' : returnedBbcode,
    );
  }
}
