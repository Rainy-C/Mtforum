package me.rain.mtforum.feature.forum

import android.graphics.Canvas
import android.graphics.Paint
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
    private var savedSelectionStart: Int = 0
    private var savedSelectionEnd: Int = 0
    var markup by mutableStateOf("")
        private set

    private class ForumMediaSpan(drawable: Drawable, val code: String) :
        ImageSpan(drawable, ALIGN_BOTTOM) {
        override fun getSize(
            paint: Paint, text: CharSequence?, start: Int, end: Int,
            fm: Paint.FontMetricsInt?,
        ): Int {
            val metrics = paint.fontMetricsInt
            if (fm != null) {
                val center = (metrics.ascent + metrics.descent) / 2
                val upper = center - drawable.bounds.height() / 2
                val lower = upper + drawable.bounds.height()
                fm.ascent = minOf(metrics.ascent, upper)
                fm.descent = maxOf(metrics.descent, lower)
                fm.top = minOf(metrics.top, fm.ascent)
                fm.bottom = maxOf(metrics.bottom, fm.descent)
            }
            return drawable.bounds.width()
        }

        override fun draw(
            canvas: Canvas, text: CharSequence?, start: Int, end: Int,
            x: Float, top: Int, y: Int, bottom: Int, paint: Paint,
        ) {
            val checkpoint = canvas.save()
            val metrics = paint.fontMetricsInt
            val offset = (metrics.ascent + metrics.descent - drawable.bounds.height()) / 2f
            canvas.translate(x, y + offset)
            drawable.draw(canvas)
            canvas.restoreToCount(checkpoint)
        }
    }

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
        editText.setSelection(
            savedSelectionStart.coerceIn(0, editText.length()),
            savedSelectionEnd.coerceIn(0, editText.length()),
        )
        editText.addTextChangedListener(watcher)
        sync()
    }

    fun detach(editText: EditText? = editor) {
        if (editText == null || editor !== editText) return
        val content = editText.editableText
        // Text and BBCode indices match unless an image span is present.
        // For rich text we conservatively keep the cursor at the end after
        // a recycle rather than let a raw BBCode expansion shift it wrongly.
        val containsMedia = content.getSpans(
            0, content.length, ForumMediaSpan::class.java
        ).isNotEmpty()
        savedText = markup
        savedSelectionStart = if (containsMedia) markup.length
            else editText.selectionStart.coerceIn(0, markup.length)
        savedSelectionEnd = if (containsMedia) markup.length
            else editText.selectionEnd.coerceIn(0, markup.length)
        editText.removeTextChangedListener(watcher)
        editor = null
    }

    fun clear() {
        savedText = ""
        savedSelectionStart = 0
        savedSelectionEnd = 0
        editor?.setText("")
        markup = ""
    }

    private fun editDetached(prefix: String, suffix: String = "", replaceSelection: Boolean = false) {
        val start = minOf(savedSelectionStart, savedSelectionEnd).coerceIn(0, savedText.length)
        val end = maxOf(savedSelectionStart, savedSelectionEnd).coerceIn(start, savedText.length)
        val chosen = if (replaceSelection) savedText.substring(start, end) else ""
        val insertion = prefix + chosen + suffix
        savedText = savedText.replaceRange(start, end, insertion)
        val cursor = if (replaceSelection) {
            if (end == start) start + prefix.length else start + insertion.length
        } else start + insertion.length
        savedSelectionStart = cursor
        savedSelectionEnd = cursor
        markup = savedText
    }

    /** Restore the plain BBCode text saved for a new thread draft. */
    fun restoreDraft(text: String) {
        if (markup.isNotBlank() || text.isBlank()) return
        savedText = text
        savedSelectionStart = text.length
        savedSelectionEnd = text.length
        editor?.setText(text)
        editor?.setSelection(editor?.length() ?: 0)
        markup = text
    }

    /** Insert text at the actual selection, not at the end of the document. */
    fun insertText(text: String) {
        val view = editor
        if (view == null) {
            editDetached(text)
            return
        }
        val from = minOf(view.selectionStart, view.selectionEnd).coerceAtLeast(0)
        val to = maxOf(view.selectionStart, view.selectionEnd).coerceAtLeast(0)
        view.editableText.replace(from, to, text)
        view.setSelection(from + text.length)
        sync()
    }

    /** Wrap selection in BBCode while preserving embedded ImageSpans. */
    fun wrapSelection(prefix: String, suffix: String) {
        val view = editor
        if (view == null) {
            editDetached(prefix, suffix, replaceSelection = true)
            return
        }
        val from = minOf(view.selectionStart, view.selectionEnd).coerceAtLeast(0)
        val to = maxOf(view.selectionStart, view.selectionEnd).coerceAtLeast(0)
        val content = view.editableText
        content.insert(to, suffix)
        content.insert(from, prefix)
        view.setSelection(
            if (to == from) from + prefix.length else to + prefix.length + suffix.length,
        )
        sync()
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
        val view = editor
        if (view == null) {
            editDetached(code)
            return
        }
        // Match the actual text size (font scale included): roughly 1.23x for
        // smileys, rather than a hardcoded 30dp that dwarfs 14sp text.
        val size = if (image) (view.textSize * 3.1f).toInt().coerceAtLeast(1)
            else (view.textSize * 1.12f).toInt().coerceAtLeast(1)
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
    centerSingleLine: Boolean = false,
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
                includeFontPadding = false
                inputType = InputType.TYPE_CLASS_TEXT or
                    InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                    InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                gravity = (if (centerSingleLine) Gravity.CENTER_VERTICAL else Gravity.TOP) or Gravity.START
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
            // LazyColumn can recycle the AndroidView while the composer state stays
            // alive. A previously disposed editor must never own the new view.
            // Reattach also applies BBCode inserted while the editor was offscreen.
            state.attach(view)
            view.isEnabled = enabled
            view.textSize = textSizeSp
            view.setTextColor(color)
            view.setHintTextColor(hintColor)
            view.hint = hint
            view.gravity = (if (centerSingleLine) Gravity.CENTER_VERTICAL else Gravity.TOP) or Gravity.START
            view.setOnFocusChangeListener { _, focused ->
                if (focused) onFocused?.invoke()
            }
        },
        onRelease = { releasedView ->
            // Release exactly this view, not a newly attached instance.
            state.detach(releasedView)
        },
    )
}
