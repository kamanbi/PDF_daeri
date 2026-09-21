// `ocr_text_layer.dart` 단위 테스트 — `_workspace/79_architect_v1.1_v2_design.md` §7.4.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/pdf/ocr_source.dart';
import 'package:pdf_daeri/pdf/ocr_text_layer.dart';
import 'package:pdf_daeri/pdf/stamp_builder.dart';

void main() {
  group('ocrResultToStampSpec', () {
    test('OcrWord -> TextMark 변환: 좌표는 그대로, 폰트 크기는 rect 높이 비율 × 페이지 높이', () {
      const rect = StampRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.25);
      final ocrResult = OcrPageResult(
        words: const [OcrWord(text: '안녕', rect: rect)],
        fullText: '안녕',
      );

      final result = ocrResultToStampSpec(
        ocrResult: ocrResult,
        widthPt: 400,
        heightPt: 800,
        koreanFontBytes: Uint8List(4),
      );

      expect(result.error, isNull);
      final spec = result.spec!;
      expect(spec.widthPt, 400);
      expect(spec.heightPt, 800);
      expect(spec.marks, hasLength(1));

      final mark = spec.marks.single as TextMark;
      expect(mark.rect, rect);
      expect(mark.text, '안녕');
      expect(mark.invisible, isTrue);
      // heightFraction(0.05) * heightPt(800) * 0.8 = 32.0
      expect(mark.fontSizePt, closeTo(32.0, 0.001));
    });

    test('공백만 있는 단어는 스킵된다', () {
      const rect = StampRect(left: 0, top: 0, right: 1, bottom: 0.1);
      final ocrResult = OcrPageResult(
        words: const [OcrWord(text: '   ', rect: rect)],
        fullText: '   ',
      );

      final result = ocrResultToStampSpec(
        ocrResult: ocrResult,
        widthPt: 100,
        heightPt: 100,
        koreanFontBytes: Uint8List(4),
      );

      expect(result.error, isNull);
      expect(result.spec!.marks, isEmpty);
    });

    test('단어가 있는데 koreanFontBytes가 없으면 fontMissing 에러를 반환한다(예외 아님)', () {
      const rect = StampRect(left: 0, top: 0, right: 1, bottom: 0.1);
      final ocrResult = OcrPageResult(
        words: const [OcrWord(text: 'hello', rect: rect)],
        fullText: 'hello',
      );

      final result = ocrResultToStampSpec(
        ocrResult: ocrResult,
        widthPt: 100,
        heightPt: 100,
        koreanFontBytes: null,
      );

      expect(result.error, StampBuildError.fontMissing);
      expect(result.spec, isNull);
    });

    test('단어가 없으면 koreanFontBytes가 없어도 빈 spec을 반환한다', () {
      final ocrResult = const OcrPageResult(words: [], fullText: '');

      final result = ocrResultToStampSpec(
        ocrResult: ocrResult,
        widthPt: 100,
        heightPt: 100,
        koreanFontBytes: null,
      );

      expect(result.error, isNull);
      expect(result.spec!.marks, isEmpty);
    });
  });
}
