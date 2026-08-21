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
  });

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

/// 保留富文本模型，后续逐步恢复富文本渲染。
/// 当前重构版正文首先保证“可见、可复制、稳定”，图片单独渲染。
class PostContent {
  final PostContentType type;
  final String text;
  final String? url;

  const PostContent._({
    required this.type,
    required this.text,
    this.url,
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
}

enum PostContentType {
  text,
  bold,
  link,
  image,
  emoji,
  quote,
  code,
  audio,
  video,
  flash,
  free,
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
  final String? forumName;
  final String? postTime;
  final String? excerpt;

  const SearchResult({
    required this.tid,
    this.title,
    this.authorUid,
    this.authorName,
    this.forumName,
    this.postTime,
    this.excerpt,
  });
}

class LoginResult {
  final bool success;
  final String message;

  const LoginResult({required this.success, required this.message});
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
      followUrl: followUrl ?? this.followUrl,
      friendUrl: friendUrl,
      pokeUrl: pokeUrl,
      messageUrl: messageUrl,
      reportUrl: reportUrl,
    );
  }
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

