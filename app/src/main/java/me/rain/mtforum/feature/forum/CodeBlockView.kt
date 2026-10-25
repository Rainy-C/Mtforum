package me.rain.mtforum.feature.forum

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.yukonga.miuix.kmp.theme.MiuixTheme

@Composable
internal fun PostCodeBlock(code: String, languageHint: String? = null) {
    val context = LocalContext.current
    val dark = MiuixTheme.colorScheme.background.red + MiuixTheme.colorScheme.background.green + MiuixTheme.colorScheme.background.blue < 1.5f
    val label = remember(code, languageHint) { CodeSyntax.detect(code, languageHint) }
    val lines = remember(code) { code.lines() }
    var expanded by remember(code) { mutableStateOf(false) }
    val canFold = lines.size > 20
    val displayed = remember(code, expanded) { if (canFold && !expanded) lines.take(20).joinToString("\n") else code }
    val highlighted = remember(displayed, label, dark) { CodeSyntax.highlight(displayed, label, dark) }
    val contentColor = MiuixTheme.colorScheme.onSurface
    val muted = MiuixTheme.colorScheme.onSurfaceVariantSummary
    Column(
        Modifier.fillMaxWidth().background(MiuixTheme.colorScheme.surface, RoundedCornerShape(16.dp))
            .padding(vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            BasicText(label.uppercase(), style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = muted))
            BasicText("复制", Modifier.clickable {
                val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                manager.setPrimaryClip(ClipData.newPlainText("MTForum $label", code))
            }, style = TextStyle(fontSize = 12.sp, color = contentColor))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (lines.size > 1) {
                val lineCount = displayed.lines().size
                val gutter = remember(lineCount) { (1..lineCount).joinToString("\n") }
                BasicText(gutter, style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                    lineHeight = 20.sp, color = muted.copy(alpha = .7f)))
            }
            SelectionContainer {
                BasicText(
                    highlighted,
                    Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                    style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                        lineHeight = 20.sp, color = contentColor),
                    softWrap = false,
                )
            }
        }
        if (canFold) {
            BasicText(
                if (expanded) "收起代码" else "展开全部 ${lines.size} 行",
                Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(vertical = 8.dp),
                style = TextStyle(color = contentColor, fontSize = 12.sp,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center),
            )
        }
    }
}
