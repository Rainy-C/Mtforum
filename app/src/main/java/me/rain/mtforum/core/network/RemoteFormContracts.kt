package me.rain.mtforum.core.network

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.jsoup.nodes.Element

/** Restore fields displaced by malformed mobile markup; use known Discuz submit contracts. */
internal object RemoteFormContracts {
    /** keke_integralmall's popup uses JavaScript POST rather than an HTML form. */
    fun mallConfirmation(doc: Element, page: String): RemoteForm? {
        val url = page.toHttpUrlOrNull() ?: return null
        if (url.queryParameter("id") != "keke_integralmall:show_win" &&
            !url.encodedPath.contains("keke_integralmall-show_win")) return null
        if (url.queryParameter("ac") != "xd") return null
        val tid = url.queryParameter("tid")?.takeIf { it.toLongOrNull() != null } ?: return null
        val hash = url.queryParameter("formhash") ?: ForumParser.formhash(doc.outerHtml()) ?: return null
        val text = doc.text()
        if (Regex("抱歉|余额不足|无权|未登录|售罄").containsMatchIn(text)) return null
        // Require the actual confirmation popup, not merely a URL that resembles one.
        if (!Regex("兑换|购买|收货").containsMatchIn(text)) return null
        val fields = mutableListOf(
            RemoteField("formhash", "formhash", "hidden", hash),
            RemoteField("ac", "ac", "hidden", "xd"),
            RemoteField("tid", "tid", "hidden", tid),
        )
        val address = doc.select("input[name], textarea[name]").firstOrNull { it.attr("name") == "addr" }
        fields += RemoteField("addr", "收货信息", if (address == null) "hidden" else "textarea",
            address?.let { if (it.tagName() == "textarea") it.wholeText() else it.attr("value") }.orEmpty(),
            address?.hasAttr("required") == true)
        return RemoteForm("mall-exchange", "${ForumRepository.BaseUrl}/plugin.php?id=keke_integralmall:actions",
            "POST", false, fields, listOf(RemoteSubmit("确认兑换", "", "")), referer = page)
    }

    fun recover(doc: Element, page: String, pageHash: String?) {
        val url = page.toHttpUrlOrNull() ?: return
        val editor = url.queryParameter("mod") == "post" &&
            url.queryParameter("action") in setOf("newthread", "reply", "edit")
        val profile = url.queryParameter("mod") == "spacecp" && url.queryParameter("ac") == "profile"
        val controls = doc.select("input[name], textarea[name], select[name]")
        if (!editor && !profile) return
        val expected = if (editor) setOf("subject", "message") else setOf(
            "realname", "gender", "sightml", "bio", "qq", "mobile", "oldpassword", "emailnew"
        )
        val primary = controls.firstOrNull { it.attr("name") in expected } ?: return
        val hash = pageHash ?: ForumParser.formhash(doc.outerHtml()) ?: return
        val form = primary.closest("form")
            ?: doc.selectFirst(if (editor) "form#postform" else "form#profileform")
            ?: doc.appendElement("form").attr("id", if (editor) "postform" else "profileform")
                .attr("action", page).attr("method", "POST")
        controls.filter { it.closest("form") == null && !it.hasAttr("form") }
            .filter { control ->
                val key = control.attr("name")
                if (editor) key in setOf(
                    "formhash", "posttime", "fid", "tid", "pid", "page", "subject", "message",
                    "typeid", "usesig", "allownoticeauthor", "delete", "readperm", "price"
                ) || key.startsWith("attachnew[")
                else key in setOf(
                    "formhash", "realname", "gender", "birthyear", "birthmonth", "birthday",
                    "resideprovince", "residecity", "occupation", "sightml", "bio", "qq", "mobile",
                    "oldpassword", "newpassword", "newpassword2", "emailnew", "questionidnew",
                    "answernew", "secmobiccnew", "secmobilenew"
                ) || key.startsWith("privacy[")
            }.forEach { control ->
                if (form.select("input[name], textarea[name], select[name]")
                        .none { it.attr("name") == control.attr("name") }) form.appendChild(control.clone())
            }
        if (form.select("input[name]").none { it.attr("name") == "formhash" })
            form.appendElement("input").attr("type", "hidden").attr("name", "formhash").attr("value", hash)
    }

    fun complete(form: RemoteForm, pageHash: String?): RemoteForm {
        val url = form.url.toHttpUrlOrNull() ?: return form
        val referer = form.referer.toHttpUrlOrNull()
        val keys = form.fields.map { it.key }.toSet()
        val fields = form.fields.toMutableList()
        val submittedKeys = keys + form.submits.map { it.name }
        fun hidden(key: String, value: String) {
            if (key !in submittedKeys) fields += RemoteField(key, key, "hidden", value)
        }
        var method = form.method
        if (url.queryParameter("mod") == "post" && "message" in keys) {
            method = "POST"
            when (url.queryParameter("action")) {
                "reply" -> hidden("replysubmit", "yes")
                "newthread" -> hidden("topicsubmit", "yes")
                "edit" -> hidden("editsubmit", "yes")
            }
        }
        if (url.queryParameter("ac") == "profile" &&
            keys.any { it in setOf("realname", "gender", "sightml", "bio", "qq", "mobile", "oldpassword", "emailnew") }) {
            method = "POST"
            if ("oldpassword" in keys || referer?.queryParameter("op") == "password") hidden("passwordsubmit", "true")
            else {
                hidden("profilesubmit", "true")
                hidden("profilesubmitbtn", "true")
            }
        }
        if (method == "POST" && pageHash != null) hidden("formhash", pageHash)
        return form.copy(method = method, fields = fields.map { field ->
            if (field.key in setOf("message", "oldpassword") || field.key == "subject" && url.queryParameter("action") == "newthread")
                field.copy(required = true) else field
        })
    }
}
