/// 배너 배치의 단일 구현. (설계 `_workspace/52_architect_week4_design.md` §1 전체)
///
/// **어떤 화면도 `BannerAd`/`AdWidget`을 직접 만들지 않는다.** 화면이 아는 것은
/// [BannerHost] 위젯 하나와 [BannerHost.contentBottomPadding] 헬퍼 하나뿐이다
/// (§1.1 공개 계약). 항상 `Scaffold.bottomNavigationBar`에만 놓는다 — body 안에
/// 넣지 않는다(스크롤·SafeArea 계산이 화면마다 갈라지는 것을 막기 위함).
///
/// `adsRemoved`를 이 파일이 직접 읽는 것은 §4.3 검사28 위반이 아니다 — 검사28은
/// `lib/ads/**`·`lib/billing/**`·`settings_screen.dart` **밖**에서 읽는 것만 막는다.
/// 다만 배너를 **붙여도 되는가**(로드·표시 여부)의 판단은 여전히 [AdGate] 하나로
/// 몰아 둔다 — 이 파일이 직접 읽는 `adsRemoved`는 오직 I-AD1의 유일한 예외
/// (구매 시 예약 높이 자체를 0으로 접는 것)를 구현하기 위해서다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../billing/entitlement.dart';
import '../core/platform_features.dart';
import 'ad_gate.dart';
import 'ad_ids.dart';
import 'ads_bootstrap.dart';

/// 배너를 붙일 수 있는 4개 지점. `ads.md` 노출 지점 표와 1:1 대응한다.
/// **이 enum에 값을 추가하는 것은 광고 지점 추가**이므로 절대 규칙 7에 걸린다.
/// S2(스캔)·시스템 파일 선택기는 여기에 없다 — 없는 것이 계약이다.
enum BannerSlot { home, viewer, edit, settings }

/// "지금 드래그 중" 신호의 단일 소유 provider(§1.4 방어 3). [BannerHost]만 이
/// 값을 소비한다. 화면(`page_grid_editor.dart`)은 set만 하고, 배너가 어떻게
/// 반응하는지 알지 못한다.
final bannerDragAvoidProvider = StateProvider<bool>((ref) => false);

/// 화면 하단 배너. **항상 `Scaffold.bottomNavigationBar`에만 놓는다.**
class BannerHost extends ConsumerStatefulWidget {
  const BannerHost({super.key, required this.slot});

  final BannerSlot slot;

  /// 방어 2 — 완충 밴드(§1.3). 배너 바로 위에 요소를 두지 않기 위한 높이.
  static const double bufferBandHeight = 24.0;

  /// 마지막 스크롤 요소가 밴드에 딱 붙지 않게 하는 여유(§1.2 산식 주석).
  static const double contentTailPadding = 8.0;

  /// 스크롤 영역 하단 패딩(방어 2 — 완충 밴드). 스크롤을 가진 화면(S1 홈
  /// CustomScrollView, S3 편집 그리드, S5 설정 ListView)은 **반드시** 이 값을
  /// 마지막 sliver/리스트의 bottom padding에 더한다. 광고 제거 구매 시 0을
  /// 돌려주므로 화면 코드에 분기가 생기지 않는다.
  static double contentBottomPadding(WidgetRef ref) {
    final adsRemoved = ref.watch(adsRemovedProvider).valueOrNull ?? false;
    final height = ref.watch(bannerHeightProvider);
    if (adsRemoved || height == null) return 0;
    return height + bufferBandHeight + contentTailPadding;
  }

  @override
  ConsumerState<BannerHost> createState() => _BannerHostState();
}

class _BannerHostState extends ConsumerState<BannerHost> {
  BannerAd? _ad;
  bool _loading = false;
  bool _failed = false; // 로드 실패 후 재시도하지 않는다(§1.6) — reserved 유지.
  bool _lastDragAvoid = false;

  Timer? _suppressRebuildTimer;
  Timer? _dragSafetyTimer;

