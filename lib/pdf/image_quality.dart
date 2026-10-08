/// 이미지 화질 프리셋 — 편집 저장(`pdf_engine.dart`)과 압축(`pdf_compressor.dart`) 양쪽이
/// 공유하는 타입이다. 이 타입 하나만을 위해 두 파일이 서로 import하게 되는 것을 막기 위해
/// (§6.4 자동 검사 19 — `pdf_compressor.dart` ↔ `pdf_engine.dart` 상호 import 금지) 별도
/// 파일로 뺐다.
///
/// `pdf_engine.dart`는 하위 호환을 위해 이 타입을 `export`한다 — 기존에
/// `import 'pdf_engine.dart'`로 `ImageQuality`를 쓰던 코드는 한 글자도 바뀌지 않는다
/// (§2.3/§2.6 공개 시그니처 무변경 원칙 유지).
library;

enum ImageQuality { original, high, standard, min }

/// 저장·압축이 공유하는 이미지 화질 정책의 단일 소유자.
class ImageQualityProfile {
  const ImageQualityProfile({
    required this.quality,
    required this.label,
    required this.recommendedFor,
    required this.longEdgeMaxPx,
    required this.jpegQuality,
    required this.estimatedMinRatio,
    required this.estimatedMaxRatio,
  });

  final ImageQuality quality;
  final String label;
  final String recommendedFor;
  final int longEdgeMaxPx;
  final int jpegQuality;
  final double estimatedMinRatio;
  final double estimatedMaxRatio;

  static const high = ImageQualityProfile(
    quality: ImageQuality.high,
    label: '고화질',
    recommendedFor: '도면·작은 글씨',
    longEdgeMaxPx: 2480,
    jpegQuality: 85,
    estimatedMinRatio: 0.55,
    estimatedMaxRatio: 0.90,
  );
  static const standard = ImageQualityProfile(
    quality: ImageQuality.standard,
    label: '기본',
    recommendedFor: '일반 문서에 권장',
    longEdgeMaxPx: 1754,
    jpegQuality: 75,
    estimatedMinRatio: 0.35,
    estimatedMaxRatio: 0.65,
  );
  static const min = ImageQualityProfile(
    quality: ImageQuality.min,
    label: '최소',
    recommendedFor: '메일·메신저 첨부',
    longEdgeMaxPx: 1240,
    jpegQuality: 60,
    estimatedMinRatio: 0.20,
    estimatedMaxRatio: 0.45,
  );

  /// 재인코딩을 하지 않는다는 뜻의 센티널. `encodeForEmbed`의 A-4 스킵 조건
  /// `longEdge <= longEdgeMaxPx`가 어떤 실사 이미지에서도 참이 되도록 잡는다.
  /// 실제 카메라 센서 장변은 1e4px를 넘지 않으므로 1<<24로 충분하다(§76 §1.3).
  static const int unboundedLongEdgePx = 1 << 24;

  static const original = ImageQualityProfile(
    quality: ImageQuality.original,
    label: '원본',
    recommendedFor: '원본 해상도 그대로 (용량 큼)',
    longEdgeMaxPx: unboundedLongEdgePx,
    jpegQuality: 100, // 크롭이 걸린 페이지에만 실제로 쓰인다(§76 §1.2)
    estimatedMinRatio: 1.00,
    estimatedMaxRatio: 1.00,
  );

  static ImageQualityProfile of(ImageQuality quality) => switch (quality) {
    ImageQuality.original => original,
    ImageQuality.high => high,
    ImageQuality.standard => standard,
    ImageQuality.min => min,
  };

  /// 재인코딩 없이 원본 바이트를 그대로 임베드하는 프리셋인가.
  /// 압축 경로가 이 프리셋을 거부할 때 쓰는 유일한 판별자다(§76 §1.5).
  bool get isPassthrough => longEdgeMaxPx >= unboundedLongEdgePx;

  String get processingDescription => processingDescriptionFor();

  /// [tr]은 UI 쪽이 넘기는 번역 함수(한국어 키 → 현재 언어). 이 파일은 context가
  /// 없는 순수 모델이라 기본값은 한국어 그대로(항등)다.
  String processingDescriptionFor({String Function(String key) tr = _identity}) =>
      tr('장변 최대 {px}px · JPEG 품질 {quality}')
          .replaceAll('{px}', '$longEdgeMaxPx')
          .replaceAll('{quality}', '$jpegQuality');

