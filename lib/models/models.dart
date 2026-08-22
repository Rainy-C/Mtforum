/// 帖子列表项。
class Thread {
  final String tid;
  final String? title;
  final String? authorUid;
  final String? authorName;
  final String? avatarUrl;
  final String? forumName;
  final String? forumId;
  final String? replyCount;
  final String? viewCount;
  final String? likeCount;
  final String? lastReplyTime;
  final String? excerpt;
  final List<String> thumbnails;
  final bool hasHiddenContent;

  const Thread({
    required this.tid,
    this.title,
    this.authorUid,
    this.authorName,
    this.avatarUrl,
    this.forumName,
    this.forumId,
    this.replyCount,
    this.viewCount,
    this.likeCount,
    this.lastReplyTime,
    this.excerpt,
    this.thumbnails = const [],
    this.hasHiddenContent = false,
  });

  Thread copyWith({
    String? tid,
    String? title,
    String? authorUid,
    String? authorName,
    String? avatarUrl,
    String? forumName,
    String? forumId,
    String? replyCount,
    String? viewCount,
    String? likeCount,
    String? lastReplyTime,
    String? excerpt,
    List<String>? thumbnails,
    bool? hasHiddenContent,
  }) {
    return Thread(
      tid: tid ?? this.tid,
      title: title ?? this.title,
      authorUid: authorUid ?? this.authorUid,
      authorName: authorName ?? this.authorName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      forumName: forumName ?? this.forumName,
      forumId: forumId ?? this.forumId,
      replyCount: replyCount ?? this.replyCount,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      lastReplyTime: lastReplyTime ?? this.lastReplyTime,
      excerpt: excerpt ?? this.excerpt,
      thumbnails: thumbnails ?? this.thumbnails,
      hasHiddenContent: hasHiddenContent ?? this.hasHiddenContent,
    );
  }

  String get detailUrl => 'https://bbs.binmt.cc/thread-$tid-1-1.html';
}

/// 帖子楼层。
class Post {
  final String pid;
  final String? authorUid;
  final String? authorName;
  final String? authorLevel;
  final String? avatarUrl;
  final String content;
  final String? floor;
  final String? postTime;
  final bool isOp;
  final List<String> images;
  final List<PostContent> richContent;
  final String? repquotePid;
  final String? replyToName;
  final String? hiddenHint;
  final int page;

  const Post({
    required this.pid,
    this.authorUid,
    this.authorName,
    this.authorLevel,
    this.avatarUrl,
    required this.content,
    this.floor,
    this.postTime,
    this.isOp = false,
    this.images = const [],
    this.richContent = const [],
    this.repquotePid,
    this.replyToName,
    this.hiddenHint,
    this.page = 1,
  });
}

class ThreadDetail {
  final String tid;
  final String title;
  final List<Post> posts;
  final String formhash;
  final String noticeauthor;
  final String fid;
  final int page;
  final String currentUid;

  const ThreadDetail({
    required this.tid,
    required this.title,
    required this.posts,
    required this.formhash,
    required this.noticeauthor,
    required this.fid,
    required this.page,
    this.currentUid = '',
  });
}

class PostEditorForm {
  final String formhash;
  final String posttime;
  final String fid;
  final String tid;
  final String pid;
  final int page;
  final String subject;
  final String message;
  final String deleteValue;
  final String allowNoticeAuthor;
  final String useSig;
  final String uploadUid;
  final String uploadHash;
  final int maxUploadSizeKb;

  const PostEditorForm({
    required this.formhash,
    required this.posttime,
    required this.fid,
    this.tid = '',
    this.pid = '',
    this.page = 1,
    this.subject = '',
    this.message = '',
    this.deleteValue = '0',
    this.allowNoticeAuthor = '1',
    this.useSig = '1',
    this.uploadUid = '',
    this.uploadHash = '',
    this.maxUploadSizeKb = 1024,
  });

  bool get canUploadImages => uploadUid.isNotEmpty && uploadHash.isNotEmpty;
}

class PostAttachmentUploadResult {
  final bool success;
  final String message;
  final String aid;
  final String relativePath;
  final String fileName;
  final String url;
  final String limitInfo;

