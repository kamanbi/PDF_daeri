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

  group('ImageQualityProfile.original — 원본 화질(§76 §1.3)', () {
    test('재인코딩을 하지 않는 패스스루 프리셋이다', () {
      expect(ImageQualityProfile.original.isPassthrough, isTrue);
      expect(ImageQualityProfile.original.longEdgeMaxPx, ImageQualityProfile.unboundedLongEdgePx);
      expect(ImageQualityProfile.original.jpegQuality, 100);
      expect(
        ImageQualityProfile.high.isPassthrough,
        isFalse,
        reason: 'high는 여전히 2480px 상한을 가진 별개 프리셋이다(§76 §1.1 — high를 무제한으로 바꾸지 않는다)',
      );
    });

    test('of(original)이 original 프로필을 반환한다', () {
      expect(ImageQualityProfile.of(ImageQuality.original), same(ImageQualityProfile.original));
    });

    test('estimateFor가 "원본 크기 그대로" 문구를 반환한다(N.NMB~N.NMB 형태로 나오지 않는다)', () {
      final text = ImageQualityProfile.original.estimateFor(10 * 1024 * 1024);
      expect(text, contains('원본 크기 그대로'));
      expect(text, isNot(contains('~')));
    });
  });

  group('T4 — CompressLadder.rungs[0..2]는 ImageQualityProfile.high/standard/min과 수치가 갈리지 않는다', () {
    test('longEdgeMaxPx/jpegQuality가 세 프리셋과 각각 일치한다', () {
      expect(CompressLadder.rungs[0].longEdgeMaxPx, ImageQualityProfile.high.longEdgeMaxPx);
      expect(CompressLadder.rungs[0].jpegQuality, ImageQualityProfile.high.jpegQuality);
      expect(CompressLadder.rungs[1].longEdgeMaxPx, ImageQualityProfile.standard.longEdgeMaxPx);
      expect(CompressLadder.rungs[1].jpegQuality, ImageQualityProfile.standard.jpegQuality);
      expect(CompressLadder.rungs[2].longEdgeMaxPx, ImageQualityProfile.min.longEdgeMaxPx);
      expect(CompressLadder.rungs[2].jpegQuality, ImageQualityProfile.min.jpegQuality);
    });

    test('3..4단은 목표 전용 하위 단(1000px/50, 800px/40)이다', () {
      expect(CompressLadder.rungs[3].longEdgeMaxPx, 1000);
      expect(CompressLadder.rungs[3].jpegQuality, 50);
      expect(CompressLadder.rungs[4].longEdgeMaxPx, 800);
      expect(CompressLadder.rungs[4].jpegQuality, 40);
      expect(CompressLadder.rungs.length, 5);
    });

    test('indexOf가 사용자 프리셋 3종을 사다리 인덱스로 정확히 매핑한다', () {
      expect(CompressLadder.indexOf(ImageQuality.high), 0);
      expect(CompressLadder.indexOf(ImageQuality.standard), 1);
      expect(CompressLadder.indexOf(ImageQuality.min), 2);
    });

    test('indexOf(original)은 패스스루라 사다리에 없어 예외를 던진다(§76 §1.5)', () {
      expect(() => CompressLadder.indexOf(ImageQuality.original), throwsArgumentError);
    });

    test('startIndexFor: 큰 목표는 고화질 단을 그대로 선택한다', () {
      const originalBytes = 10 * 1024 * 1024;
      final i = CompressLadder.startIndexFor(originalBytes: originalBytes, targetBytes: originalBytes);
      expect(i, 0);
    });

    test('startIndexFor: 매우 작은 목표는 마지막 단(4)으로 떨어진다', () {
      const originalBytes = 10 * 1024 * 1024;
      final i = CompressLadder.startIndexFor(originalBytes: originalBytes, targetBytes: 1);
      expect(i, CompressLadder.rungs.length - 1);
    });

    test('startIndexFor는 파일 I/O 없이 산술만으로 계산된다(originalBytes<=0이면 마지막 단)', () {
      final i = CompressLadder.startIndexFor(originalBytes: 0, targetBytes: 100);
      expect(i, CompressLadder.rungs.length - 1);
    });
  });
}
