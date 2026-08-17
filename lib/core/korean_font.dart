/// 한글 폰트(Noto Sans KR) 로딩 단일 구현. (설계 §9.2)
///
/// - 바이트만 제공한다. 그리기·폰트 등록은 `pdf/image_pdf_builder.dart`(pdf-core)가 한다.
/// - **메인 isolate에서만** 호출 가능(`rootBundle` 사용). 워커 isolate에는 `bytes()`가
///   반환한 `Uint8List`를 미리 로드해 넘긴다(§8.2).
library;

import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

abstract final class KoreanFont {
  static const String assetPath = 'assets/fonts/NotoSansKR-Regular.ttf';

  static Uint8List? _cached;
  static bool _warmedUp = false;

  static bool get isLoaded => _cached != null;

  /// 앱 시작 시 1회 호출한다(`main()`에서 `Workspace.ensureLayout()` 직후).
  /// 폰트 파일이 아직 없어도 앱을 죽이지 않는다 — 실패를 로그로만 남긴다.
  /// 실제 저장 시점에 폰트가 필요한 코드는 [bytes]를 직접 호출해 명시적으로
  /// [KoreanFontMissing]을 받아 처리해야 한다.
  static Future<void> warmUp() async {
    if (_warmedUp) return;
    _warmedUp = true;
    try {
      await bytes();
    } on KoreanFontMissing catch (e) {
      developer.log(
        '한글 폰트 로딩 실패: $assetPath 를 찾을 수 없습니다. '
        'PDF에 한글 텍스트를 그리는 지점에서 "□□□"가 출력될 수 있습니다. '
        'assets/fonts/NotoSansKR-Regular.ttf 배치 여부를 확인하세요.',
        name: 'KoreanFont',
        level: 900, // WARNING
        error: e,
      );
    }
  }

  /// 폰트 바이트를 반환한다. 없으면 [KoreanFontMissing]을 던진다(앱 크래시 아님 —
  /// 호출자가 `try/catch`로 받아 PdfFailure 등으로 변환해야 한다).
  static Future<Uint8List> bytes() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(assetPath);
      final result = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _cached = result;
      return result;
    } catch (e) {
      throw KoreanFontMissing(assetPath, e);
    }
  }
}

/// [KoreanFont.assetPath]에 폰트 파일이 없을 때 던지는 명시적 예외.
/// `PdfFailure`(pdf-core 소유)로 감싸는 것은 호출부의 책임이다.
class KoreanFontMissing implements Exception {
  const KoreanFontMissing(this.assetPath, this.cause);
  final String assetPath;
  final Object cause;

  @override
  String toString() => 'KoreanFontMissing($assetPath): $cause';
}