  const PostAttachmentUploadResult({
    required this.success,
    required this.message,
    this.aid = '',
    this.relativePath = '',
    this.fileName = '',
    this.url = '',
    this.limitInfo = '',
  });
}

class ThreadSubmitResult {
  final bool success;
  final String message;
  final String? tid;
  final String? pid;
  final String? fid;

  const ThreadSubmitResult({
    required this.success,
    required this.message,
    this.tid,
    this.pid,
    this.fid,
  });
}

/// 帖子正文富文本块。
/// 由 ForumParser 将 Discuz/Comiis HTML 归一化为 App 可稳定渲染的结构。
class PostContent {
  final PostContentType type;
  final String text;
  final String? url;
  final List<List<String>> tableRows;
  final int tableHeaderRows;
  final List<PostContent> children;

  const PostContent._({
    required this.type,
    required this.text,
    this.url,
    this.tableRows = const [],
    this.tableHeaderRows = 0,
    this.children = const [],
  });

  factory PostContent.text(String t) =>
      PostContent._(type: PostContentType.text, text: t);

  factory PostContent.bold(String t) =>
      PostContent._(type: PostContentType.bold, text: t);

  factory PostContent.link(String t, String url) =>
      PostContent._(type: PostContentType.link, text: t, url: url);

  factory PostContent.image(String url) =>
      PostContent._(type: PostContentType.image, text: '', url: url);

  factory PostContent.emoji(String url) =>
      PostContent._(type: PostContentType.emoji, text: '', url: url);

  factory PostContent.quote(String t) =>
      PostContent._(type: PostContentType.quote, text: t);

  factory PostContent.richQuote(List<PostContent> children) => PostContent._(
        type: PostContentType.richQuote,
        text: '',
        children: List<PostContent>.unmodifiable(children),
      );

  factory PostContent.code(String t) =>
      PostContent._(type: PostContentType.code, text: t);

  factory PostContent.audio(String url) =>
      PostContent._(type: PostContentType.audio, text: '', url: url);

  factory PostContent.video(String url) =>
      PostContent._(type: PostContentType.video, text: '', url: url);

  factory PostContent.flash(String url) =>
      PostContent._(type: PostContentType.flash, text: '', url: url);

  factory PostContent.free(String t) =>
      PostContent._(type: PostContentType.free, text: t);

  factory PostContent.attachment(String name, {String? url}) => PostContent._(
        type: PostContentType.attachment,
        text: name,
        url: url,
      );

  factory PostContent.table(
    List<List<String>> rows, {
    int headerRows = 0,
  }) =>
      PostContent._(
        type: PostContentType.table,
        text: '',
        tableRows: rows,
        tableHeaderRows: headerRows,
      );
}

enum PostContentType {
  text,
  bold,
  link,
  image,
  emoji,
  quote,
  richQuote,
  code,
  audio,
  video,
  flash,
  free,
  attachment,
  table,
}

class UserProfile {
  final String uid;
  final String? username;
  final String? avatarUrl;
  final String? userGroup;
  final int? credits;
  final int? gold;
  final int? contribution;
  final int? threads;
  final int? posts;
  final int? friends;
  final String? regDate;
  final String? lastVisit;

  const UserProfile({
    required this.uid,
    this.username,
    this.avatarUrl,
    this.userGroup,
    this.credits,
    this.gold,
    this.contribution,
    this.threads,
    this.posts,
    this.friends,
    this.regDate,
    this.lastVisit,
  });
}

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
  final List<String> thumbnails;
  final bool hasHiddenContent;

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
    this.thumbnails = const [],
    this.hasHiddenContent = false,
  });
}

class LoginResult {
  final bool success;
  final String message;

  const LoginResult({required this.success, required this.message});
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
  final String? tid;

  const FavoriteItem({
    required this.favid,
    required this.title,
    required this.type,
    required this.href,
    this.tid,
  });

  bool get isThread => tid != null && tid!.isNotEmpty;
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

class MallItem {
  final String tid;
  final String title;
  final String? imageUrl;
  final int? priceGold;
  final String? marketPrice;
  final int? remaining;
  final int? purchased;
  final String? endTime;

  const MallItem({
    required this.tid,
    required this.title,
    this.imageUrl,
    this.priceGold,
    this.marketPrice,
    this.remaining,
    this.purchased,
    this.endTime,
  });
}

class MallDetail {
  final String tid;
  final String title;
  final String? imageUrl;
  final int? priceGold;
  final String? marketPrice;
  final String? buyUrl;
  final String? cardStatusUrl;

