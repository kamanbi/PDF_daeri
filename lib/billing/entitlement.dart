/// `adsRemoved` 상태의 진실. (설계 `_workspace/52_architect_week4_design.md` §3.5)
///
/// 신뢰 순서(§3.5):
/// ```
/// 진실의 원천 :  Google Play Developer API (서버 검증 결과)
///       ↓ 캐시
/// 영속 캐시   :  settings.ads_removed  (Drift 단일 행, SettingsRepository)
///       ↓ 노출
/// 런타임      :  adsRemovedProvider    ← 화면·광고가 읽는 유일한 값
/// ```
///
/// `SettingsRepository`(`lib/data/repository/settings_repository.dart`, W4-T3)를
/// 단일 소유 저장소로 쓴다. 구독의 활성 여부는 Google Play 조회 결과로만 바꾸며,
/// 이 파일은 `SettingsRows`를 직접 쿼리하지 않는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository/settings_repository.dart';

/// `SettingsRepository` 인스턴스. `main.dart` 부팅 시퀀스가 override한다
/// (D-5/D-6, 다음 라운드). 미주입 상태(null)에서는 이 파일과 `lib/ads/**`가
/// 전부 실패-닫힘으로 동작한다 — DB가 없으면 구매 여부를 신뢰할 수 없으므로
/// [Entitlement.syncSubscriptionState]는 조용히 아무 것도 하지 않고, [adsRemovedProvider]는
/// §3.5 "DB 초기화 실패 시 기본값은 false(광고 표시)"를 그대로 따른다.
final settingsRepositoryProvider = Provider<SettingsRepository?>((ref) => null);

/// adsRemoved의 런타임 진실(§3.5 "런타임"). 화면·`lib/ads/**`가 읽는 유일한 값이다.
///
/// `SettingsRepository.watch()`를 그대로 투영한다 — 이 provider 자체는 캐시를
/// 쓰지 않고 읽기만 한다. 캐시를 **쓰는** 쪽은 Google Play 구독 확인 결과를 받는
/// [Entitlement.syncSubscriptionState]이며, 화면 코드가 `setAdsRemoved`를 직접
/// 호출하지 않는다(단일 진입점).
final adsRemovedProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  if (repo == null) return Stream.value(false);
  return repo.watch().map((settings) => settings.adsRemoved);
});

/// 같은 검증된 연간 구독이 광고 제거와 OCR 생성을 함께 허용한다.
final ocrEntitlementProvider = Provider<AsyncValue<bool>>(
  (ref) => ref.watch(adsRemovedProvider),
);

/// OCR 화면이 구독 캐시의 첫 값을 기다려야 할 때 사용하는 비동기 경계.
final ocrEntitlementFutureProvider = FutureProvider<bool>(
  (ref) => ref.watch(adsRemovedProvider.future),
);

/// `adsRemoved` 캐시 갱신의 단일 진입점. `lib/billing/billing_service.dart`가
/// 서버가 확인한 활성 구독 상태만 전달한다. 다른 코드는 이 클래스를
/// 거치지 않고 `SettingsRepository.setAdsRemoved`를 직접 호출하지 않는다.
class Entitlement {
  Entitlement({required SettingsRepository? settingsRepository})
    : _settingsRepository = settingsRepository;

  final SettingsRepository? _settingsRepository;

  /// 활성 구독이면 광고를 제거하고, 만료됐으면 다시 표시한다. Google Play 조회가
  /// 실패한 경우에는 이 메서드를 호출하지 않아 직전 캐시를 보존한다.
  Future<void> syncSubscriptionState(bool activeSubscription) async {
    final repo = _settingsRepository;
    if (repo == null) return;
    await repo.setAdsRemoved(activeSubscription);
  }
}

final entitlementProvider = Provider<Entitlement>((ref) {
  return Entitlement(settingsRepository: ref.watch(settingsRepositoryProvider));
});
