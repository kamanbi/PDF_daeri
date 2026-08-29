/// `in_app_purchase` SDK 접점 단일 소유자. (설계 `_workspace/52_architect_week4_design.md`
/// §3.1·§3.2·§3.3·§3.4·§3.6)
///
/// **이 파일 밖에서 `InAppPurchase.instance`를 부르지 않는다.** 구매 스트림·
/// 상품 조회·구매·복원이 전부 여기 모인다.
///
/// 검증 수준(§3.4, 확정): 서버 영수증 검증을 하지 않는다(절대 규칙 1 — 서버
/// 없음). `PurchaseDetails.status`가 `purchased`/`restored`이고
/// `productID == 'ads_removed'`인지만 확인한다. 수용 위험: 루팅 기기 + 결제
/// 후킹 앱으로 위조 가능하나, 피해는 그 기기 1대의 광고 수익 손실로 한정된다
/// (`ads.md` "기능 잠금 없음").
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'entitlement.dart';

/// 연간 자동 갱신 구독 상품(연 4,990원). Google Play Console에서 연간 기본 요금제를
/// 활성화해야 한다.
///
/// **[승인 대기 · 사용자 작업 필요]** 이 상품은 아직 Play Console에 존재하지
/// 않는다(§3.2). 상품이 없으면 [BillingService.queryProducts]가 `notFoundIDs`를
/// 받아 [PurchaseUiState.notFound]로 떨어진다 — 앱이 죽지 않는다.
const String kAdsRemovedProductId = 'ads_removed';

/// S5 설정 화면(§6.2, 다음 라운드 T9)이 구독할 구매 UI 상태.
enum PurchaseUiState {
  /// 상품 조회 전 — 아직 [BillingService.queryProducts]가 끝나지 않았다.
  loading,

  /// 이 기기에서 인앱결제를 쓸 수 없다(`InAppPurchase.instance.isAvailable() ==
  /// false`). §3.6: 항목을 숨기지 않고 비활성 + 안내 문구로 대응한다.
  unavailable,

  /// 상품이 Play Console에 없거나(`notFoundIDs`) 조회에 실패했다(§3.2). 조용한
  /// 비활성 — 에러 다이얼로그를 띄우지 않는다.
  notFound,

  /// 구매 가능(미구매) 상태. [BillingService.product]가 채워져 있다.
  available,

  /// 구독 결제 호출 후 `pending` 이벤트 대기 중(§3.3 "버튼 자리에 스피너").
  purchasePending,

  /// 방금 `purchased`/`restored` 이벤트를 받았다(전이 확인용 — 지속 상태는
  /// `adsRemovedProvider`가 갖는다. 이 값은 "방금 막 반영됐다"는 1회성 신호다).
  purchased,
}

/// 수동 복원(S5 [구매 복원] 버튼, §3.6) 결과. `restorePurchases()`는 "복원할
/// 게 없다"를 알려주지 않으므로 5초 타임아웃이 유일한 판정 수단이다.
enum RestoreOutcome { restored, nothingToRestore }

class BillingService {
  BillingService({
    required Entitlement entitlement,
    InAppPurchase? inAppPurchase,
  }) : _entitlement = entitlement,
       _iap = inAppPurchase ?? InAppPurchase.instance;

  final Entitlement _entitlement;
  final InAppPurchase _iap;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _product;
  bool _available = false;
  bool _started = false;
  PurchaseUiState _state = PurchaseUiState.loading;

  final _statusController = StreamController<PurchaseUiState>.broadcast();

  /// 수동 복원 진행 중에만 채워지는 훅. §3.6: 복원 시도 중 도착한
  /// `purchased`/`restored` 이벤트를 [restoreManually]가 관측하기 위함이다.
  void Function()? _restoreProbe;

  /// 최신 구매 UI 상태 스트림(§6.2 화면 표에 대응). 화면이 구독한다(다음 라운드).
  Stream<PurchaseUiState> get statusStream => _statusController.stream;

  /// 스트림 구독 전에도 즉시 읽을 수 있는 현재 상태.
  PurchaseUiState get state => _state;

  /// 조회된 상품. `notFound`/`unavailable`/`loading` 상태에서는 null이다.
  ProductDetails? get product => _product;

  void _emit(PurchaseUiState next) {
    _state = next;
    _statusController.add(next);
  }

