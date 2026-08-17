/// 앱 루트 위젯. 라우팅은 1주차 범위(S1 최소 홈)만 담는다.
/// `lib/app/router.dart`(전체 5개 화면 라우팅)는 설계 §1.2에 따라 2주차 산출물이다
/// — 지금은 `Navigator.push` 직접 호출로 충분하다(선제 구현 금지, 절대 규칙 8).
library;

import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';

class PdfDaeriApp extends StatelessWidget {
  const PdfDaeriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF 대리',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const HomeScreen(),
    );
  }
}
