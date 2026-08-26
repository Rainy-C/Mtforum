import 'package:flutter/material.dart';

/// MTForum 统一视觉体系。
///
/// 统一卡片、输入框、Chip、BottomSheet、按钮、加载状态和页面过渡，
/// 页面本身只负责信息层级，不再各自定义一套视觉参数。
class AppTheme {
  static const Color seedColor = Color(0xFF3F67B1);

  static ThemeData light({String? fontFamily}) =>
      _build(Brightness.light, fontFamily: fontFamily);
  static ThemeData dark({String? fontFamily}) =>
      _build(Brightness.dark, fontFamily: fontFamily);

  static ThemeData _build(Brightness brightness, {String? fontFamily}) {
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

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.86),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _MTPageTransitionsBuilder(),
          TargetPlatform.iOS: _MTPageTransitionsBuilder(),
          TargetPlatform.linux: _MTPageTransitionsBuilder(),
          TargetPlatform.macOS: _MTPageTransitionsBuilder(),
          TargetPlatform.windows: _MTPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _MTPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.68 : 0.72),
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.68),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        alignLabelWithHint: true,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.22),
        selectionHandleColor: scheme.primary,
      ),

      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.82)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
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
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.65),
        indicatorColor: scheme.primary,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.06),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainer,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.82)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}

/// 全局页面切换：纯横向层级动画。
///
/// 新页面从右侧完整推入；返回时严格反向滑出。底层页面仅做轻微视差，
/// 不叠加透明度、缩放或额外位移，避免返回时出现“飘一下”的感觉。
class _MTPageTransitionsBuilder extends PageTransitionsBuilder {
  const _MTPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 进入使用减速曲线，返回使用对应的加速曲线。
    // reverse 继续使用 easeOut 会导致返回时起步发黏、收尾突然。
    final primary = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final secondary = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final incoming = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(primary);
    final background = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.06, 0),
    ).animate(secondary);

    return RepaintBoundary(
      child: SlideTransition(
        position: background,
        transformHitTests: false,
        child: SlideTransition(
          position: incoming,
          transformHitTests: false,
          child: child,
        ),
      ),
    );
  }
}
