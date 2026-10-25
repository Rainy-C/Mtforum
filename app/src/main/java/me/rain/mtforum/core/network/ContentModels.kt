package me.rain.mtforum.core.network

/** Server-backed content. Missing statistics stay unknown rather than becoming zero. */
data class Topic(
    val id: String,
    val title: String,
    val url: String,
    val author: String = "",
    val authorUrl: String? = null,
    val avatar: String? = null,
    val forum: String = "",
    val time: String = "",
    val excerpt: String = "",
    val replies: String? = null,
    val views: String? = null,
    val likes: String? = null,
    val images: List<String> = emptyList(),
    val hasImageAttachments: Boolean = false,
    val hasHiddenContent: Boolean = false,
)

data class ForumBoard(
    val id: String,
    val title: String,
    val group: String,
    val summary: String = "",
    val todayPosts: String? = null,
)

data class ContentLink(val text: String, val url: String)

data class ContentPost(
    val id: String,
    val author: String,
    val authorUrl: String?,
    val avatar: String?,
    val time: String,
    val floor: String,
    val html: String,
    val images: List<String>,
    val links: List<ContentLink>,
)

data class TopicDetail(
    val title: String,
    val tid: String,
    val fid: String,
    val posts: List<ContentPost>,
    val next: String?,
    val previous: String?,
    val formhash: String?,
)

data class FieldOption(val label: String, val value: String)

data class RemoteField(
    val key: String,
    val label: String,
    val type: String,
    val value: String,
    val required: Boolean = false,
    val checked: Boolean = false,
    val options: List<FieldOption> = emptyList(),
    val maxLength: Int? = null,
    val readOnly: Boolean = false,
)

data class RemoteSubmit(
    val label: String,
    val name: String,
    val value: String,
    val url: String? = null,
    val method: String? = null,
)

data class RemoteForm(
    val id: String,
    val url: String,
    val method: String,
    val multipart: Boolean,
    val fields: List<RemoteField>,
    val submits: List<RemoteSubmit>,
    val upload: UploadConfig? = null,
    val captchaImages: List<String> = emptyList(),
    val referer: String = url,
)

enum class NativeContentKind {
    Text, Navigation, Person, Thread, Notice, Product, Rank, Facts, CreditRecord, UserGroup
}

data class ContentFact(val label: String, val value: String)

/** Presentation data extracted only from the forum's real list row (never generated counts). */
data class FeedListMeta(
    val author: String = "",
    val authorUrl: String? = null,
    val avatar: String? = null,
    val time: String = "",
    val forum: String = "",
    val likes: String? = null,
    val replies: String? = null,
    val views: String? = null,
)

data class ContentBlock(
    val text: String,
    val title: String = "",
    val image: String? = null,
    val links: List<ContentLink> = emptyList(),
    val kind: NativeContentKind = NativeContentKind.Text,
    val facts: List<ContentFact> = emptyList(),
    val rank: Int? = null,
    val primaryLink: ContentLink? = null,
    val hasHiddenContent: Boolean = false,
    val feedMeta: FeedListMeta? = null,
)

data class NativeDocument(
    val title: String,
    val url: String,
    val blocks: List<ContentBlock>,
    val forms: List<RemoteForm>,
    val next: String? = null,
    val previous: String? = null,
    val formhash: String? = null,
    val signedToday: Boolean? = null,
)

data class ForumUpload(
    val name: String,
    val filename: String,
    val type: String,
    val bytes: ByteArray,
)

data class UploadConfig(val uid: String, val hash: String, val maxBytes: Int)

data class ConversationSummary(
    val uid: String,
    val name: String,
    val avatar: String?,
    val text: String,
    val time: String,
    val unread: Boolean,
)

data class ChatMessage(
    val text: String,
    val time: String,
    val mine: Boolean,
    val images: List<String>,
)

data class Conversation(
    val peer: String,
    val name: String,
    val pmid: String,
    val formhash: String,
    val messages: List<ChatMessage>,
)
