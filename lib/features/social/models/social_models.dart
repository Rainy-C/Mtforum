part of '../../../models/models.dart';

class SocialUser {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? profileUrl;
  final String? messageUrl;

  const SocialUser({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.profileUrl,
    this.messageUrl,
  });
}

class FriendRequestItem {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? acceptUrl;
  final String? ignoreUrl;
  final String requestTime;
  final bool isOnline;

  const FriendRequestItem({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.acceptUrl,
    this.ignoreUrl,
    this.requestTime = '',
    this.isOnline = false,
  });
}

class WallComment {
  final String cid;
  final String uid;
  final String username;
  final String? avatarUrl;
  final String time;
  final String content;

  const WallComment({
    required this.cid,
    required this.uid,
    required this.username,
    this.avatarUrl,
    required this.time,
    required this.content,
  });
}

class OperationResult {
  final bool success;
  final String message;

  const OperationResult({
    required this.success,
    required this.message,
  });
}

class FriendItem {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? messageUrl;

  const FriendItem({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.messageUrl,
  });
}
