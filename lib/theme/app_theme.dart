import 'package:flutter/material.dart';

/// MTForum 视觉体系
///
/// 重点不是增加更多颜色，而是把 Material 3 的 surface 层级真正拉开：
/// scaffold < card < secondary surface < selected / action。
class AppTheme {
  static const Color seedColor = Color(0xFF3F67B1);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    final scheme = generated.copyWith(
      primary: isDark ? const Color(0xFFAFC8FF) : const Color(0xFF315A9E),
      onPrimary: isDark ? const Color(0xFF002E69) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF203B67) : const Color(0xFFD8E5FF),
      onPrimaryContainer:
          isDark ? const Color(0xFFD9E5FF) : const Color(0xFF102F5E),
      secondary: isDark ? const Color(0xFF82D5CA) : const Color(0xFF276A64),
      secondaryContainer:
          isDark ? const Color(0xFF164A47) : const Color(0xFFC7F0EB),
      onSecondaryContainer:
          isDark ? const Color(0xFFB9F3EC) : const Color(0xFF123E3A),
      tertiary: isDark ? const Color(0xFFF2C27E) : const Color(0xFF8A5A16),
      tertiaryContainer:
          isDark ? const Color(0xFF583C18) : const Color(0xFFFFE1B4),
      onTertiaryContainer:
          isDark ? const Color(0xFFFFE1B4) : const Color(0xFF57370C),
      surface: isDark ? const Color(0xFF0F1116) : const Color(0xFFF6F7FA),
      surfaceContainerLowest:
          isDark ? const Color(0xFF0B0D11) : const Color(0xFFFFFFFF),
      surfaceContainerLow:
          isDark ? const Color(0xFF161920) : const Color(0xFFFFFFFF),
      surfaceContainer:
          isDark ? const Color(0xFF1C2028) : const Color(0xFFF0F2F6),
      surfaceContainerHigh:
          isDark ? const Color(0xFF242A35) : const Color(0xFFE8EBF1),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2D3542) : const Color(0xFFDDE2EA),
      outline: isDark ? const Color(0xFF929BAA) : const Color(0xFF697386),
      outlineVariant:
          isDark ? const Color(0xFF3A4352) : const Color(0xFFC9D0DA),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
      errorContainer:
          isDark ? const Color(0xFF6A2424) : const Color(0xFFFFDAD6),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.72 : 0.80),
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: TextStyle(color: scheme.outline),
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.72),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.85),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),

      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.90)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),

      tabBarTheme: TabBarThemeData(
        dividerColor: scheme.outlineVariant,
        indicatorColor: scheme.primary,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
