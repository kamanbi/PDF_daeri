/// 3.5주차 디자인 확정 토큰. (milestones.md "색상·타이포그래피·톤 확정")
///
/// FinWise(Figma Community 참고 파일)의 카드 레이아웃·큰 라운드 코너·여백감을
/// 구조적으로만 참고했다 — 색상 팔레트(그린 계열)는 그대로 쓰지 않고, 사용자 결정에
/// 따라 포인트 컬러를 "고급스러운 딥 네이비 블루"로 새로 잡았다(2026-08-26 확정).
/// 레이아웃/네비게이션 구조는 이번 라운드에서 바꾸지 않는다 — 스타일(색·타이포·라운드·
/// 여백)만 입힌다.
library;

import 'package:flutter/material.dart';

abstract final class AppTheme {
  /// 포인트 컬러(프라이머리) — 딥 네이비 블루. (2026-08-26 사용자 확정)
  static const seedColor = Color(0xFF1B4B66);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: const TextTheme(
        // 압축률(%) 등 숫자 강조에 쓰는 큰 표제 — home_screen/compress_sheet에서 재사용.
        headlineSmall: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w700, fontSize: 24),
        titleLarge: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 20),
        titleMedium: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w400, fontSize: 16),
        bodyMedium: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w400, fontSize: 14),
        labelLarge: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
