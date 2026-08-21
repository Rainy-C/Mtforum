import 'package:flutter_test/flutter_test.dart';
import 'package:mtforum/data/sign_parser.dart';

void main() {
  const parser = SignParser();

  test('已签到响应视为成功', () {
    final result = parser.parseSignResponse(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<root><![CDATA[已签到]]></root>',
    );

    expect(result.success, isTrue);
    expect(result.alreadySigned, isTrue);
    expect(result.message, contains('已签到'));
  });

  test('签到成功响应视为成功', () {
    final result = parser.parseSignResponse(
      '<root><![CDATA[签到成功，获得 2 金币]]></root>',
    );

    expect(result.success, isTrue);
    expect(result.alreadySigned, isFalse);
  });

  test('未登录响应不能误判成功', () {
    final result = parser.parseSignResponse(
      '<root><![CDATA[您还未登录，请先登录]]></root>',
    );

    expect(result.success, isFalse);
  });

  test('签到排行解析', () {
    final records = parser.parseRank(
      '''
      <table>
        <tbody id="autolist_154205">
          <tr>
            <td class="k_misign_lc">
              <h4 class="f_c">
                <a href="home.php?mod=space&uid=154205">Cynnie</a>
                <span>1 秒前</span>
                <span class="y">总天数 24天</span>
              </h4>
              <p class="f_0">月天数 3 天，上次奖励 2 金币</p>
            </td>
          </tr>
        </tbody>
      </table>
      ''',
      baseUrl: 'https://bbs.binmt.cc',
    );

    expect(records, hasLength(1));
    expect(records.single.uid, '154205');
    expect(records.single.username, 'Cynnie');
    expect(records.single.signTime, '1 秒前');
    expect(records.single.totalDays, '总天数 24天');
    expect(records.single.reward, contains('2 金币'));
  });
}
