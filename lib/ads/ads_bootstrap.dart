/// 앱 부팅 단계 광고 SDK 배선 조각. (설계 `_workspace/52_architect_week4_design.md`
/// §1.2 방어 1(높이 선점)·§3.6 부팅 순서)
///
/// 이 파일이 제공하는 것은 부팅 단계에서 **호출할 함수 2개 + provider 1개**뿐이다.
/// `runApp` 이전에 실제로 호출하는 배선(§3.6 1~3단계, `main.dart` D-6)은 다음
/// 라운드의 몫이다 — 이 라운드(W4-T4/T5)는 `lib/billing/**`·`lib/ads/**`만 만든다.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 부팅에서 확정된 적응형 배너 높이(px, 논리 픽셀 아님 — `AdSize.height`는 dp).
/// `null` = 이번 실행에 배너를 아예 쓰지 않는다(§1.2 "해석 실패 → null → 배너
/// 없음"). `main.dart`가 §3.6 순서대로 [resolveAdaptiveBannerHeight] 결과로
/// override한다(D-6, 다음 라운드). 이 provider가 곧 §1.6 상태 머신의
/// `disabled`(`bannerHeight == null`) 진입 조건이다.
final bannerHeightProvider = Provider<int?>((ref) => null);

/// AdMob SDK 초기화(`MobileAds.instance.initialize()`). §3.6-2: `adsRemoved ==
/// false`일 때만 호출해야 한다는 판단은 **호출자의 책임**이다 — 이 함수 자체는
/// 판단하지 않는다(단일 게이트 원칙 §4는 `adsRemoved` 판단 지점을
/// `lib/ads/**`·`lib/billing/**`로 한정할 뿐, 어느 파일이 호출 여부를 결정해야
/// 하는지까지 정하지 않는다. 실제 호출 지점은 `main.dart`, 다음 라운드).
///
/// 실패해도 부팅을 막지 않는다 — 예외를 흡수하고 로그만 남긴다(기존 부팅
/// 시퀀스의 "각 단계 독립 실패 흡수" 관례, `main.dart` 참조).
Future<void> initializeMobileAds() async {
  try {
    await MobileAds.instance.initialize();
  } catch (e, st) {
    developer.log(
      'MobileAds.initialize 실패',
      name: 'ads_bootstrap',
      level: 900,
      error: e,
      stackTrace: st,
    );
  }
}

/// 적응형 배너 높이를 1회 해석한다(§1.2). **부팅 시 `runApp` 이전에만** 호출한다
/// — 위젯 build 안에서 await 하면 늦게 도착한 높이가 곧 레이아웃 점프가 된다.
///
/// [screenWidthDp]는 호출자가 `PlatformDispatcher.instance.views.first`의
/// `physicalSize.width / devicePixelRatio`로 구해 넘긴다(`MediaQuery`가 아직
/// 없는 시점이므로 이 함수 자체는 위젯 컨텍스트에 의존하지 않는다).
///
/// 실패(오프라인·SDK 초기화 실패) 또는 3초 타임아웃 시 `null`을 반환한다 —
/// 실패-닫힘(fail closed): 높이 0 + 배너 없음.
Future<int?> resolveAdaptiveBannerHeight(double screenWidthDp) async {
  try {
    final size =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
          screenWidthDp.truncate(),
        ).timeout(const Duration(seconds: 3));
    return size?.height;
  } catch (e, st) {
    developer.log(
      '적응형 배너 높이 해석 실패',
      name: 'ads_bootstrap',
      level: 900,
      error: e,
      stackTrace: st,
    );
    return null;
  }
}
