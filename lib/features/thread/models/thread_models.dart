part of '../../../models/models.dart';

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
  final String? typeId;
  final String? typeName;

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
    this.typeId,
    this.typeName,
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
    String? typeId,
    String? typeName,
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
      typeId: typeId ?? this.typeId,
      typeName: typeName ?? this.typeName,
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
  final String? lastEditTime;
  final String? lastEditor;
  final bool isOp;
  final List<String> images;
  final List<PostContent> richContent;
  final String? repquotePid;
  final String? replyToName;
  final String? replyToTime;
  final String? replyQuoteText;
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
    this.lastEditTime,
    this.lastEditor,
    this.isOp = false,
    this.images = const [],
    this.richContent = const [],
    this.repquotePid,
    this.replyToName,
    this.replyToTime,
    this.replyQuoteText,
    this.hiddenHint,
    this.page = 1,
  });
}

class ThreadDetail {
  final String tid;
  final String title;
  final List<Post> posts;
  final String? replyCount;
  final String? likeCount;
  final String? viewCount;
  final String formhash;
  final String noticeauthor;
  final String fid;
  final int page;
  final String currentUid;

  const ThreadDetail({
    required this.tid,
    required this.title,
    required this.posts,
    this.replyCount,
    this.likeCount,
    this.viewCount,
    required this.formhash,
    required this.noticeauthor,
    required this.fid,
    required this.page,
    this.currentUid = '',
  });
}

class ThreadTypeOption {
  final String id;
  final String name;

  const ThreadTypeOption({
    required this.id,
    required this.name,
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
  final List<String> attachmentAids;
  final List<ThreadTypeOption> threadTypes;
  final String selectedTypeId;

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
    this.attachmentAids = const [],
    this.threadTypes = const [],
    this.selectedTypeId = '',
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
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrikethrough;
  final String? color;
  final String? backgroundColor;
  final String? fontFamily;
  final double? fontSizeScale;
  final String? alignment;
  final String? listType;

  const PostContent._({
    required this.type,
    required this.text,
    this.url,
    this.tableRows = const [],
    this.tableHeaderRows = 0,
    this.children = const [],
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.color,
    this.backgroundColor,
    this.fontFamily,
    this.fontSizeScale,
    this.alignment,
    this.listType,
  });

  factory PostContent.text(String t) =>
      PostContent._(type: PostContentType.text, text: t);

  factory PostContent.bold(String t) =>
      PostContent._(type: PostContentType.bold, text: t, isBold: true);

  factory PostContent.inline(
    String t, {
    String? url,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
    String? color,
    String? backgroundColor,
    String? fontFamily,
    double? fontSizeScale,
  }) =>
      PostContent._(
        type: url == null ? PostContentType.text : PostContentType.link,
        text: t,
        url: url,
        isBold: bold,
        isItalic: italic,
        isUnderline: underline,
        isStrikethrough: strikethrough,
        color: color,
        backgroundColor: backgroundColor,
        fontFamily: fontFamily,
        fontSizeScale: fontSizeScale,
      );

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

  factory PostContent.divider() =>
      const PostContent._(type: PostContentType.divider, text: '');

  factory PostContent.aligned(
    List<PostContent> children, {
    required String alignment,
  }) =>
      PostContent._(
        type: PostContentType.aligned,
        text: '',
        children: List<PostContent>.unmodifiable(children),
        alignment: alignment,
      );

  factory PostContent.list(
    List<PostContent> children, {
    String type = '',
  }) =>
      PostContent._(
        type: PostContentType.list,
        text: '',
        children: List<PostContent>.unmodifiable(children),
        listType: type,
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
  divider,
  aligned,
  list,
}
