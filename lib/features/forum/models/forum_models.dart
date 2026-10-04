part of '../../../models/models.dart';

class SearchResult {
  final String tid;
  final String? title;
  final String? authorUid;
  final String? authorName;
  final String? avatarUrl;
  final String? forumName;
  final String? postTime;
  final String? excerpt;
  final String? replyCount;
  final String? viewCount;
  final String? likeCount;
  final List<String> thumbnails;
  final bool hasHiddenContent;
  final String? typeId;
  final String? typeName;

  const SearchResult({
    required this.tid,
    this.title,
    this.authorUid,
    this.authorName,
    this.avatarUrl,
    this.forumName,
    this.postTime,
    this.excerpt,
    this.replyCount,
    this.viewCount,
    this.likeCount,
    this.thumbnails = const [],
    this.hasHiddenContent = false,
    this.typeId,
    this.typeName,
  });
}

/// 论坛排行榜用户项。
class RankItem {
  final String uid;
  final String username;
  final String? avatarUrl;
  final int rank;
  final String? gender;
  final String value;

  const RankItem({
    required this.uid,
    required this.username,
    this.avatarUrl,
    required this.rank,
    this.gender,
    required this.value,
  });
}

class SignResult {
  final bool success;
  final bool alreadySigned;
  final String message;

  const SignResult({
    required this.success,
    required this.message,
    this.alreadySigned = false,
  });
}

class SignRecord {
  final String uid;
  final String username;
  final String signTime;
  final String totalDays;
  final String reward;

  const SignRecord({
    required this.uid,
    required this.username,
    required this.signTime,
    required this.totalDays,
    required this.reward,
  });
}

class FavoriteItem {
  final String favid;
  final String title;
  final String type;
  final String href;
  final String? deleteUrl;
  final String? tid;
  final Thread? thread;

  const FavoriteItem({
    required this.favid,
    required this.title,
    required this.type,
    required this.href,
    this.deleteUrl,
    this.tid,
    this.thread,
  });

  bool get isThread => tid != null && tid!.isNotEmpty;
}

class ForumBoard {
  final String fid;
  final String name;
  final String? iconUrl;
  final int? todayPosts;

  const ForumBoard({
    required this.fid,
    required this.name,
    this.iconUrl,
    this.todayPosts,
  });
}

class ForumGroup {
  final String id;
  final String name;
  final List<ForumBoard> boards;

  const ForumGroup({
    required this.id,
    required this.name,
    required this.boards,
  });
}

class ReplyResult {
  final bool success;
  final String? newPid;
  final String message;

  const ReplyResult({
    required this.success,
    this.newPid,
    required this.message,
  });
}

class LoginResult {
  final bool success;
  final String message;

  const LoginResult({required this.success, required this.message});
}
