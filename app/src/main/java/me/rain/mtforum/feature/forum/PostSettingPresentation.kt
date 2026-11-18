package me.rain.mtforum.feature.forum

import me.rain.mtforum.core.network.RemoteField

/** User-facing descriptions for fields actually returned by the current board's Discuz form. */
internal object PostSettingPresentation {
    private val names = mapOf(
        "readperm" to "阅读权限",
        "price" to "主题售价（金币）",
        "usesig" to "显示个人签名",
        "allownoticeauthor" to "收到回复时通知我",
        "anonymous" to "匿名发布",
        "ordertype" to "评论排列方式",
        "stickreply" to "倒序查看回复",
        "seccodeverify" to "图片验证码",
        "secanswer" to "验证问答答案",
        "save" to "保存为草稿",
        "special" to "帖子类型",
        "notify" to "接收通知",
        "allowcomment" to "允许评论",
    )
    private val descriptions = mapOf(
        "readperm" to "0 表示公开阅读；其他权限值以论坛实际规则为准。",
        "price" to "0 表示免费。论坛可能限制设置售价的用户等级。",
        "usesig" to "发布时是否显示个人签名。",
        "allownoticeauthor" to "有人回复这篇帖子时接收通知。",
        "anonymous" to "如果板块允许，隐藏发帖人身份。",
        "seccodeverify" to "请输入上方验证码图片里的内容。",
        "secanswer" to "请输入上方验证问题的答案。",
    )

    fun isVisible(field: RemoteField): Boolean =
        field.key.isNotBlank() &&
            field.type !in setOf("hidden", "file", "submit", "button", "reset", "image") &&
            field.key !in setOf("subject", "message", "typeid", "posttime", "topicsubmit")

    fun label(field: RemoteField): String {
        names[field.key]?.let { return it }
        val label = field.label.trim()
        return label.takeIf {
            it.isNotBlank() && it != "填写内容" && it != field.key
        } ?: field.key
    }

    fun hint(field: RemoteField): String? = descriptions[field.key]
}
