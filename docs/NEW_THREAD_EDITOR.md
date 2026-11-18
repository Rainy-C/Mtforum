# 原生发帖编辑器

参考接口行为与验证流程：<https://github.com/qcxs/mtbbs_app>，主要阅读：
- `lib/api/forum/post/http.dart`
- `lib/api/forum/post/export.dart`
- `lib/core/parser/page_fetcher.dart`
- `lib/api/forum/seccode/`
- `lib/api/forum/secqaa/`

项目使用 Kotlin + Compose 实现，未移植 Flutter UI 或复制其源文件。

## 页面路径

由板块页面的“发帖”按钮打开 `forum.php?mod=post&action=newthread&fid=<板块ID>&mobile=2`，在 `HomeScreen` 路由 `newthread` 中使用 `NewThreadScreen`，而非通用 `NativeForm`。

## 发帖协议

1. GET 当前板块的发帖页，以当前论坛 Cookie 获取实际表单、`formhash`、`posttime`、`typeid` 与可选设置。
2. 如存在验证码或验证问答占位标签，恢复 hash 与输入字段，按官方 `misc.php?action=update` 接口获取题面或图片。图片必须使用服务端下发的 update 令牌，不能自己推算。
3. 图片使用论坛返回的 upload hash/uid 上传，取得 aid 后在正文当前位置插入 `[attachimg]aid[/attachimg]`。
4. POST `forum.php?mod=post&action=newthread&fid=...&topicsubmit=yes&inajax=1`，提交所有实际表单字段、BBCode 正文和 `attachnew[aid][description]`。
5. 只有服务器明确表示成功或跳转到正常帖子页才清除草稿并刷新板块。无法确认的响应不自动重试，避免重复发表。

## 编辑体验

- 标题、服务器返回的主题分类与附加字段
- 光标位置插入 BBCode、行内表情和图片，支持正文预览
- 按板块私有保存标题和正文草稿，不保存凭据或验证答案
- 成功状态页可打开新帖，退出时返回原板块

## 测试限制

编译通过不代表论坛端真实发表验证通过。特别需要真机测试：有/无验证码板块、上传附件、长正文、隐藏内容、重复发布保护。没有使用用户账户进行真实发帖或扣费操作。

## 0.4.8 帖子式预览

预览不使用 WebView，也不提交任何内容。NewThreadScreen 保留原 ForumInlineEditorState，
只切换到 ThreadDraftPreview。它构造未发布的 ContentPost，调用真实的
ThreadPostCard 和 RichPostBody 显示内容，不包含虚构的点赞数、评论数或奖励。
ThreadDraftPreviewContent 将普通正文换行映射到 HTML br 标签，但保留 pre 代码块原始换行。
返回编辑（包括系统返回键）复用原草稿，不重新读取表单。
已上传附件 ID 在本地只可显示占位符，正式附件 URL 由论坛服务端解析。
