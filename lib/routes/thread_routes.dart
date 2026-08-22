import 'package:flutter/material.dart';

import '../pages/thread_detail_page.dart';

/// 帖子详情统一走全局页面过渡，保证进入与返回和其他页面完全一致。
Route<T> buildThreadRoute<T>(String tid) {
  return MaterialPageRoute<T>(
    settings: RouteSettings(name: '/thread/$tid'),
    builder: (_) => ThreadDetailPage(tid: tid),
  );
}