  String estimateFor(int inputBytes, {String Function(String key) tr = _identity}) {
    if (inputBytes <= 0) return tr('사진 크기를 확인하면 예상 용량을 표시합니다.');
    if (isPassthrough) {
      return tr('원본 크기 그대로 ({size})').replaceAll('{size}', formatBytes(inputBytes));
    }
    final minBytes = (inputBytes * estimatedMinRatio).round();
    final maxBytes = (inputBytes * estimatedMaxRatio).round();
    return tr('사진 기준 예상 {min} ~ {max}')
        .replaceAll('{min}', formatBytes(minBytes))
        .replaceAll('{max}', formatBytes(maxBytes));
  }

  static String _identity(String key) => key;

  static String formatBytes(int bytes) {
    const bytesPerMb = 1024 * 1024;
    if (bytes >= bytesPerMb) {
      return '${(bytes / bytesPerMb).toStringAsFixed(1)}MB';
    }
    const bytesPerKb = 1024;
    return '${(bytes / bytesPerKb).toStringAsFixed(0)}KB';
  }
}

/// 목표 용량 모드에서만 쓰는 화질 단 하나. 사용자에게 직접 노출하지 않는다(§76 §3.2).
class CompressRung {
  const CompressRung({required this.longEdgeMaxPx, required this.jpegQuality});
  final int longEdgeMaxPx;
  final int jpegQuality;
}

/// 목표 용량 모드 전용 화질 사다리. 인덱스가 작을수록 고화질이다.
/// 0..2는 사용자 프리셋(high/standard/min)과 **같은 수치**이며, 3..4는 목표
/// 용량 모드에서만 도달할 수 있는 하위 단이다(UI에 노출하지 않는다). (§76 §3.2)
abstract final class CompressLadder {
  /// 0..2는 `ImageQualityProfile.high/standard/min`의 값을 **참조로 생성**한다
  /// (리터럴 재기재 금지 — 두 표가 갈라지는 것을 코드 구조로 막는다, spec-guardian C1).
  static final List<CompressRung> rungs = [
    CompressRung(
      longEdgeMaxPx: ImageQualityProfile.high.longEdgeMaxPx,
      jpegQuality: ImageQualityProfile.high.jpegQuality,
    ), // 0 = high
    CompressRung(
      longEdgeMaxPx: ImageQualityProfile.standard.longEdgeMaxPx,
      jpegQuality: ImageQualityProfile.standard.jpegQuality,
    ), // 1 = standard
    CompressRung(
      longEdgeMaxPx: ImageQualityProfile.min.longEdgeMaxPx,
      jpegQuality: ImageQualityProfile.min.jpegQuality,
    ), // 2 = min
    const CompressRung(longEdgeMaxPx: 1000, jpegQuality: 50), // 3 = 목표 전용
    const CompressRung(longEdgeMaxPx: 800, jpegQuality: 40), // 4 = 목표 전용
  ];

  /// 사용자 프리셋을 사다리 인덱스로 변환한다. `original`은 패스스루 프리셋이라
  /// 사다리에 없다(§76 §1.5) — 호출하면 프로그래밍 오류로 취급해 예외를 던진다.
  static int indexOf(ImageQuality preset) => switch (preset) {
    ImageQuality.high => 0,
    ImageQuality.standard => 1,
    ImageQuality.min => 2,
    ImageQuality.original => throw ArgumentError(
      'ImageQuality.original is passthrough and is not on CompressLadder (§76 §1.5)',
    ),
  };

  /// 예상 비율(`estimatedMaxRatio`)로 **파일을 전혀 읽지 않고** 시작 단을 고른다.
  /// 목표를 만족할 것으로 예상되는 가장 고화질 단(0..2 중). 없으면 마지막 단.
  static int startIndexFor({required int originalBytes, required int targetBytes}) {
    if (originalBytes <= 0) return rungs.length - 1;
    for (final profile in [
      ImageQualityProfile.high,
      ImageQualityProfile.standard,
      ImageQualityProfile.min,
    ]) {
      final predictedBytes = (originalBytes * profile.estimatedMaxRatio).round();
      if (predictedBytes <= targetBytes) return indexOf(profile.quality);
    }
    return rungs.length - 1;
  }
}
