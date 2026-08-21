import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

class SignParser {
  const SignParser();

  SignResult parseSignResponse(String raw) {
    final cdata = RegExp(
      r'<!\[CDATA\[(.*?)\]\]>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);

    var message = _clean(
      html_parser.parseFragment(cdata ?? raw).text ?? '',
    );

    if (message.isEmpty) {
      message = _clean(raw);
    }

    final notLogged = message.contains('未登录') ||
        message.contains('还未登录') ||
        message.contains('请先登录');

    final alreadySigned = message.contains('已签到');
    final success = !notLogged &&
        (alreadySigned ||
            message.contains('签到成功') ||
            (message.contains('成功') && !message.contains('失败')));

    return SignResult(
      success: success,
      alreadySigned: alreadySigned,
      message: message.isEmpty
          ? (success ? '签到成功' : '签到失败')
          : message,
    );
  }

  List<SignRecord> parseRank(
    String raw, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(raw);
    final records = <SignRecord>[];

    for (final row in document.querySelectorAll('tbody[id^="autolist_"]')) {
      final uid = row.id.replaceFirst('autolist_', '').trim();
      if (uid.isEmpty) {
        continue;
      }

      final spans = row.querySelectorAll('h4 span');
      final username = _clean(row.querySelector('h4 a')?.text ?? '');
      final signTime = spans.isNotEmpty ? _clean(spans.first.text) : '';

      String totalDays = '';
      final totalEl = row.querySelector('h4 span.y');
      if (totalEl != null) {
        totalDays = _clean(totalEl.text);
      } else if (spans.length > 1) {
        totalDays = _clean(spans[1].text);
      }

      final detail = _clean(row.querySelector('p')?.text ?? '');

      records.add(
        SignRecord(
          uid: uid,
          username: username,
          signTime: signTime,
          totalDays: totalDays,
          reward: detail,
        ),
      );
    }

    return records;
  }

  String _clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
