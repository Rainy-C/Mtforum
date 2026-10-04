import 'package:flutter/material.dart';

/// 配色体系：**中性灰 / 黑白 + 单一低饱和强调色**。
///
/// 刻意不用高饱和蓝紫，也不使用渐变、发光、玻璃拟态。
/// - 表面色阶（surface / surfaceContainer*）全部走低彩度中性灰，
///   深浅色都保持"纸张 + 石墨"的质感；
/// - 强调色只保留一个：低饱和松石绿（[accentSeed]），用于主按钮、
///   选中态、进度条；
/// - 语义色（error / tertiary）保持 MD3 默认语义，不额外装饰。
abstract final class AppColors {
  /// 唯一强调色种子（低饱和松石绿）
  static const Color accentSeed = Color(0xFF2F6B5F);

  static ColorScheme light() {
    final base = ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: const Color(0xFF2C6357),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFCDE9E1),
      onPrimaryContainer: const Color(0xFF0C3A31),
      secondary: const Color(0xFF4A635C),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDCE7E3),
      onSecondaryContainer: const Color(0xFF26332F),
      tertiary: const Color(0xFF5A5D6B),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFE1E2EC),
      onTertiaryContainer: const Color(0xFF2C2F3A),

      // 中性表面：不跟随种子上色，保证"黑白灰"主体
      surface: const Color(0xFFF7F7F8),
      onSurface: const Color(0xFF1A1C1D),
      onSurfaceVariant: const Color(0xFF5C6064),
      surfaceDim: const Color(0xFFDCDDDF),
      surfaceBright: const Color(0xFFFBFBFC),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFFFFFF),
      surfaceContainer: const Color(0xFFF1F2F3),
      surfaceContainerHigh: const Color(0xFFEAEBED),
      surfaceContainerHighest: const Color(0xFFE3E5E7),

      outline: const Color(0xFF8A8F94),
      outlineVariant: const Color(0xFFD3D6DA),
      inverseSurface: const Color(0xFF2F3133),
      onInverseSurface: const Color(0xFFF1F2F3),
      inversePrimary: const Color(0xFF9BD3C6),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
    );
  }

  static ColorScheme dark() {
    final base = ColorScheme.fromSeed(
      seedColor: accentSeed,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      primary: const Color(0xFF94CFC2),
      onPrimary: const Color(0xFF00382F),
      primaryContainer: const Color(0xFF1E4F46),
      onPrimaryContainer: const Color(0xFFC9EBE3),
      secondary: const Color(0xFFB3C7C0),
      onSecondary: const Color(0xFF1F352F),
      secondaryContainer: const Color(0xFF354B45),
      onSecondaryContainer: const Color(0xFFCFE3DC),
      tertiary: const Color(0xFFC4C6D2),
      onTertiary: const Color(0xFF2D3039),
      tertiaryContainer: const Color(0xFF444650),
      onTertiaryContainer: const Color(0xFFE1E2EC),

      // 深色表面：石墨黑，不带蓝紫偏色
      surface: const Color(0xFF121315),
      onSurface: const Color(0xFFE6E7E9),
      onSurfaceVariant: const Color(0xFFA9ADB2),
      surfaceDim: const Color(0xFF121315),
      surfaceBright: const Color(0xFF383A3D),
      surfaceContainerLowest: const Color(0xFF0C0D0E),
      surfaceContainerLow: const Color(0xFF181A1C),
      surfaceContainer: const Color(0xFF1E2023),
      surfaceContainerHigh: const Color(0xFF282A2D),
      surfaceContainerHighest: const Color(0xFF333538),

      outline: const Color(0xFF8B9095),
      outlineVariant: const Color(0xFF3D4145),
      inverseSurface: const Color(0xFFE6E7E9),
      onInverseSurface: const Color(0xFF2F3133),
      inversePrimary: const Color(0xFF2C6357),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      error: const Color(0xFFF2B8B5),
      onError: const Color(0xFF601410),
      errorContainer: const Color(0xFF8C1D18),
      onErrorContainer: const Color(0xFFF9DEDC),
    );
  }
}
