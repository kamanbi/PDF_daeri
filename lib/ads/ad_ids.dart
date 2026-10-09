import 'package:flutter/foundation.dart';

/// 광고 단위 ID 단일 소유 — 52_architect_week4_design.md §5.2.
///
/// **실제 광고 단위 ID는 이 파일에 없다.** `--dart-define`으로 빌드 시 주입한다:
/// ```
/// flutter build appbundle \
///   --dart-define=ADMOB_BANNER_UNIT_ID=<F:\keys\PDF_daeri\.env 참조> \
///   --dart-define=ADMOB_INTERSTITIAL_UNIT_ID=<F:\keys\PDF_daeri\.env 참조>
/// flutter build ipa \
///   --dart-define=ADMOB_IOS_BANNER_UNIT_ID=<.env 참조> \
///   --dart-define=ADMOB_IOS_INTERSTITIAL_UNIT_ID=<.env 참조>
/// ```
///
/// App ID는 이 파일과 무관하다 — Android는 `android/ads.properties` + gradle
/// `manifestPlaceholders`(§5.1), iOS는 `Info.plist`의 `GADApplicationIdentifier`
/// (`$(ADMOB_IOS_APP_ID)`, Codemagic 변수)로 별도 주입된다.
abstract final class AdIds {
  // 구글 공식 테스트 단위(공개 상수 — 비밀이 아니다).
  // CLAUDE.md "개발·테스트 중에는 AdMob 테스트 광고 단위 ID 사용".
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testIosBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const _testIosInterstitial = 'ca-app-pub-3940256099942544/4411468910';

  static const _banner = String.fromEnvironment('ADMOB_BANNER_UNIT_ID');
  static const _interstitial = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_UNIT_ID',
  );
  static const _iosBanner = String.fromEnvironment('ADMOB_IOS_BANNER_UNIT_ID');
  static const _iosInterstitial = String.fromEnvironment(
    'ADMOB_IOS_INTERSTITIAL_UNIT_ID',
  );

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  /// **디버그 빌드에서만** Google 테스트 ID를 쓴다. 릴리스는 빌드 스크립트가
  /// 실제 단위 ID 누락을 실패로 처리하므로 테스트 광고로 폴백하지 않는다.
  static String get banner => kReleaseMode
      ? (_isIos ? _iosBanner : _banner)
      : (_isIos ? _testIosBanner : _testBanner);

  static String get interstitial => kReleaseMode
      ? (_isIos ? _iosInterstitial : _interstitial)
      : (_isIos ? _testIosInterstitial : _testInterstitial);

  /// 릴리스인데 정의가 비어 있다 = 실수로 테스트 광고를 달고 출시하려는 상태.
  static bool get isMisconfiguredRelease =>
      kReleaseMode &&
      (_isIos
          ? (_iosBanner.isEmpty || _iosInterstitial.isEmpty)
          : (_banner.isEmpty || _interstitial.isEmpty));
}
