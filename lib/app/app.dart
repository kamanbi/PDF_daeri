/// 앱 루트 위젯. (1주차 최소 홈 → 2주차 라우팅 전면 개편)
///
/// [2026-08-18 · 2주차] `lib/app/router.dart`(설계 §1.5)로 라우팅을 이관한다 —
/// `home:` 직접 지정을 버리고 `initialRoute` + `onGenerateRoute`를 쓴다.
/// `navigatorKey`는 이 파일이 소유한다(features/**에서 전역 키를 따로 만들지 않는다).
///
/// 인텐트 수신 배선(설계 §4.3, 1주차 산출물 유지)에 이어 이번 라운드는 **소비
/// 지점**을 완성한다: `pendingIncomingUriProvider`에 URI가 쌓이고
/// `appBusyProvider`가 false일 때만 `openPdfAndGoToViewer`로 넘긴다(§4.4 —
/// 스캔·저장 진행 중에는 가로채지 않는다는 원칙을 이 신호로 지킨다).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_screen.dart';
import '../features/viewer/open_pdf_flow.dart';
import 'providers.dart';
import 'router.dart';

class PdfDaeriApp extends ConsumerStatefulWidget {
  const PdfDaeriApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  ConsumerState<PdfDaeriApp> createState() => _PdfDaeriAppState();
}

class _PdfDaeriAppState extends ConsumerState<PdfDaeriApp> with WidgetsBindingObserver {
  StreamSubscription<String>? _intentSub;
  ProviderSubscription<String?>? _pendingSub;
  ProviderSubscription<bool>? _busySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final service = ref.read(incomingIntentServiceProvider);
    // 구독 순서 고정(§4.2): ① 스트림 구독이 service.start() 내부에서 먼저 걸리고
    // ② 그 다음 takeInitialUri()가 1회 조회된다. 여기서는 구독만 먼저 걸어 둔다.
    _intentSub = service.uris.listen(_onIncomingUri);
    service.start();

    // 큐(pendingIncomingUriProvider)·busy(appBusyProvider) 둘 중 하나라도
    // 바뀌면 소비 가능 여부를 다시 판단한다(§4.4).
    _pendingSub = ref.listenManual(pendingIncomingUriProvider, (prev, next) => _maybeConsumePending());
    _busySub = ref.listenManual(appBusyProvider, (prev, next) => _maybeConsumePending());
  }

  void _onIncomingUri(String uri) {
    // 큐 길이 1(§4.4): 나중 것이 이전 것을 덮는다.
    ref.read(pendingIncomingUriProvider.notifier).state = uri;
  }

  void _maybeConsumePending() {
    final busy = ref.read(appBusyProvider);
    final uri = ref.read(pendingIncomingUriProvider);
    if (busy || uri == null) return;

    final context = PdfDaeriApp.navigatorKey.currentContext;
    if (context == null) return;

    // 먼저 큐를 비운다 — openPdfAndGoToViewer가 비동기로 도는 동안 같은 URI를
    // 중복 소비하지 않기 위함이다.
    ref.read(pendingIncomingUriProvider.notifier).state = null;
    openPdfAndGoToViewer(context: context, ref: ref, source: IntentUriSource(uri));
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
    _pendingSub?.close();
    _busySub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF 대리',
      navigatorKey: PdfDaeriApp.navigatorKey,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      initialRoute: AppRoutes.home,
      onGenerateRoute: onGenerateRoute,
      // 방어선(근본 수정은 MainActivity.kt의 shouldHandleDeeplinking()=false —
      // _workspace/29 참고). 그럼에도 알 수 없는 이름의 라우트가 push되면(예:
      // 향후 다른 딥링크 경로, 테스트) Navigator가 죽지 않고 홈으로 안전 착지한다.
      onUnknownRoute: (settings) => MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
}