  /// §3.6 4단계: `purchaseStream` 구독을 **가장 먼저** 건다. 앱 실행당 1회만
  /// 호출한다(화면 전환·resume마다 부르지 않는다) — 재호출은 아무 것도 하지
  /// 않는다.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      _available = await _iap.isAvailable();
    } catch (e, st) {
      developer.log(
        'InAppPurchase.isAvailable 실패',
        name: 'billing_service',
        level: 900,
        error: e,
        stackTrace: st,
      );
      _available = false;
    }

    if (!_available) {
      _emit(PurchaseUiState.unavailable);
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e, StackTrace st) {
        developer.log(
          'purchaseStream 오류',
          name: 'billing_service',
          level: 900,
          error: e,
          stackTrace: st,
        );
      },
    );
  }

  /// §3.6 5단계: [start] 이후에만 호출한다. 상품이 없으면(`notFoundIDs`) 또는
  /// 조회 자체가 실패하면 [PurchaseUiState.notFound]로 떨어진다 — 앱이 죽지
  /// 않는다(§3.2 "사용자 작업 미완" 상태에 대한 방어).
  Future<void> queryProducts([
    Set<String> productIds = const {kAdsRemovedProductId},
  ]) async {
    if (!_available) return;
    try {
      final response = await _iap.queryProductDetails(productIds);
      if (response.notFoundIDs.isNotEmpty) {
        developer.log(
          '상품 미등록: ${response.notFoundIDs}',
          name: 'billing_service',
          level: 800,
        );
      }
      if (response.error != null || response.productDetails.isEmpty) {
        _product = null;
        _emit(PurchaseUiState.notFound);
        return;
      }
      _product = response.productDetails.first;
      _emit(PurchaseUiState.available);
    } catch (e, st) {
      developer.log(
        '상품 조회 실패',
        name: 'billing_service',
        level: 900,
        error: e,
        stackTrace: st,
      );
      _product = null;
      _emit(PurchaseUiState.notFound);
    }
  }

  /// [구독] 버튼 핸들러. Android 구독은 Play가 제공한 오퍼 토큰이 반드시 있어야
  /// 하며, 상품이 없거나 결제를 쓸 수 없으면 아무 것도 하지 않는다.
  Future<void> buy() async {
    final product = _product;
    if (product == null || !_available) return;
    if (Platform.isAndroid &&
        (product is! GooglePlayProductDetails || product.offerToken == null)) {
      developer.log(
        '구독 오퍼 토큰이 없어 결제를 시작하지 않음',
        name: 'billing_service',
        level: 800,
      );
      return;
    }
    try {
      final purchaseParam = product is GooglePlayProductDetails
          ? GooglePlayPurchaseParam(
              productDetails: product,
              offerToken: product.offerToken,
            )
          : PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e, st) {
      developer.log(
        'buyNonConsumable 실패',
        name: 'billing_service',
        level: 900,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 앱 시작 시 활성 구독을 동기화한다. Android에서는 Google Play 현재 구매 목록을
  /// 조회해 만료된 구독도 광고 제거 캐시에서 해제한다.
  Future<void> restorePurchases() async {
    if (!_available) return;
    await _syncSubscriptionEntitlement();
    await _iap.restorePurchases();
  }

  /// 수동 갱신은 Android의 현재 활성 구독 목록으로 즉시 판정한다. Android 외
  /// 플랫폼에서는 기존 복원 이벤트를 5초간 관찰한다.
  Future<RestoreOutcome> restoreManually() async {
    if (!_available) return RestoreOutcome.nothingToRestore;

    final activeSubscription = await _syncSubscriptionEntitlement();
    if (activeSubscription != null) {
      return activeSubscription
          ? RestoreOutcome.restored
          : RestoreOutcome.nothingToRestore;
    }

    final completer = Completer<void>();
    _restoreProbe = () {
      if (!completer.isCompleted) completer.complete();
    };
    try {
      await _iap.restorePurchases();
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } finally {
      _restoreProbe = null;
    }
    return completer.isCompleted
        ? RestoreOutcome.restored
        : RestoreOutcome.nothingToRestore;
  }

  /// 성공 시 활성 여부를 반환하고, Play 조회 실패 시 null을 반환한다. 실패 때
  /// 캐시를 덮어쓰지 않아 일시적인 스토어 연결 문제로 광고 제거가 사라지지 않는다.
  Future<bool?> _syncSubscriptionEntitlement() async {
    if (!Platform.isAndroid) return null;
    try {
      final androidAddition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await androidAddition.queryPastPurchases();
      if (response.error != null) {
        developer.log(
          '활성 구독 조회 실패: ${response.error}',
          name: 'billing_service',
          level: 900,
        );
        return null;
      }

      final activeSubscription = response.pastPurchases.any(
        (purchase) =>
            purchase.productID == kAdsRemovedProductId &&
            purchase.status == PurchaseStatus.purchased,
      );
      await _entitlement.syncSubscriptionState(activeSubscription);
      return activeSubscription;
    } catch (e, st) {
      developer.log(
        '활성 구독 동기화 실패',
        name: 'billing_service',
        level: 900,
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == kAdsRemovedProductId) {
        switch (purchase.status) {
          case PurchaseStatus.pending:
            _emit(PurchaseUiState.purchasePending);
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            // §3.4: 로컬 검증 수준 — status + productID 일치만 확인한다.
            // verificationData 서명은 앱에서 자체 검증하지 않는다.
            await _entitlement.syncSubscriptionState(true);
            _emit(PurchaseUiState.purchased);
            _restoreProbe?.call();
          case PurchaseStatus.canceled:
            // §3.3: 아무 것도 하지 않는다(스낵바도 없다).
            break;
          case PurchaseStatus.error:
            developer.log(
              '구매 오류: ${purchase.error}',
              name: 'billing_service',
              level: 800,
            );
        }
      }

      // §3.3: "completePurchase는 모든 purchased/restored에 대해 반드시
      // 호출한다." pendingCompletePurchase는 상태와 무관하게 완료 처리한다 —
      // 누락하면 Google이 3일 후 자동 환불하고 매 실행마다 같은 구매를
      // 다시 받는다.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _statusController.close();
  }
}

final billingServiceProvider = Provider<BillingService>((ref) {
  final service = BillingService(entitlement: ref.watch(entitlementProvider));
  ref.onDispose(service.dispose);
  return service;
});