  const MallDetail({
    required this.tid,
    required this.title,
    this.imageUrl,
    this.priceGold,
    this.marketPrice,
    this.buyUrl,
    this.cardStatusUrl,
  });
}

class MallExchangeResult {
  final bool success;
  final String message;
  final String? url;

  const MallExchangeResult({
    required this.success,
    required this.message,
    this.url,
  });
}

class ForumBoard {
  final String fid;
  final String name;
  final String? iconUrl;

  const ForumBoard({
    required this.fid,
    required this.name,
    this.iconUrl,
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

class BasicProfileForm {
  final String realname;
  final int privacyRealname;
  final int gender;
  final int privacyGender;
  final int birthyear;
  final int birthmonth;
  final int birthday;
  final int privacyBirthday;
  final String resideProvince;
  final int privacyResideCity;
  final String occupation;
  final int privacyOccupation;

  const BasicProfileForm({
    this.realname = '',
    this.privacyRealname = 3,
    this.gender = 0,
    this.privacyGender = 0,
    this.birthyear = 0,
    this.birthmonth = 0,
    this.birthday = 0,
    this.privacyBirthday = 0,
    this.resideProvince = '',
    this.privacyResideCity = 0,
    this.occupation = '',
    this.privacyOccupation = 0,
  });
}

class CreditSummary {
  final int? total;
  final int? gold;
  final int? praise;
  final int? reputation;
  final String formula;

  const CreditSummary({
    this.total,
    this.gold,
    this.praise,
    this.reputation,
    this.formula = '',
  });
}

class RemoteTextPageData {
  final String title;
  final List<String> lines;

  const RemoteTextPageData({
    required this.title,
    required this.lines,
  });
}

class NoticeItem {
  final String id;
  final String type;
  final String authorUid;
  final String username;
  final String? avatarUrl;
  final String content;
  final String actionText;
  final String time;
  final String? targetTitle;
  final String? targetUrl;
  final String? tid;
  final String? pid;
  final String? ignoreUrl;
  final bool isSystem;
  final bool isUnread;

  const NoticeItem({
    this.id = '',
    this.type = '',
    this.authorUid = '',
    this.username = '',
    this.avatarUrl,
    required this.content,
    this.actionText = '',
    this.time = '',
    this.targetTitle,
    this.targetUrl,
    this.tid,
    this.pid,
    this.ignoreUrl,
    this.isSystem = false,
    this.isUnread = false,
  });

  bool get hasThreadTarget => tid != null && tid!.isNotEmpty;
}

class NoticePageData {
  final List<NoticeItem> items;
  final bool hasMore;

  const NoticePageData({
    required this.items,
    this.hasMore = false,
  });
}

class RenameStatusData {
  final int? costGold;
  final bool insufficientGold;
  final bool hasRenameForm;
  final String message;

  const RenameStatusData({
    this.costGold,
    this.insufficientGold = false,
    this.hasRenameForm = false,
    this.message = '',
  });
}

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

  const FriendRequestItem({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.acceptUrl,
    this.ignoreUrl,
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

class SpaceUserProfile {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String? backgroundUrl;
  final int? popularity;
  final int? following;
  final int? followers;
  final int? posts;
  final int? replies;
  final int? friends;
  final int? credits;
  final int? goodReview;
  final int? gold;
  final int? reputation;
  final String? level;
  final String? userGroup;
  final String? gender;
  final String? signature;
  final String? customTitle;
  final String? occupation;
  final String? residence;
  final String? birthday;
  final String? onlineTime;
  final String? registerTime;
  final String? lastVisit;
  final List<String> medalUrls;
  final bool isFollowing;
  final bool isBlocked;
  final String? followUrl;
  final String? friendUrl;
  final String? pokeUrl;
  final String? messageUrl;
  final String? reportUrl;

  const SpaceUserProfile({
    required this.uid,
    required this.username,
    this.avatarUrl,
    this.backgroundUrl,
    this.popularity,
    this.following,
    this.followers,
    this.posts,
    this.replies,
    this.friends,
    this.credits,
    this.goodReview,
    this.gold,
    this.reputation,
    this.level,
    this.userGroup,
    this.gender,
    this.signature,
    this.customTitle,
    this.occupation,
    this.residence,
    this.birthday,
    this.onlineTime,
    this.registerTime,
    this.lastVisit,
    this.medalUrls = const [],
    this.isFollowing = false,
    this.isBlocked = false,
    this.followUrl,
    this.friendUrl,
    this.pokeUrl,
    this.messageUrl,
    this.reportUrl,
  });

  SpaceUserProfile copyWith({
    int? following,
    int? followers,
    bool? isFollowing,
    bool? isBlocked,
    String? followUrl,
  }) {
    return SpaceUserProfile(
      uid: uid,
      username: username,
      avatarUrl: avatarUrl,
      backgroundUrl: backgroundUrl,
      popularity: popularity,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      posts: posts,
      replies: replies,
      friends: friends,
      credits: credits,
      goodReview: goodReview,
      gold: gold,
      reputation: reputation,
      level: level,
      userGroup: userGroup,
      gender: gender,
      signature: signature,
      customTitle: customTitle,
      occupation: occupation,
      residence: residence,
      birthday: birthday,
      onlineTime: onlineTime,
      registerTime: registerTime,
      lastVisit: lastVisit,
      medalUrls: medalUrls,
      isFollowing: isFollowing ?? this.isFollowing,
      isBlocked: isBlocked ?? this.isBlocked,
      followUrl: followUrl ?? this.followUrl,
      friendUrl: friendUrl,
      pokeUrl: pokeUrl,
      messageUrl: messageUrl,
      reportUrl: reportUrl,
    );
  }
}

class UserGroupPermission {
  final String name;
  final String value;
  final bool? allowed;

  const UserGroupPermission({
    required this.name,
    required this.value,
    this.allowed,
  });
}

class UserGroupData {
  final String groupName;
  final String currentLevel;
  final String nextLevel;
  final double progress;
  final String pointsNeeded;
  final String nextGroupName;
  final List<UserGroupPermission> permissions;

  const UserGroupData({
    this.groupName = '',
    this.currentLevel = '',
    this.nextLevel = '',
    this.progress = 0,
    this.pointsNeeded = '',
    this.nextGroupName = '',
    this.permissions = const [],
  });
}

class SignatureProfileForm {
  final String bio;
  final String signature;
  final int privacyBio;

  const SignatureProfileForm({
    this.bio = '',
    this.signature = '',
    this.privacyBio = 0,
  });
}

class SecurityQuestionOption {
  final int id;
  final String label;

  const SecurityQuestionOption({
    required this.id,
    required this.label,
  });
}

class PasswordSecurityData {
  final String formhash;
  final String email;
  final String mobileCountryCode;
  final String mobile;
  final int questionId;
  final List<SecurityQuestionOption> questions;

  const PasswordSecurityData({
    required this.formhash,
    this.email = '',
    this.mobileCountryCode = '',
    this.mobile = '',
    this.questionId = 0,
    this.questions = const [],
  });
}


class ContactProfileForm {
  final String qq;
  final int privacyQq;
  final String mobile;
  final int privacyMobile;

  const ContactProfileForm({
    this.qq = '',
    this.privacyQq = 0,
    this.mobile = '',
    this.privacyMobile = 0,
  });
}

class PasswordSecurityUpdate {
  final String oldPassword;
  final String newPassword;
  final String newPasswordConfirm;
  final String email;
  final String mobileCountryCode;
  final String mobile;
  final int questionId;
  final String answer;

  const PasswordSecurityUpdate({
    required this.oldPassword,
    this.newPassword = '',
    this.newPasswordConfirm = '',
    this.email = '',
    this.mobileCountryCode = '',
    this.mobile = '',
    this.questionId = 0,
    this.answer = '',
  });
}

class SmsCodeResult {
  final bool success;
  final String message;
  final int cooldownSeconds;

  const SmsCodeResult({
    required this.success,
    required this.message,
    this.cooldownSeconds = 0,
  });
}

class PokeOption {
  final int iconId;
  final String label;
  final String? iconUrl;

  const PokeOption({
    required this.iconId,
    required this.label,
    this.iconUrl,
  });
}

class PokePageData {
  final String formhash;
  final List<PokeOption> options;

  const PokePageData({
    required this.formhash,
    this.options = const [],
  });
}

class InviteStatusData {
  final bool canInvite;
  final String message;

  const InviteStatusData({
    required this.canInvite,
    required this.message,
  });
}

class SmsBindingData {
  final String? phone;
  final bool canUnbind;

  const SmsBindingData({
    this.phone,
    this.canUnbind = false,
  });
}

class PromotionData {
  final String username;
  final String uid;
  final String? avatarUrl;
  final String link;
  final String reward;

  const PromotionData({
    required this.username,
    required this.uid,
    this.avatarUrl,
    required this.link,
    required this.reward,
  });
}

class CreditRecord {
  final String type;
  final String delta;
  final String time;
  final String reason;
  final String raw;

  const CreditRecord({
    this.type = '',
    this.delta = '',
    this.time = '',
    this.reason = '',
    this.raw = '',
  });
}

class PmMessage {
  final String? pmid;
  final String? senderUid;
  final String content;
  final String time;
  final String date;
  final bool isMine;

  const PmMessage({
    this.pmid,
    this.senderUid,
    required this.content,
    this.time = '',
    this.date = '',
    this.isMine = false,
  });
}

class PmConversationData {
  final String touid;
  final String pmid;
  final String formhash;
  final String peerName;
  final String? peerAvatarUrl;
  final int endTimestamp;
  final List<PmMessage> messages;

  const PmConversationData({
    required this.touid,
    required this.pmid,
    required this.formhash,
    required this.peerName,
    this.peerAvatarUrl,
    required this.endTimestamp,
    this.messages = const [],
  });
}

class PmConversationSummary {
  final String touid;
  final String username;
  final String? avatarUrl;
  final String? lastMessage;
  final String? lastTime;

  const PmConversationSummary({
    required this.touid,
    required this.username,
    this.avatarUrl,
    this.lastMessage,
    this.lastTime,
  });
}


/// 单个消息入口的未读状态。
///
/// Discuz 某些模板只给出“有新消息”标记而不输出精确数字，
/// 因此 [count] 允许为空；此时 UI 使用“新”Badge，而不是伪造数量。
class UnreadBadgeInfo {
  final int? count;
  final bool hasUnread;

  const UnreadBadgeInfo({
    this.count,
    this.hasUnread = false,
  });

  const UnreadBadgeInfo.none()
      : count = 0,
        hasUnread = false;

  bool get isVisible => hasUnread || (count ?? 0) > 0;

  String? get label {
    if (!isVisible) return null;
    final value = count;
    if (value == null) return '新';
    if (value > 99) return '99+';
    return '$value';
  }
}

/// 消息中心三类入口的未读汇总。
class MessageUnreadSummary {
  final UnreadBadgeInfo privateMessages;
  final UnreadBadgeInfo notices;
  final UnreadBadgeInfo friendRequests;

  const MessageUnreadSummary({
    this.privateMessages = const UnreadBadgeInfo.none(),
    this.notices = const UnreadBadgeInfo.none(),
    this.friendRequests = const UnreadBadgeInfo.none(),
  });

  const MessageUnreadSummary.empty()
      : privateMessages = const UnreadBadgeInfo.none(),
        notices = const UnreadBadgeInfo.none(),
        friendRequests = const UnreadBadgeInfo.none();

  bool get hasUnread =>
      privateMessages.isVisible || notices.isVisible || friendRequests.isVisible;

  /// 底部导航的汇总 Badge。若存在只能确认“有新消息”但无法确认数量的
  /// 来源，则用 `N+` / `新` 表示，避免把不完整数字当成精确总数。
  String? get totalLabel {
    final entries = [privateMessages, notices, friendRequests];
    var exactTotal = 0;
    var hasUnknown = false;

    for (final entry in entries) {
      if (!entry.isVisible) continue;
      if (entry.count == null) {
        hasUnknown = true;
      } else {
        exactTotal += entry.count!;
      }
    }

    if (exactTotal <= 0 && !hasUnknown) return null;
    if (hasUnknown) {
      if (exactTotal <= 0) return '新';
      return exactTotal > 99 ? '99+' : '$exactTotal+';
    }
    return exactTotal > 99 ? '99+' : '$exactTotal';
  }
}
