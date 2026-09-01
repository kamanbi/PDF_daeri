/// 플랫폼별 기능 가용성의 **단일 소유자**. (68 §4.3)
///
/// 이 파일 밖에서 `Platform.isWindows`/`Platform.isAndroid`로 기능 유무를 판단하지 않는다
/// — 자동 검사31이 이를 강제한다. 여기 없는 새 플래그가 필요하면 먼저 이 표를 갱신한다.
library;

import 'dart:io';

abstract final class AppFeatures {
  static final bool ads = Platform.isAndroid; // google_mobile_ads
  static final bool billing = Platform.isAndroid; // in_app_purchase
  static final bool storeUpdate = Platform.isAndroid; // PlayUpdateService, in_app_review
  static final bool scan = Platform.isAndroid; // doclens 카메라 스캔
  static final bool intentImport = Platform.isAndroid; // content:// VIEW 인텐트
  static final bool publicExport = true; // 구현체만 갈린다(§3.4)
}
