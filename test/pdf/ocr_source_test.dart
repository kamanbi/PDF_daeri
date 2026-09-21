// OcrSource 인터페이스 계약 검증(§7.3). 실제 ML Kit 호출(MlKitOcrSource)은 통합 테스트
// 대상이며 실기기 확인 항목이다 — 여기서는 인터페이스·값 타입 계약만 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/pdf/ocr_source.dart';
import 'package:pdf_daeri/pdf/stamp_builder.dart';

void main() {
  group('OcrWord/OcrPageResult', () {
    test('rect는 StampRect(0.0~1.0, 좌상단 원점)를 그대로 쓴다', () {
      const rect = StampRect(left: 0.1, top: 0.2, right: 0.5, bottom: 0.3);
      const word = OcrWord(text: '보고서', rect: rect);

      expect(word.text, '보고서');
      expect(word.rect, rect);
      expect(word.rect.widthFraction, closeTo(0.4, 1e-9));
    });

    test('words가 비어 있어도 fullText만으로 결과를 구성할 수 있다', () {
      const result = OcrPageResult(words: [], fullText: '');
      expect(result.words, isEmpty);
      expect(result.fullText, isEmpty);
    });

    test('한글 단어와 좌표를 여러 개 담을 수 있다(고정 테스트 데이터)', () {
      const words = [
        OcrWord(
          text: '2026년',
          rect: StampRect(left: 0.05, top: 0.05, right: 0.2, bottom: 0.1),
        ),
        OcrWord(
          text: '8월',
          rect: StampRect(left: 0.22, top: 0.05, right: 0.3, bottom: 0.1),
        ),
        OcrWord(
          text: '보고서',
          rect: StampRect(left: 0.32, top: 0.05, right: 0.5, bottom: 0.1),
        ),
        OcrWord(
          text: '(최종)',
          rect: StampRect(left: 0.52, top: 0.05, right: 0.68, bottom: 0.1),
        ),
      ];
      const result = OcrPageResult(
        words: words,
        fullText: '2026년 8월 보고서 (최종)',
      );

      expect(result.words, hasLength(4));
      expect(result.fullText, '2026년 8월 보고서 (최종)');
      expect(result.words.map((w) => w.text), [
        '2026년',
        '8월',
        '보고서',
        '(최종)',
      ]);
    });
  });

  group('OcrSource 구현체', () {
    test('recognize 성공 시 PdfOk<OcrPageResult>를 돌려준다', () async {
      final source = _FakeOcrSource(
        PdfOk(
          const OcrPageResult(
            words: [
              OcrWord(
                text: '테스트',
                rect: StampRect(left: 0, top: 0, right: 0.3, bottom: 0.1),
              ),
            ],
            fullText: '테스트',
          ),
        ),
      );

      final result = await source.recognize('/cache/scan.jpg');

      expect(result, isA<PdfOk<OcrPageResult>>());
      expect((result as PdfOk<OcrPageResult>).value.fullText, '테스트');
    });

    test('실패는 예외가 아니라 PdfErr로 반환한다', () async {
      final source = _FakeOcrSource(
        const PdfErr(SourceCorrupted('/cache/broken.jpg')),
      );

      final result = await source.recognize('/cache/broken.jpg');

      expect(result, isA<PdfErr<OcrPageResult>>());
      expect(
        (result as PdfErr<OcrPageResult>).failure,
        isA<SourceCorrupted>(),
      );
    });

    test('dispose는 플러그인 자원 해제를 호출부에 위임할 수 있다', () async {
      final source = _FakeOcrSource(
        const PdfOk(OcrPageResult(words: [], fullText: '')),
      );

      await source.dispose();

      expect(source.disposed, isTrue);
    });
  });
}

/// `OcrSource` 계약만 검증하기 위한 페이크. 실제 플러그인 타입을 전혀 참조하지 않는다 —
/// 이 자체가 §7.3의 "플러그인 타입이 인터페이스 밖으로 새지 않는다"는 격리를 테스트 층에서도
/// 보여준다.
class _FakeOcrSource implements OcrSource {
  _FakeOcrSource(this._result);

  final PdfResult<OcrPageResult> _result;
  bool disposed = false;

  @override
  Future<PdfResult<OcrPageResult>> recognize(String imagePath) async =>
      _result;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
