import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';

void main() {
  group('ImageQualityProfile', () {
    test('세 화질은 인코딩 기준과 예상 용량 범위를 각각 가진다', () {
      expect(ImageQualityProfile.high.longEdgeMaxPx, 2480);
      expect(ImageQualityProfile.standard.longEdgeMaxPx, 1754);
      expect(ImageQualityProfile.min.longEdgeMaxPx, 1240);
      expect(ImageQualityProfile.high.jpegQuality, 85);
      expect(ImageQualityProfile.standard.jpegQuality, 75);
      expect(ImageQualityProfile.min.jpegQuality, 60);
      expect(
        ImageQualityProfile.high.estimatedMinRatio,
        greaterThan(ImageQualityProfile.standard.estimatedMinRatio),
      );
      expect(
        ImageQualityProfile.standard.estimatedMinRatio,
        greaterThan(ImageQualityProfile.min.estimatedMinRatio),
      );
    });

    test('입력 사진 용량으로 예상 범위를 읽기 쉬운 단위로 표시한다', () {
      expect(
        ImageQualityProfile.high.estimateFor(10 * 1024 * 1024),
        '사진 기준 예상 5.5MB ~ 9.0MB',
      );
      expect(
        ImageQualityProfile.min.estimateFor(0),
        '사진 크기를 확인하면 예상 용량을 표시합니다.',
      );
    });
  });
}
