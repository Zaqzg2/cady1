import 'package:flutter/material.dart';

/// ألوان دلالية ثابتة تُستخدم في كل الشاشات (الثقة/الصلاحية) — بمعزل عن
/// ColorScheme العام، لأنها ألوان "حالة" وليست ألوان علامة تجارية.
class AppColors {
  AppColors._();

  // درجات الثقة كما وردت في المواصفة: 🟢 عالية، 🟠 متوسطة، 🔴 منخفضة
  static const confidenceHigh = Color(0xFF2E7D32);
  static const confidenceMedium = Color(0xFFEF6C00);
  static const confidenceLow = Color(0xFFC62828);

  // حالة الصلاحية: 🔴 منتهي، 🟠 <30 يوم، 🟡 <60 يوم، 🟢 آمن
  static const expiryExpired = Color(0xFFC62828);
  static const expiryWithin30 = Color(0xFFEF6C00);
  static const expiryWithin60 = Color(0xFFF9A825);
  static const expirySafe = Color(0xFF2E7D32);
}

class AppTheme {
  AppTheme._();

  // بدلاً من الأزرق الافتراضي المعتاد: أخضر-تيل عميق يوحي بالاستقرار المالي
  // والمخزون، مع كسر بصري عن قوالب Material الجاهزة.
  static const _seedColor = Color(0xFF0F6B5C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // عمدًا لا نضبط fontFamily هنا — "استخدام خط النظام في الجهاز" حسب
      // المواصفة، فنترك Flutter يستخدم الخط الافتراضي للمنصة.
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
