package me.rain.mtforum.feature.forum

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle

/** Fast, bounded lexer. Works offline, never executes untrusted forum code. */
internal object CodeSyntax {
    private val sourceKeywords = setOf(
        "abstract", "and", "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "data", "def", "default", "delete", "do", "else", "enum", "except", "export", "extends",
        "false", "final", "finally", "for", "from", "fun", "function", "if", "implements", "import", "in",
        "include", "inline", "instanceof", "interface", "internal", "is", "let", "namespace", "new", "nil",
        "null", "object", "override", "package", "private", "protected", "public", "return", "static",
        "struct", "super", "suspend", "switch", "this", "throw", "throws", "true", "try", "type", "typedef",
        "using", "val", "var", "virtual", "void", "when", "where", "while", "yield", "SELECT", "FROM",
        "WHERE", "JOIN", "ORDER", "INSERT", "UPDATE", "DELETE", "CREATE", "TABLE", "AND", "OR",
    )
    private val tokens = Regex("""(?s)/\*.*?\*/|//[^\r\n]*|#[^\r\n]*|(?:\"\"\".*?\"\"\")|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|\b\d+(?:\.\d+)?\b|\b[\p{L}_][\p{L}\p{N}_]*\b""")

    fun detect(code: String, hint: String? = null): String {
        val given = hint?.trim()?.lowercase().orEmpty()
        val known = mapOf("kt" to "Kotlin", "kotlin" to "Kotlin", "java" to "Java", "py" to "Python",
            "python" to "Python", "js" to "JavaScript", "javascript" to "JavaScript", "ts" to "TypeScript",
            "c" to "C", "cpp" to "C++", "c++" to "C++", "sh" to "Shell", "bash" to "Shell",
            "json" to "JSON", "html" to "HTML", "xml" to "XML", "css" to "CSS", "sql" to "SQL",
            "smali" to "Smali", "dex" to "Smali")
        val sample = code.take(4096)
        // Strong format signatures override wrong forum template hints.
        // Some Discuz code containers advertise Python for a Java sample.
        val javaSource = Regex(
            """(?m)^\s*package\s+[\w.]+\s*;|^\s*import\s+[\w.*]+\s*;|\bpublic\s+(?:final\s+)?class\s+\w+"""
        ).findAll(sample).count() >= 2
        val smaliSource = Regex("""(?m)^\s*\.(?:class|super|method|field|locals|registers)\b""")
            .findAll(sample).count() >= 2
        if (smaliSource) return "Smali"
        if (javaSource) return "Java"
        known[given]?.let { return it }
        return when {
            Regex("""(?m)^\s*\.(?:class|method|super)\b""")
                .containsMatchIn(sample) && ".end method" in sample -> "Smali"
            "#include" in sample || "std::" in sample -> "C++"
            Regex("""\bfun\s+\w+\s*\(|\bval\s+\w+\s*=|\bdata\s+class\b""").containsMatchIn(sample) -> "Kotlin"
            Regex("""\bpublic\s+static\s+void\s+main\b|\bSystem\.out\.""").containsMatchIn(sample) -> "Java"
            Regex("""(?m)^\s*(def |from \w+ import |import \w+|print\()""").containsMatchIn(sample) -> "Python"
            Regex("""(?m)^#!.*(?:sh|bash)|\b(?:sudo|apt|grep|echo|chmod)\s+""").containsMatchIn(sample) -> "Shell"
            Regex("""(?i)\b(?:SELECT|INSERT|UPDATE|CREATE TABLE)\b.*\b(?:FROM|INTO|SET|TABLE)\b""").containsMatchIn(sample) -> "SQL"
            Regex("""^\s*[\[{]\s*[\"{]""").containsMatchIn(sample) && ":" in sample -> "JSON"
            Regex("""(?i)<(?:!doctype\s+html|html|div|span|p|body|head)\b""").containsMatchIn(sample) -> "HTML"
            Regex("""(?i)<\?xml\b""").containsMatchIn(sample) -> "XML"
            Regex("""\b(?:const|let)\s+\w+|console\.log\(|=>""").containsMatchIn(sample) -> "JavaScript"
            Regex("""\b(?:int|char|printf|malloc)\b.*[();]""").containsMatchIn(sample) -> "C"
            else -> "TEXT"
        }
    }

    private val smaliTokens = Regex(
        """(?m)#[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?<!\w)\.(?:class|super|source|implements|field|method|end|locals|registers|annotation|prologue|line|param|catch|array-data|packed-switch|sparse-switch)\b|(?<![\w])(?:invoke-[\w/-]+|move[\w/-]*|const[\w/-]*|iget[\w/-]*|iput[\w/-]*|sget[\w/-]*|sput[\w/-]*|return[\w/-]*|if-[\w/-]+|goto[\w/-]*|new-instance|check-cast|packed-switch|sparse-switch)\b|(?<!\w):[A-Za-z_][\w]*|\b(?:[vp]\d+|-?\d+)\b"""
    )

    private fun highlightSmali(code: String, dark: Boolean): AnnotatedString {
        val directive = if (dark) Color(0xFFCCA8F0) else Color(0xFF7857B7)
        val instruction = if (dark) Color(0xFF98BDE9) else Color(0xFF3065A5)
        val constant = if (dark) Color(0xFFE5BF89) else Color(0xFFAC6A24)
        val comments = if (dark) Color(0xFF888E9B) else Color(0xFF858A94)
        return buildAnnotatedString {
            var cursor = 0
            smaliTokens.findAll(code).forEach { token ->
                if (token.range.first < cursor) return@forEach
                append(code.substring(cursor, token.range.first))
                val v = token.value
                val tint = when {
                    v.startsWith("#") -> comments
                    v.startsWith(".") -> directive
                    v.startsWith("\"") || v.startsWith("'") -> constant
                    v.startsWith(":") -> instruction
                    v.first().isDigit() || v.first() == '-' ||
                        Regex("""^[vp]\d+$""").matches(v) -> constant
                    else -> instruction
                }
                withStyle(SpanStyle(color = tint)) { append(v) }
                cursor = token.range.last + 1
            }
            append(code.substring(cursor))
        }
    }

    fun highlight(code: String, language: String, dark: Boolean): AnnotatedString {
        if (code.length > 60000 || language == "TEXT") return AnnotatedString(code)
        if (language.equals("Smali", true)) return highlightSmali(code, dark)
        val keyword = if (dark) Color(0xFFBCA4E8) else Color(0xFF7A4FA2)
        val string = if (dark) Color(0xFFA9D69C) else Color(0xFF357547)
        val comment = if (dark) Color(0xFF92989C) else Color(0xFF81868B)
        val number = if (dark) Color(0xFFE9B77D) else Color(0xFFAD611A)
        return buildAnnotatedString {
            var cursor = 0
            tokens.findAll(code).forEach { match ->
                if (match.range.first < cursor) return@forEach
                append(code.substring(cursor, match.range.first))
                val value = match.value
                val style = when {
                    value.startsWith("//") || value.startsWith("/*") || value.startsWith('#') && language != "C++" -> comment
                    value.startsWith('"') || value.startsWith('\'') -> string
                    value[0].isDigit() -> number
                    value in sourceKeywords -> keyword
                    else -> null
                }
                if (style != null) withStyle(SpanStyle(color = style)) { append(value) }
                else append(value)
                cursor = match.range.last + 1
            }
            append(code.substring(cursor))
        }
    }
}
