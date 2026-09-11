import 'package:flutter/material.dart';

/// 深色主题。街机厅光线暗，深色底更不刺眼。
class AppTheme {
  const AppTheme._();

  static const Color bg = Color(0xFF14141C);
  static const Color surface = Color(0xFF1D1D28);
  static const Color surfaceHigh = Color(0xFF262634);
  static const Color border = Color(0xFF33334A);

  static const Color textPrimary = Color(0xFFE8E8F0);
  static const Color textSecondary = Color(0xFF9AA0B5);
  static const Color textDim = Color(0xFF7D8399);
  static const Color textFaint = Color(0xFF5A6076);

  /// 已开放 / 已解锁
  static const Color accent = Color(0xFF4ADE80);

  /// 需要注意（未达成、条件待确认）
  static const Color warning = Color(0xFFC98A2E);

  /// BOSS 难度
  static const Color bossTint = Color(0xFFD8B46A);

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        surface: surface,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2A2A3A), thickness: 1, space: 1),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}

/// 门状态对应的显示文字与颜色。
class StatusStyle {
  const StatusStyle(this.label, this.color);

  final String label;
  final Color color;
}