  @override
  void dispose() {
    _suppressRebuildTimer?.cancel();
    _dragSafetyTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  /// 전면 종료 후 배너 억제(suppressed) 구간이 끝나는 시각에 맞춰 1회 재빌드를
  /// 예약한다. `_bannerSuppressedUntilProvider`(ad_gate.dart 내부 전용)는
  /// **값이 바뀔 때만** 리스너를 깨우므로, 시간이 그냥 흘러 억제가 풀리는
  /// 순간은 provider 스스로 알리지 않는다 — 그래서 이 타이머가 필요하다.
  void _scheduleSuppressRebuild(DateTime until) {
    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    _suppressRebuildTimer?.cancel();
    _suppressRebuildTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  /// 방어 1 — 높이 선점(§1.2). 화면 진입당 로드 시도 1회, 재시도 없음(§1.6).
  void _maybeLoad(int height, double widthDp) {
    if (_ad != null || _loading || _failed) return;
    _loading = true;
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize(width: widthDp.truncate(), height: height),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() {
            _loading = false;
            _ad = loadedAd as BannerAd;
          });
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (!mounted) return;
          setState(() {
            _loading = false;
            _failed = true;
          });
        },
      ),
    );
    ad.load();
  }

  /// 방어 3 — 드래그 회피(§1.4). 신호 누수 방어: true가 10초 이상 지속되면
  /// 스스로 복귀한다.
  void _syncDragAvoidSafety(bool avoid) {
    if (avoid == _lastDragAvoid) return;
    _lastDragAvoid = avoid;
    _dragSafetyTimer?.cancel();
    if (avoid) {
      _dragSafetyTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) ref.read(bannerDragAvoidProvider.notifier).state = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 68 §5.2: 광고 SDK가 없는 플랫폼에서는 자리 자체를 만들지 않는다.
    if (!AppFeatures.ads) return const SizedBox.shrink();

    final adsRemoved = ref.watch(adsRemovedProvider).valueOrNull ?? false;
    final height = ref.watch(bannerHeightProvider);

    // removed(§4.2)·disabled(§1.2 해석 실패) — 높이 0, 위젯 없음. I-AD1의
    // 유일한 예외.
    if (adsRemoved || height == null) {
      final ad = _ad;
      if (ad != null) {
        _ad = null;
        ad.dispose();
      }
      return const SizedBox.shrink();
    }

    final adGate = ref.watch(adGateProvider);
    final dragAvoid = ref.watch(bannerDragAvoidProvider);
    _syncDragAvoidSafety(dragAvoid);

    final suppressedUntil = adGate.bannerSuppressedUntil;
    if (suppressedUntil != null) {
      _scheduleSuppressRebuild(suppressedUntil);
    }

    final allowed = adGate.bannerAllowed;
    if (allowed) {
      final widthDp = MediaQuery.of(context).size.width;
      _maybeLoad(height, widthDp);
    }

    final showAd = allowed && _ad != null;
    final reservedHeight = height + BannerHost.bufferBandHeight;

    // 시스템 제스처/내비게이션 영역은 배너의 일부가 아니다. 하단 SafeArea가
    // 광고와 완충 밴드 전체를 위로 올리며, Scaffold가 늘어난 높이를 body에서
    // 자동으로 제외하므로 화면별 inset 계산이 추가되지 않는다.
    return SafeArea(
      top: false,
      child: SizedBox(
        height: reservedHeight,
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 방어 2 — 완충 밴드. 인터랙션 없음, 배경색 없음(§1.3).
            const IgnorePointer(
              child: SizedBox(height: BannerHost.bufferBandHeight, width: double.infinity),
            ),
            SizedBox(
              height: height.toDouble(),
              width: double.infinity,
              child: AnimatedContainer(
                // 방어 3: 160ms easeOutCubic, 복귀도 동일(§1.4).
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(0, dragAvoid ? reservedHeight : 0, 0),
                child: showAd
                    ? Center(
                        child: SizedBox(
                          width: _ad!.size.width.toDouble(),
                          height: _ad!.size.height.toDouble(),
                          child: AdWidget(ad: _ad!),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
