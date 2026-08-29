/// 광고에 관한 **모든 판단**이 끝나는 단일 지점. (설계
/// `_workspace/52_architect_week4_design.md` §4 전체)
///
/// `adsRemoved`/`adsRemovedProvider` 식별자를 읽는 곳은 `lib/ads/**`·
/// `lib/billing/**`·`lib/features/settings/settings_screen.dart` 뿐이다
/// (§4.3 검사28). 화면·저장·공유 코드 어디에서도 이 값을 직접 읽지 않는다 —
/// `AdGate`를 통해서만 판단 결과(불린)를 받는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../billing/entitlement.dart';
import 'ads_bootstrap.dart';
import 'interstitial_controller.dart';

/// §1.5 방어 4: 전면광고 종료 후 3초간 배너 억제. `AdGate`가 유일한 소유자다
/// (library-private — 이 파일 밖에서 참조할 수 없다).
final _bannerSuppressedUntilProvider = StateProvider<DateTime?>((ref) => null);
final _pendingInterstitialProvider = StateProvider<bool>((ref) => false);
final _interstitialTransitionInFlightProvider = StateProvider<bool>(
  (ref) => false,
);

class AdGate {
  AdGate._({
    required bool adsRemoved,
    required int? bannerHeight,
    required DateTime? suppressedUntil,
    required bool pendingInterstitial,
    required bool transitionInFlight,
    required InterstitialController interstitial,
    required DateTime Function() now,
    required void Function(DateTime?) setSuppressedUntil,
    required void Function(bool) setPendingInterstitial,
    required void Function(bool) setTransitionInFlight,
  }) : _adsRemoved = adsRemoved,
       _bannerHeight = bannerHeight,
       _suppressedUntil = suppressedUntil,
       _pendingInterstitial = pendingInterstitial,
       _transitionInFlight = transitionInFlight,
       _interstitial = interstitial,
       _now = now,
       _setSuppressedUntil = setSuppressedUntil,
       _setPendingInterstitial = setPendingInterstitial,
       _setTransitionInFlight = setTransitionInFlight;

  final bool _adsRemoved;
  final int? _bannerHeight;
  final DateTime? _suppressedUntil;
  final bool _pendingInterstitial;
  final bool _transitionInFlight;
  final InterstitialController _interstitial;
  final DateTime Function() _now;
  final void Function(DateTime?) _setSuppressedUntil;
  final void Function(bool) _setPendingInterstitial;
  final void Function(bool) _setTransitionInFlight;

  /// §1.5: 전면 종료 후 배너 억제 구간.
  static const Duration bannerSuppressDuration = Duration(seconds: 3);

  /// 배너를 붙여도 되는가. `BannerHost`만 읽는다(§4.1).
  /// `!adsRemoved && bannerHeight != null && !suppressed`.
  bool get bannerAllowed {
    if (_adsRemoved) return false; // §4.2: 구매 시 배너 완전 소거.
    if (_bannerHeight == null) return false; // §1.6 disabled 상태.
    final until = _suppressedUntil;
    if (until != null && _now().isBefore(until)) return false; // suppressed.
    return true;
  }

  /// 전면 억제 해제 시각(§1.5). `BannerHost`가 읽는다. 억제 중이 아니거나
  /// `adsRemoved == true`면 null.
  DateTime? get bannerSuppressedUntil => _adsRemoved ? null : _suppressedUntil;

  /// 작업 성공은 광고를 즉시 띄우지 않고 다음 앱 페이지 전환까지 대기시킨다.
  Future<void> registerCompletedTask() async {
    if (_adsRemoved) return;
    _setPendingInterstitial(true);
    await _interstitial.preload();
  }

  /// 모달이 아닌 앱 화면 전환이 완료될 때만 호출한다. 광고가 없거나 5분 간격을
  /// 만족하지 않으면 대기를 유지해 다음 화면 전환에서만 다시 시도한다.
  Future<void> consumePendingOnPageTransition() async {
    if (_adsRemoved || !_pendingInterstitial || _transitionInFlight) return;
    _setTransitionInFlight(true);
    await _interstitial.preload();
    final shown = await _interstitial.showIfEligible();
    if (shown) {
      _setPendingInterstitial(false);
      _setSuppressedUntil(_now().add(bannerSuppressDuration));
    }
    _setTransitionInFlight(false);
  }
}

/// `adsRemoved`·배너 높이·억제 상태·전면 컨트롤러 중 하나라도 바뀌면 새
/// [AdGate] 인스턴스가 만들어진다 — `ref.watch(adGateProvider)`를 쓰는 위젯이
/// 그대로 재빌드된다(§4.2 "구매가 세션 중간에 성공하면 배너가 사라지며
/// 레이아웃이 1회 줄어든다"가 이 재계산으로 성립한다).
final adGateProvider = Provider<AdGate>((ref) {
  final adsRemoved = ref.watch(adsRemovedProvider).valueOrNull ?? false;
  final bannerHeight = ref.watch(bannerHeightProvider);
  final suppressedUntil = ref.watch(_bannerSuppressedUntilProvider);
  final pendingInterstitial = ref.watch(_pendingInterstitialProvider);
  final transitionInFlight = ref.watch(_interstitialTransitionInFlightProvider);
  final interstitial = ref.watch(interstitialControllerProvider);

  return AdGate._(
    adsRemoved: adsRemoved,
    bannerHeight: bannerHeight,
    suppressedUntil: suppressedUntil,
    pendingInterstitial: pendingInterstitial,
    transitionInFlight: transitionInFlight,
    interstitial: interstitial,
    now: DateTime.now,
    setSuppressedUntil: (value) =>
        ref.read(_bannerSuppressedUntilProvider.notifier).state = value,
    setPendingInterstitial: (value) =>
        ref.read(_pendingInterstitialProvider.notifier).state = value,
    setTransitionInFlight: (value) =>
        ref.read(_interstitialTransitionInFlightProvider.notifier).state =
            value,
  );
});
