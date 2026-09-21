// `stamp_builder.dart` 단위 테스트 — `_workspace/79_architect_v1.1_v2_design.md` §9 T1·T2·T4·T5·T6.
//
// T3-a/T3-b(무손실 불변식)는 실제 qpdf overlay 파이프라인을 태워야 하므로 별도 파일
// `test/pdf/pdf_engine_stamp_test.dart`에 있다. 이 파일은 `StampBuilder`/`buildOverlayJob`
// 자체의 순수 함수 계약만 검증한다(FFI 불필요, 모든 플랫폼에서 항상 돈다).
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/pdf/qpdf_isolate.dart' show buildOverlayJob;
import 'package:pdf_daeri/pdf/stamp_builder.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// 최소한의 유효 PNG(1x1 투명 픽셀) — 디코드 가능 여부는 `pw.MemoryImage`가 신경 쓰지
/// 않는다(바이트만 그대로 임베드). 유효한 PNG 시그니처만 있으면 `doc.save()`가 성공한다.
Uint8List _tinyPng() {
  // 1x1 투명 PNG, base64 리터럴을 손으로 풀지 않고 표준 최소 PNG 바이트를 그대로 적는다.
  return Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk header
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // bit depth 8, color type 6(RGBA)
    0x89,
    0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk header
    0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // minimal deflate data
    0x0D, 0x0A, 0x2D, 0xB4, // CRC
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk header
    0xAE, 0x42, 0x60, 0x82, // CRC
  ]);
}

