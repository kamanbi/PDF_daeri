/// 전면광고의 단일 소유자. (설계 `_workspace/52_architect_week4_design.md` §2 전체)
///
/// **`AdGate` 외에는 아무도 이 클래스를 부르지 않는다**(§2.2, §4.1). 화면·저장·
/// 공유 코드는 이 컨트롤러의 존재를 모른다. 실제 노출 트리거 호출부
/// (`save_dialog.dart`·`compress_sheet.dart`·공유 콜백)는 `AdGate`를 거쳐서만
/// 닿는다 — 그 배선 자체는 다음 라운드(W4-T8, flutter-ui 몫)다.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../billing/entitlement.dart';
import '../data/repository/settings_repository.dart';
import 'ad_ids.dart';

/// [InterstitialController]는 `SettingsRepository`를 직접 주입받는다(Riverpod
/// `Ref`를 들고 있지 않는다) — Provider 조립은 [interstitialControllerProvider]
/// 하나에만 있고, 클래스 자체는 순수 로직이라 테스트 더블로 검증하기 쉽다.
class InterstitialController {
  InterstitialController({required SettingsRepository? settingsRepository})
    : _settingsRepository = settingsRepository;

  final SettingsRepository? _settingsRepository;

  InterstitialAd? _ad;
  bool _loading = false;

  /// 미리 로드. 작업 성공 뒤 광고를 대기시키는 시점과 다음 앱 페이지 전환에서
  /// 호출한다. 로드는 표시가 아니므로 사용 중인 화면을 방해하지 않는다.
  Future<void> preload() async {
    if (_ad != null || _loading) return;

    final repo = _settingsRepository;
    if (repo == null) return; // §2.3 실패-닫힘: 카운트 불가 → 로드하지 않는다.
    if (!await repo.isInterstitialEligible()) return;

    _loading = true;
    try {
      await InterstitialAd.load(
        adUnitId: AdIds.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            _ad = ad;
          },
          onAdFailedToLoad: (error) {
            _loading = false;
            _ad = null;
            // §1.6과 동일 원칙: 재시도하지 않는다. 다음 preload() 호출(=다음
            // 저장/공유 시도)에서 다시 시도한다.
            developer.log(
              '전면광고 로드 실패: $error',
              name: 'interstitial_controller',
              level: 800,
            );
          },
        ),
      );
    } catch (e, st) {
      _loading = false;
      _ad = null;
      developer.log(
        '전면광고 로드 예외',
        name: 'interstitial_controller',
        level: 900,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 실제 표시(§2.2). 성공적으로 표시했을 때만 true. 상한 소진·미로드·표시
  /// 실패는 false. **false를 절대 사용자에게 알리지 않는다** — 호출자는 반환값
  /// 으로 UI를 바꾸지 않는다(그 규약을 지키는 것은 `AdGate`의 책임).
  Future<bool> showIfEligible() async {
    final repo = _settingsRepository;
    if (repo == null) return false; // §2.3 실패-닫힘.
    if (!await repo.isInterstitialEligible()) return false;

    final ad = _ad;
    if (ad == null) return false; // 미로드.

    // `InterstitialAd`는 1회용이다(§2.2) — 표시 시도 시점부터 재사용을 막는다.
    _ad = null;

    final shown = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        // §2.4 "증가 시점": 실제 표시 확인 후에만 카운트를 올린다. show() 호출
        // 만으로는 증가시키지 않는다 — 표시 실패 시 광고를 안 봤는데 횟수만
        // 깎이는 것을 막기 위함.
        unawaited(repo.recordInterstitialShown());
        if (!shown.isCompleted) shown.complete(true);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        // show 이후 인스턴스는 폐기하고 다시 preload한다(§2.2).
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        developer.log(
          '전면광고 표시 실패: $error',
          name: 'interstitial_controller',
          level: 800,
        );
        if (!shown.isCompleted) shown.complete(false);
      },
    );

    try {
      await ad.show();
    } catch (e, st) {
      developer.log(
        '전면광고 show() 예외',
        name: 'interstitial_controller',
        level: 900,
        error: e,
        stackTrace: st,
      );
      if (!shown.isCompleted) shown.complete(false);
    }
    return shown.future;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}

/// 앱 전역 1개(§2.2 "화면마다 만들지 않는다"). `AdGate`만 이 provider를 읽는다.
final interstitialControllerProvider = Provider<InterstitialController>((ref) {
  final controller = InterstitialController(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
