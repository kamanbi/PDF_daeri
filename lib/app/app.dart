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
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../ads/ad_gate.dart';
import '../billing/billing_service.dart';
import '../core/platform_features.dart';
import '../features/home/home_screen.dart';
import '../features/viewer/open_pdf_flow.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class PdfDaeriApp extends ConsumerStatefulWidget {
  const PdfDaeriApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  ConsumerState<PdfDaeriApp> createState() => _PdfDaeriAppState();
}

class _PdfDaeriAppState extends ConsumerState<PdfDaeriApp>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _intentSub;
  ProviderSubscription<String?>? _pendingSub;
  ProviderSubscription<bool>? _busySub;
  late final NavigatorObserver _adRouteObserver;
  var _updateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    WidgetsBinding.instance.addObserver(this);
    _adRouteObserver = _AppPageRouteObserver(
      onPageTransition: () =>
          unawaited(ref.read(adGateProvider).consumePendingOnPageTransition()),
    );

    final service = ref.read(incomingIntentServiceProvider);
    // 구독 순서 고정(§4.2): ① 스트림 구독이 service.start() 내부에서 먼저 걸리고
    // ② 그 다음 takeInitialUri()가 1회 조회된다. 여기서는 구독만 먼저 걸어 둔다.
    _intentSub = service.uris.listen(_onIncomingUri);
    service.start();

    // 큐(pendingIncomingUriProvider)·busy(appBusyProvider) 둘 중 하나라도
    // 바뀌면 소비 가능 여부를 다시 판단한다(§4.4).
    _pendingSub = ref.listenManual(
      pendingIncomingUriProvider,
      (prev, next) => _maybeConsumePending(),
    );
    _busySub = ref.listenManual(
      appBusyProvider,
      (prev, next) => _maybeConsumePending(),
    );

    // W4-T5b(문서 60 §4 F-1 해소 · §3.6 부팅 순서): billingServiceProvider는
    // Provider라 앱 전역 단일 인스턴스다. start()가 purchaseStream 구독을 먼저
    // 걸고, 그 다음 상품 조회 → 자동 복원 순서로 진행한다(순서가 절대적, §3.6).
    if (AppFeatures.billing) unawaited(_startBilling());
    if (AppFeatures.storeUpdate) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_checkForUpdate()),
      );
    }
  }

  Future<void> _startBilling() async {
    try {
      final billing = ref.read(billingServiceProvider);
      await billing.start();
      await billing.queryProducts();
      await billing.restorePurchases();
    } catch (e, st) {
      // 기존 부팅 관례(main.dart)와 동일하게 실패를 흡수한다 — 구매/복원 실패가
      // 앱을 막지 않는다(무알림, 배너 없음과 같은 fail-closed 방향).
      developer.log(
        '결제 부팅 배선 실패',
        name: 'app',
        level: 900,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _checkForUpdate() async {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;
    final updates = ref.read(playUpdateServiceProvider);
    if (!await updates.isImmediateUpdateAvailable() || !mounted) return;
    final navigator = PdfDaeriApp.navigatorKey.currentState;
    if (navigator == null) return;
    final accepted = await showDialog<bool>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: const Text('업데이트가 있습니다'),
        content: const Text('더 안정적인 최신 버전이 있습니다. 지금 업데이트할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await updates.startImmediateUpdate();
    }
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
    openPdfAndGoToViewer(
      context: context,
      ref: ref,
      source: IntentUriSource(uri),
    );
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
      theme: AppTheme.light(),
      initialRoute: AppRoutes.home,
      onGenerateRoute: onGenerateRoute,
      navigatorObservers: [_adRouteObserver],
      // 방어선(근본 수정은 MainActivity.kt의 shouldHandleDeeplinking()=false —
      // _workspace/29 참고). 그럼에도 알 수 없는 이름의 라우트가 push되면(예:
      // 향후 다른 딥링크 경로, 테스트) Navigator가 죽지 않고 홈으로 안전 착지한다.
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
}

/// 전면광고는 작업 종료가 아니라 안정된 앱 페이지 전환에서만 확인한다.
class _AppPageRouteObserver extends NavigatorObserver {
  _AppPageRouteObserver({required this.onPageTransition});

  static const _transitionSettleDuration = Duration(milliseconds: 300);

  final VoidCallback onPageTransition;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyWhenSettled(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _notifyWhenSettled(previousRoute);
  }

  void _notifyWhenSettled(Route<dynamic> route) {
    if (route is! PageRoute<dynamic>) return;
    Future<void>.delayed(_transitionSettleDuration, () {
      if (route.isCurrent) onPageTransition();
    });
  }
}
