package me.rain.mtforum.feature.forum

import org.junit.Assert.*
import org.junit.Test

class CodeSyntaxTest {
    @Test fun detectsCommonLanguagesAndFallsBack() {
        assertEquals("Kotlin", CodeSyntax.detect("fun main() { println(1) }"))
        assertEquals("C++", CodeSyntax.detect("#include <iostream>\nint main() {}"))
        assertEquals("Python", CodeSyntax.detect("def greet():\n    print('Hi')"))
        assertEquals("TEXT", CodeSyntax.detect("一段没有代码特征的普通文字"))
        assertEquals("JSON", CodeSyntax.detect("{}", "json"))
    }
    @Test fun highlightingNeverChangesSourceText() {
        val code = "// comment\nfun main() { println(\"Hi\") }"
        assertEquals(code, CodeSyntax.highlight(code, "Kotlin", false).text)
    }
}
