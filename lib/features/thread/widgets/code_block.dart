part of '../thread_detail_page.dart';

class _CodeBlock extends StatelessWidget {
  final String code;

  const _CodeBlock({
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final language = _CodeSyntax.detect(code);
    final languageColor = _CodeSyntax.languageColor(
      language,
      theme.brightness,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 6, 5),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: languageColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  language.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '复制代码',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: code),
                    );

                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('代码已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              _CodeSyntax.highlight(
                code,
                language: language,
                context: context,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.48,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeLanguage {
  final String id;
  final String label;

  const _CodeLanguage(this.id, this.label);
}

class _CodeSyntax {
  static const _plain = _CodeLanguage('plain', '代码');
  static const _cpp = _CodeLanguage('cpp', 'C / C++');
  static const _java = _CodeLanguage('java', 'Java');
  static const _kotlin = _CodeLanguage('kotlin', 'Kotlin');
  static const _dart = _CodeLanguage('dart', 'Dart');
  static const _python = _CodeLanguage('python', 'Python');
  static const _shell = _CodeLanguage('shell', 'Shell');
  static const _javascript = _CodeLanguage('javascript', 'JavaScript');
  static const _typescript = _CodeLanguage('typescript', 'TypeScript');
  static const _rust = _CodeLanguage('rust', 'Rust');
  static const _go = _CodeLanguage('go', 'Go');
  static const _json = _CodeLanguage('json', 'JSON');
  static const _xml = _CodeLanguage('xml', 'HTML / XML');
  static const _sql = _CodeLanguage('sql', 'SQL');
  static const _smali = _CodeLanguage('smali', 'Smali');

  static _CodeLanguage detect(String code) {
    final text = code.trim();
    final lower = text.toLowerCase();

    if (text.isEmpty) {
      return _plain;
    }

    if (RegExp(
      r'(^|\n)\s*\.(?:class|super|method|end method|locals|registers)\b'
      r'|invoke-(?:virtual|static|direct)'
      r'|Landroid/',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(text)) {
      return _smali;
    }

    if (RegExp(
      r'(^|\n)\s*#!\s*/(?:usr/)?bin/(?:ba)?sh\b'
      r'|(^|\n)\s*(?:git\s+clone|npx|npm|pnpm|yarn|curl|wget|adb|fastboot|flutter|dart|python(?:3)?|pip(?:3)?|docker|cargo|gradle|\.\/gradlew)\b'
      r'|\b(?:apt|apk|yum|dnf|pacman)\s+(?:install|update)\b'
      r'|\bexport\s+[A-Za-z_][A-Za-z0-9_]*='
      r'|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(text)) {
      return _shell;
    }

    if (RegExp(
      r'\bfun\s+[A-Za-z_]\w*\s*\('
      r'|\b(?:val|var)\s+[A-Za-z_]\w*'
      r'|\boverride\s+fun\b'
      r'|\bdata\s+class\b',
    ).hasMatch(text)) {
      return _kotlin;
    }

    if (lower.contains('package:flutter/') ||
        (RegExp(r'\bWidget\s+build\s*\(').hasMatch(text) &&
            RegExp(r'\b(?:final|const)\s+[A-Za-z_]\w*\s*=').hasMatch(text))) {
      return _dart;
    }

    if (RegExp(
      r'\bpublic\s+(?:final\s+)?class\b'
      r'|\bstatic\s+void\s+main\s*\('
      r'|\bimport\s+java\.',
    ).hasMatch(text)) {
      return _java;
    }

    if (RegExp(
      r'^\s*#include\s*[<"]'
      r'|\bstd::'
      r'|\b(?:int|void)\s+main\s*\('
      r'|\b(?:printf|cout|cin)\b',
      multiLine: true,
    ).hasMatch(text)) {
      return _cpp;
    }

    if (RegExp(
      r'\bfn\s+main\s*\('
      r'|\blet\s+mut\b'
      r'|\bprintln!\s*\('
      r'|\buse\s+std::',
    ).hasMatch(text)) {
      return _rust;
    }

    if (RegExp(
      r'(^|\n)\s*package\s+main\b'
      r'|\bfunc\s+main\s*\('
      r'|\bfmt\.(?:Print|Printf|Println)\b',
      multiLine: true,
    ).hasMatch(text)) {
      return _go;
    }

    if (RegExp(
      r'\binterface\s+[A-Za-z_]\w*'
      r'|\btype\s+[A-Za-z_]\w*\s*='
      r'|:\s*(?:string|number|boolean|unknown|never)\b',
    ).hasMatch(text)) {
      return _typescript;
    }

    if (RegExp(
      r'\b(?:const|let)\s+[A-Za-z_$][\w$]*\s*='
      r'|=>'
      r'|\bconsole\.(?:log|error|warn)\s*\('
      r'|\bfunction\s+[A-Za-z_$][\w$]*\s*\(',
    ).hasMatch(text)) {
      return _javascript;
    }

    if (RegExp(
      r'''(^|\n)\s*(?:def|class)\s+[A-Za-z_]\w*|\bif\s+__name__\s*==\s*["']__main__["']|(^|\n)\s*from\s+[A-Za-z_.]+\s+import\s+''',
      multiLine: true,
    ).hasMatch(text)) {
      return _python;
    }

    if (RegExp(
      r'^\s*<\??(?:!doctype|html|[A-Za-z_][\w:.-]*)'
      r'|</[A-Za-z_][\w:.-]*>',
      caseSensitive: false,
    ).hasMatch(text)) {
      return _xml;
    }

    if (RegExp(r'^\s*[\{\[]').hasMatch(text) &&
        RegExp(r'"[^"]+"\s*:').hasMatch(text)) {
      return _json;
    }

    if (RegExp(
      r'\bselect\b[\s\S]+\bfrom\b'
      r'|\binsert\s+into\b'
      r'|\bupdate\b[\s\S]+\bset\b'
      r'|\bcreate\s+table\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return _sql;
    }

    return _plain;
  }

  static Color languageColor(
    _CodeLanguage language,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;

    return switch (language.id) {
      'cpp' => dark ? const Color(0xFF76D7FF) : const Color(0xFF00658A),
      'java' => dark ? const Color(0xFFFFB77A) : const Color(0xFF8B4B00),
      'kotlin' => dark ? const Color(0xFFC7A7FF) : const Color(0xFF6541A5),
      'dart' => dark ? const Color(0xFF67D9E8) : const Color(0xFF006874),
      'python' => dark ? const Color(0xFFFFD86B) : const Color(0xFF745B00),
      'shell' => dark ? const Color(0xFF8DDA91) : const Color(0xFF246A2B),
      'javascript' => dark ? const Color(0xFFFFD54F) : const Color(0xFF705D00),
      'typescript' => dark ? const Color(0xFF82B8FF) : const Color(0xFF245EA7),
      'rust' => dark ? const Color(0xFFFFA87A) : const Color(0xFF8E3D12),
      'go' => dark ? const Color(0xFF70D7E8) : const Color(0xFF00677A),
      'json' => dark ? const Color(0xFFC5E478) : const Color(0xFF516A00),
      'xml' => dark ? const Color(0xFFFF9EC1) : const Color(0xFF9B345F),
      'sql' => dark ? const Color(0xFFB8C7FF) : const Color(0xFF40558D),
      'smali' => dark ? const Color(0xFFFF8F8F) : const Color(0xFF9D2C2C),
      _ => dark ? const Color(0xFF9DA7B7) : const Color(0xFF5F6876),
    };
  }

  static TextSpan highlight(
    String code, {
    required _CodeLanguage language,
    required BuildContext context,
  }) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final keywordColor =
        dark ? const Color(0xFF82B1FF) : const Color(0xFF245EA7);
    final stringColor =
        dark ? const Color(0xFFC3E88D) : const Color(0xFF4F6D00);
    final commentColor =
        dark ? const Color(0xFF788493) : const Color(0xFF727B88);
    final numberColor =
        dark ? const Color(0xFFFFA07A) : const Color(0xFF9A471F);
    final annotationColor =
        dark ? const Color(0xFFC792EA) : const Color(0xFF7451A6);
    final functionColor =
        dark ? const Color(0xFFFFD580) : const Color(0xFF775A00);
    final typeColor =
        dark ? const Color(0xFF89DDFF) : const Color(0xFF00677A);

    final keywords = _keywordsFor(language.id);
    final spans = <TextSpan>[];
    final tokenPattern = RegExp(
      r'''(/\*[\s\S]*?\*/|//[^\n]*|<!--[\s\S]*?-->|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b0x[0-9A-Fa-f]+\b|\b\d+(?:\.\d+)?\b|@[A-Za-z_]\w*|\b[A-Za-z_]\w*\b)''',
      multiLine: true,
    );

    var cursor = 0;

    for (final match in tokenPattern.allMatches(code)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: code.substring(cursor, match.start),
          ),
        );
      }

      final token = match.group(0)!;
      TextStyle? style;

      final isHashComment = token.startsWith('#') &&
          (language.id == 'python' || language.id == 'shell');

      if (token.startsWith('//') ||
          token.startsWith('/*') ||
          token.startsWith('<!--') ||
          isHashComment) {
        style = TextStyle(
          color: commentColor,
          fontStyle: FontStyle.italic,
        );
      } else if (token.startsWith('"') ||
          token.startsWith("'") ||
          token.startsWith('`')) {
        style = TextStyle(color: stringColor);
      } else if (RegExp(r'^(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)$')
          .hasMatch(token)) {
        style = TextStyle(color: numberColor);
      } else if (token.startsWith('@') ||
          (token.startsWith('#') && !isHashComment)) {
        style = TextStyle(color: annotationColor);
      } else if (_isKeyword(keywords, token, language.id)) {
        style = TextStyle(
          color: keywordColor,
          fontWeight: FontWeight.w600,
        );
      } else if (const {
        'true',
        'false',
        'null',
        'nil',
        'None',
        'undefined',
      }.contains(token)) {
        style = TextStyle(color: numberColor);
      } else {
        final after = code.substring(match.end);
        final before =
            match.start > 0 ? code.substring(0, match.start) : '';

        if (language.id == 'xml' &&
            RegExp(r'<\/?\s*$').hasMatch(before)) {
          style = TextStyle(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          );
        } else if (RegExp(r'^\s*\(').hasMatch(after)) {
          style = TextStyle(color: functionColor);
        } else if (RegExp(r'^[A-Z][A-Za-z0-9_]*$').hasMatch(token)) {
          style = TextStyle(color: typeColor);
        }
      }

      spans.add(
        TextSpan(
          text: token,
          style: style ?? TextStyle(color: colors.onSurface),
        ),
      );

      cursor = match.end;
    }

    if (cursor < code.length) {
      spans.add(
        TextSpan(
          text: code.substring(cursor),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  static bool _isKeyword(
    Set<String> keywords,
    String token,
    String language,
  ) {
    if (language == 'sql') {
      return keywords.contains(token.toUpperCase());
    }
    return keywords.contains(token);
  }

  static Set<String> _keywordsFor(String language) {
    switch (language) {
      case 'cpp':
        return const {
          'alignas', 'alignof', 'auto', 'bool', 'break', 'case', 'catch',
          'char', 'class', 'const', 'constexpr', 'continue', 'default',
          'delete', 'do', 'double', 'else', 'enum', 'explicit', 'extern',
          'false', 'float', 'for', 'friend', 'if', 'inline', 'int', 'long',
          'namespace', 'new', 'nullptr', 'operator', 'private', 'protected',
          'public', 'return', 'short', 'signed', 'sizeof', 'static', 'struct',
          'switch', 'template', 'this', 'throw', 'true', 'try', 'typedef',
          'typename', 'union', 'unsigned', 'using', 'virtual', 'void',
          'volatile', 'while',
        };
      case 'java':
        return const {
          'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch',
          'char', 'class', 'const', 'continue', 'default', 'do', 'double',
          'else', 'enum', 'extends', 'final', 'finally', 'float', 'for', 'if',
          'implements', 'import', 'instanceof', 'int', 'interface', 'long',
          'native', 'new', 'package', 'private', 'protected', 'public',
          'return', 'short', 'static', 'strictfp', 'super', 'switch',
          'synchronized', 'this', 'throw', 'throws', 'transient', 'try',
          'void', 'volatile', 'while',
        };
      case 'kotlin':
        return const {
          'as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for',
          'fun', 'if', 'in', 'interface', 'is', 'null', 'object', 'package',
          'return', 'super', 'this', 'throw', 'true', 'try', 'typealias',
          'typeof', 'val', 'var', 'when', 'while', 'by', 'catch',
          'constructor', 'delegate', 'dynamic', 'field', 'file', 'finally',
          'get', 'import', 'init', 'param', 'property', 'receiver', 'set',
          'setparam', 'where',
        };
      case 'dart':
        return const {
          'abstract', 'as', 'assert', 'async', 'await', 'base', 'break',
          'case', 'catch', 'class', 'const', 'continue', 'covariant',
          'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export',
          'extends', 'extension', 'external', 'factory', 'false', 'final',
          'finally', 'for', 'Function', 'get', 'hide', 'if', 'implements',
          'import', 'in', 'interface', 'is', 'late', 'library', 'mixin',
          'new', 'null', 'of', 'on', 'operator', 'part', 'required',
          'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super',
          'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var',
          'void', 'when', 'while', 'with', 'yield',
        };
      case 'python':
        return const {
          'and', 'as', 'assert', 'async', 'await', 'break', 'class',
          'continue', 'def', 'del', 'elif', 'else', 'except', 'False',
          'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
          'lambda', 'None', 'nonlocal', 'not', 'or', 'pass', 'raise',
          'return', 'True', 'try', 'while', 'with', 'yield',
        };
      case 'shell':
        return const {
          'case', 'do', 'done', 'elif', 'else', 'esac', 'export', 'fi',
          'for', 'function', 'if', 'in', 'local', 'readonly', 'return',
          'then', 'until', 'while',
        };
      case 'javascript':
      case 'typescript':
        return const {
          'async', 'await', 'break', 'case', 'catch', 'class', 'const',
          'continue', 'debugger', 'default', 'delete', 'do', 'else', 'export',
          'extends', 'false', 'finally', 'for', 'function', 'if', 'import',
          'in', 'instanceof', 'let', 'new', 'null', 'return', 'static',
          'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'var',
          'void', 'while', 'with', 'yield', 'interface', 'type', 'implements',
          'private', 'protected', 'public', 'readonly', 'unknown', 'never',
          'string', 'number', 'boolean',
        };
      case 'rust':
        return const {
          'as', 'break', 'const', 'continue', 'crate', 'else', 'enum',
          'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop',
          'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self',
          'Self', 'static', 'struct', 'super', 'trait', 'true', 'type',
          'unsafe', 'use', 'where', 'while',
        };
      case 'go':
        return const {
          'break', 'case', 'chan', 'const', 'continue', 'default', 'defer',
          'else', 'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import',
          'interface', 'map', 'package', 'range', 'return', 'select',
          'struct', 'switch', 'type', 'var',
        };
      case 'sql':
        return const {
          'ALTER', 'AND', 'AS', 'ASC', 'BEGIN', 'BY', 'CASE', 'CREATE',
          'DELETE', 'DESC', 'DISTINCT', 'DROP', 'ELSE', 'END', 'FROM',
          'GROUP', 'HAVING', 'IN', 'INNER', 'INSERT', 'INTO', 'JOIN', 'LEFT',
          'LIMIT', 'NOT', 'NULL', 'ON', 'OR', 'ORDER', 'OUTER', 'RIGHT',
          'SELECT', 'SET', 'TABLE', 'THEN', 'UNION', 'UPDATE', 'VALUES',
          'WHEN', 'WHERE',
        };
      case 'smali':
        return const {
          'class', 'super', 'method', 'end', 'locals', 'registers', 'field',
          'annotation', 'prologue', 'line', 'param', 'public', 'private',
          'protected', 'static', 'final', 'native', 'abstract', 'synthetic',
          'constructor', 'return', 'new', 'instance', 'invoke', 'virtual',
          'direct', 'move', 'result', 'const', 'string',
        };
      default:
        return const <String>{};
    }
  }
}

class _TableBlock extends StatelessWidget {
  final List<List<String>> rows;
  final int headerRows;

  const _TableBlock({
    required this.rows,
    required this.headerRows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final columnCount = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (columnCount == 0) {
      return const SizedBox.shrink();
    }

    final normalizedRows = rows
        .map(
          (row) => List<String>.generate(
            columnCount,
            (index) => index < row.length ? row[index] : '',
          ),
        )
        .toList(growable: false);

    final divider = BorderSide(color: colors.outlineVariant);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: divider,
                verticalInside: divider,
              ),
              children: [
                for (var rowIndex = 0;
                    rowIndex < normalizedRows.length;
                    rowIndex++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: rowIndex < headerRows
                          ? colors.primaryContainer.withValues(alpha: 0.55)
                          : (rowIndex.isOdd
                              ? colors.surfaceContainerHighest
                                  .withValues(alpha: 0.42)
                              : colors.surfaceContainerLow),
                    ),
                    children: [
                      for (final cell in normalizedRows[rowIndex])
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 84,
                            maxWidth: 280,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 9,
                            ),
                            child: SelectableText(
                              cell,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.45,
                                fontWeight: rowIndex < headerRows
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: rowIndex < headerRows
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