void main() {
  group('T1 : StampBuilder.build — 페이지 수·크기 1:1, 빈 마크 페이지도 생성된다', () {
    test('마크가 있는 페이지 1장 + 마크 없는 페이지 1장 -> 결과도 2페이지', () async {
      final result = await StampBuilder.build(
        pages: [
          StampPageSpec(
            widthPt: 200,
            heightPt: 300,
            marks: [
              HighlightMark(rect: const StampRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2), colorArgb: 0xFFFFFF00),
            ],
          ),
          const StampPageSpec(widthPt: 200, heightPt: 300, marks: []),
        ],
      );

      expect(result.error, isNull, reason: '빌드 실패: ${result.error}');
      final bytes = result.pdfBytes!;
      final doc = await pdfrx.PdfDocument.openData(bytes);
      try {
        expect(doc.pages.length, 2, reason: '마크 없는 페이지가 건너뛰어졌다');
      } finally {
        await doc.dispose();
      }
    });

    test('pages가 비어 있으면 emptySpec 실패를 반환한다(예외를 던지지 않는다)', () async {
      final result = await StampBuilder.build(pages: const []);
      expect(result.error, StampBuildError.emptySpec);
      expect(result.pdfBytes, isNull);
    });
  });

  group('T2 : buildOverlayJob — to/from이 1-N으로 동일, repeat 키가 없다', () {
    test('pageCount=5 -> overlay.to == overlay.from == "1-5", repeat 없음', () {
      final job = buildOverlayJob(
        sourcePath: 'source.pdf',
        stampPath: 'stamp.pdf',
        outputPath: 'out.pdf',
        pageCount: 5,
      );
      final overlay = job['overlay']! as Map<String, Object?>;
      expect(overlay['to'], '1-5');
      expect(overlay['from'], '1-5');
      expect(overlay.containsKey('repeat'), isFalse);
      expect(overlay['file'], 'stamp.pdf');
      expect(job['inputFile'], 'source.pdf');
      expect(job['outputFile'], 'out.pdf');
    });
  });

  group('T4 : HighlightMark — Multiply 블렌드와 1.0 미만 ca가 존재한다', () {
    test('결과 PDF 바이트에 /Multiply와 /ca 항목이 있다(불투명 덮어쓰기 아님)', () async {
      final result = await StampBuilder.build(
        pages: [
          StampPageSpec(
            widthPt: 200,
            heightPt: 300,
            marks: [
              HighlightMark(
                rect: const StampRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
                colorArgb: 0xFFFFFF00,
                opacity: 0.35,
              ),
            ],
          ),
        ],
      );
      expect(result.error, isNull);
      // ExtGState 딕셔너리는 콘텐츠 스트림과 달리 압축 대상이 아니다 -- 원시 바이트에서
      // 바로 찾을 수 있다. latin1으로 디코드해 바이너리 구간이 섞여도 ASCII 토큰 탐색이
      // 깨지지 않게 한다.
      final text = String.fromCharCodes(result.pdfBytes!);
      expect(text, contains('/Multiply'), reason: 'Multiply 블렌드 모드가 없다');
      expect(RegExp(r'/ca\s+0\.').hasMatch(text), isTrue, reason: '1.0 미만 fillOpacity(/ca)가 없다');
    });
  });

  group('T5 : 한글 폰트 봉쇄 — TextMark + koreanFontBytes==null -> fontMissing', () {
    test('TextMark가 있는데 폰트가 없으면 기본 폰트로 폴백하지 않고 fontMissing을 반환한다', () async {
      final result = await StampBuilder.build(
        pages: [
          StampPageSpec(
            widthPt: 200,
            heightPt: 300,
            marks: [
              const TextMark(
                rect: StampRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.2),
                text: '한글 텍스트',
                fontSizePt: 12,
              ),
            ],
          ),
        ],
        koreanFontBytes: null,
      );
      expect(result.error, StampBuildError.fontMissing);
      expect(result.pdfBytes, isNull);
    });

    test('ImageMark/HighlightMark만 있으면 폰트가 없어도 성공한다(텍스트가 없으므로)', () async {
      final result = await StampBuilder.build(
        pages: [
          StampPageSpec(
            widthPt: 200,
            heightPt: 300,
            marks: [ImageMark(rect: const StampRect(left: 0, top: 0, right: 0.3, bottom: 0.3), pngBytes: _tinyPng())],
          ),
        ],
        koreanFontBytes: null,
      );
      expect(result.error, isNull, reason: '빌드 실패: ${result.error}');
    });
  });

  group('T6 : isolate 직렬화 — toMap()/fromMap() 왕복 값 동등 + 실제 Isolate.spawn 왕복', () {
    test('ImageMark/HighlightMark/TextMark 3종 toMap -> fromMap 왕복이 원본과 값 동등하다', () {
      final imageMark = ImageMark(rect: const StampRect(left: 0, top: 0, right: 0.5, bottom: 0.5), pngBytes: _tinyPng());
      final highlightMark = const HighlightMark(
        rect: StampRect(left: 0.1, top: 0.1, right: 0.6, bottom: 0.2),
        colorArgb: 0xFFFFFF00,
        opacity: 0.4,
      );
      final textMark = const TextMark(
        rect: StampRect(left: 0.1, top: 0.5, right: 0.9, bottom: 0.6),
        text: '왕복 검증',
        fontSizePt: 14,
        colorArgb: 0xFF112233,
        invisible: true,
      );

      expect(StampMark.fromMap(imageMark.toMap()), imageMark);
      expect(StampMark.fromMap(highlightMark.toMap()), highlightMark);
      expect(StampMark.fromMap(textMark.toMap()), textMark);

      final spec = StampPageSpec(widthPt: 210, heightPt: 297, marks: [imageMark, highlightMark, textMark]);
      expect(StampPageSpec.fromMap(spec.toMap()), spec);
    });

    test('실제 Isolate.spawn 왕복 1회 — StampPageSpec.toMap()이 SendPort로 전송 가능하다', () async {
      final original = StampPageSpec(
        widthPt: 200,
        heightPt: 400,
        marks: [
          ImageMark(rect: const StampRect(left: 0, top: 0, right: 0.4, bottom: 0.4), pngBytes: _tinyPng()),
          const HighlightMark(rect: StampRect(left: 0.1, top: 0.1, right: 0.6, bottom: 0.2), colorArgb: 0xFF00FF00),
        ],
      );

      final receivePort = ReceivePort();
      await Isolate.spawn(_echoEntryPoint, (original.toMap(), receivePort.sendPort));
      final echoed = await receivePort.first as Map<Object?, Object?>;
      receivePort.close();

      final roundTripped = StampPageSpec.fromMap(echoed.cast<String, Object?>());
      expect(roundTripped, original);
    });
  });
}

/// T6 전용 isolate 진입점 — 받은 맵을 그대로 되돌려 보낸다(직렬화 가능성 자체를 증명하는 것이
/// 목적이며, `lib/pdf/**`의 허용 워커 파일(검사13) 목록을 늘리지 않기 위해 테스트 파일 안에
/// 둔다 -- `no_raster_test.dart`의 §3.4-13은 `lib/pdf/**`만 스캔하므로 여기는 대상이 아니다).
void _echoEntryPoint((Map<String, Object?>, SendPort) args) {
  final (map, sendPort) = args;
  sendPort.send(map);
}
