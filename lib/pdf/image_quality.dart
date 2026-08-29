/// 이미지 화질 프리셋 — 편집 저장(`pdf_engine.dart`)과 압축(`pdf_compressor.dart`) 양쪽이
/// 공유하는 타입이다. 이 타입 하나만을 위해 두 파일이 서로 import하게 되는 것을 막기 위해
/// (§6.4 자동 검사 19 — `pdf_compressor.dart` ↔ `pdf_engine.dart` 상호 import 금지) 별도
/// 파일로 뺐다.
///
/// `pdf_engine.dart`는 하위 호환을 위해 이 타입을 `export`한다 — 기존에
/// `import 'pdf_engine.dart'`로 `ImageQuality`를 쓰던 코드는 한 글자도 바뀌지 않는다
/// (§2.3/§2.6 공개 시그니처 무변경 원칙 유지).
library;

enum ImageQuality { high, standard, min }

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

  static ImageQualityProfile of(ImageQuality quality) => switch (quality) {
    ImageQuality.high => high,
    ImageQuality.standard => standard,
    ImageQuality.min => min,
  };

  String get processingDescription =>
      '장변 최대 ${longEdgeMaxPx}px · JPEG 품질 $jpegQuality';

  String estimateFor(int inputBytes) {
    if (inputBytes <= 0) return '사진 크기를 확인하면 예상 용량을 표시합니다.';
    final minBytes = (inputBytes * estimatedMinRatio).round();
    final maxBytes = (inputBytes * estimatedMaxRatio).round();
    return '사진 기준 예상 ${formatBytes(minBytes)} ~ ${formatBytes(maxBytes)}';
  }

  static String formatBytes(int bytes) {
    const bytesPerMb = 1024 * 1024;
    if (bytes >= bytesPerMb) {
      return '${(bytes / bytesPerMb).toStringAsFixed(1)}MB';
    }
    const bytesPerKb = 1024;
    return '${(bytes / bytesPerKb).toStringAsFixed(0)}KB';
  }
}
