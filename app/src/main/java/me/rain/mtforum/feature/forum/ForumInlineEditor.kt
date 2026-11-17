package me.rain.mtforum.feature.forum

import android.graphics.Color as AndroidColor
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.text.Editable
import android.text.Spanned
import android.text.TextWatcher
import android.text.style.ImageSpan
import android.view.Gravity
import android.text.InputType
import android.widget.EditText
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import coil.imageLoader
import coil.request.ImageRequest
import top.yukonga.miuix.kmp.theme.MiuixTheme

/**
 * Native Android EditText with ImageSpans.
 * Unlike a separate chip strip, these objects occupy a real cursor position,
 * take part in selection and backspace, and never delete themselves on tap.
 */
internal class ForumInlineEditorState {
    private var editor: EditText? = null
    private var savedText: String = ""
    var markup by mutableStateOf("")
        private set

    private class ForumMediaSpan(drawable: Drawable, val code: String) :
        ImageSpan(drawable, ALIGN_BASELINE)

    private val watcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        override fun afterTextChanged(s: Editable?) { sync() }
    }

    fun attach(editText: EditText) {
        if (editor === editText) return
        editor?.removeTextChangedListener(watcher)
        editor = editText
        editText.setText(savedText)
        editText.setSelection(editText.length())
        editText.addTextChangedListener(watcher)
        sync()
    }

    fun detach(editText: EditText? = editor) {
        if (editText == null || editor !== editText) return
        savedText = markup
        editText.removeTextChangedListener(watcher)
        editor = null
    }

    fun clear() {
        savedText = ""
        editor?.setText("")
        markup = ""
    }

    fun setTextIfUntouched(text: String) {
        if (markup.isNotEmpty() || text.isEmpty()) return
        editor?.setText(text)
        editor?.setSelection(editor?.length() ?: 0)
        savedText = text
        sync()
    }

    private fun encode(editable: Editable): String = buildString {
        var index = 0
        while (index < editable.length) {
            val spans = editable.getSpans(index, index + 1, ForumMediaSpan::class.java)
            val match = spans.firstOrNull {
                editable.getSpanStart(it) == index &&
                    editable.getSpanEnd(it) == index + 1
            }
            if (match != null) append(match.code)
            else if (editable[index] != '\uFFFC') append(editable[index])
            index++
        }
    }

    private fun sync() {
        editor?.editableText?.let {
            markup = encode(it)
            savedText = markup
        }
    }

    fun insertMedia(url: String, code: String, image: Boolean = false) {
        if (!url.startsWith("https://") && !url.startsWith("content://")) return
        val view = editor ?: return
        // Match the actual text size (font scale included): roughly 1.23x for
        // smileys, rather than a hardcoded 30dp that dwarfs 14sp text.
        val size = if (image) (view.textSize * 3.1f).toInt().coerceAtLeast(1)
            else (view.textSize * 1.23f).toInt().coerceAtLeast(1)
        val placeholder = ColorDrawable(AndroidColor.TRANSPARENT).apply {
            setBounds(0, 0, size, size)
        }
        val span = ForumMediaSpan(placeholder, code)
        val selectionStart = view.selectionStart.coerceAtLeast(0)
        val selectionEnd = view.selectionEnd.coerceAtLeast(0)
        val start = minOf(selectionStart, selectionEnd).coerceAtMost(view.length())
        val end = maxOf(selectionStart, selectionEnd).coerceAtMost(view.length())
        val edit = view.editableText
        edit.replace(start, end, "\uFFFC")
        edit.setSpan(span, start, start + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        view.setSelection(start + 1)
        sync()

        view.context.imageLoader.enqueue(
            ImageRequest.Builder(view.context)
                .data(url)
                .size(size * 2)
                .target(
                    onSuccess = { drawable ->
                        view.post {
                            val current = editor?.editableText ?: return@post
                            val from = current.getSpanStart(span)
                            if (from < 0 || current.getSpanEnd(span) != from + 1) return@post
                            val intrinsicW = drawable.intrinsicWidth.coerceAtLeast(1)
                            val intrinsicH = drawable.intrinsicHeight.coerceAtLeast(1)
                            val width = if (intrinsicW > intrinsicH)
                                size else (size.toFloat() * intrinsicW / intrinsicH).toInt()
                            val height = if (intrinsicH > intrinsicW)
                                size else (size.toFloat() * intrinsicH / intrinsicW).toInt()
                            drawable.setBounds(0, 0, width.coerceAtLeast(1), height.coerceAtLeast(1))
                            current.setSpan(
                                ForumMediaSpan(drawable, code), from, from + 1,
                                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                            )
                            current.removeSpan(span)
                            view.invalidate()
                            sync()
                        }
                    },
                ).build(),
        )
    }
}

@Composable
internal fun rememberForumInlineEditorState(): ForumInlineEditorState =
    remember { ForumInlineEditorState() }

@Composable
internal fun ForumInlineEditor(
    state: ForumInlineEditorState,
    modifier: Modifier = Modifier,
    hint: String,
    enabled: Boolean,
    textSizeSp: Float = 15f,
    onFocused: (() -> Unit)? = null,
) {
    val color = MiuixTheme.colorScheme.onSurface.toArgb()
    val hintColor = MiuixTheme.colorScheme.onSurfaceVariantSummary.toArgb()
    AndroidView(
        modifier = modifier,
        factory = { context ->
            EditText(context).apply {
                setBackgroundColor(AndroidColor.TRANSPARENT)
                setPadding(0, 0, 0, 0)
                setSingleLine(false)
                inputType = InputType.TYPE_CLASS_TEXT or
                    InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                    InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                gravity = Gravity.TOP or Gravity.START
                isVerticalScrollBarEnabled = false
                textSize = textSizeSp
                setTextColor(color)
                setHintTextColor(hintColor)
                setHint(hint)
                setOnFocusChangeListener { _, focused ->
                    if (focused) onFocused?.invoke()
                }
                state.attach(this)
            }
        },
        update = { view ->
            view.isEnabled = enabled
            view.textSize = textSizeSp
            view.setTextColor(color)
            view.setHintTextColor(hintColor)
            view.hint = hint
            view.setOnFocusChangeListener { _, focused ->
                if (focused) onFocused?.invoke()
            }
        },
    )
    DisposableEffect(state) {
        onDispose { state.detach() }
    }
}
