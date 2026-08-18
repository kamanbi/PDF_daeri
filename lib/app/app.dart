/// 앱 루트 위젯. 라우팅은 1주차 범위(S1 최소 홈)만 담는다.
/// `lib/app/router.dart`(전체 5개 화면 라우팅)는 설계 §1.5에 따라 2주차 flutter-ui
/// 산출물이다 — 지금은 `Navigator.push` 직접 호출로 충분하다(선제 구현 금지, 절대 규칙 8).
///
/// [2026-08-18 · 2주차] 외부 인텐트 수신 배선(설계 §4.3 미해소분)만 이번 라운드에
/// 추가한다: `IncomingIntentService`를 앱 부팅 시 1회 시작하고, `resumed`마다
/// `pollPending()`으로 네이티브에 갇힌 URI를 회수한다. 수신된 URI는
/// `pendingIncomingUriProvider`(큐 길이 1)에 보관만 한다 — 실제 소비(뷰어로 이동,
/// 스캔·저장 진행 중이면 대기)는 `lib/app/router.dart`·`open_pdf_flow.dart`가
/// 갖춰지는 다음 라운드에 flutter-ui가 붙인다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_screen.dart';
import 'providers.dart';

class PdfDaeriApp extends ConsumerStatefulWidget {
  const PdfDaeriApp({super.key});

  @override
  ConsumerState<PdfDaeriApp> createState() => _PdfDaeriAppState();
}

class _PdfDaeriAppState extends ConsumerState<PdfDaeriApp> with WidgetsBindingObserver {
  StreamSubscription<String>? _intentSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final service = ref.read(incomingIntentServiceProvider);
    // 구독 순서 고정(§4.2): ① 스트림 구독이 service.start() 내부에서 먼저 걸리고
    // ② 그 다음 takeInitialUri()가 1회 조회된다. 여기서는 구독만 먼저 걸어 둔다.
    _intentSub = service.uris.listen(_onIncomingUri);
    service.start();
  }

  void _onIncomingUri(String uri) {
    // 큐 길이 1(§4.4): 나중 것이 이전 것을 덮는다.
    ref.read(pendingIncomingUriProvider.notifier).state = uri;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // sink 미구독 창에 네이티브가 보관해 둔 URI를 회수한다(§4.1 미해소분 3).
      ref.read(incomingIntentServiceProvider).pollPending();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF 대리',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const HomeScreen(),
    );
  }
}
