// `PdfEngine.stamp` 무손실 불변식 — `_workspace/79_architect_v1.1_v2_design.md` §9 T3-a·T3-b(§9.1
// 절차 그대로), T7. qpdf overlay를 실제로 태우므로 Windows `test/native/qpdf30.dll`이 필요하다
// (없으면 건너뛴다 — 기존 `pdf_engine_save_roundtrip_test.dart`/`size_guard_gate_test.dart`와 동일 관례).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/stamp_builder.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => '${Directory.current.path}/$_dllRelPath';
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();
final _ffiSkip = !_canRunFfi ? 'Windows qpdf30.dll 필요' : false;

const _fontPath = 'assets/fonts/NotoSansKR-Regular.ttf';
bool get _hasFont => File(_fontPath).existsSync();

/// 마커 생성기(기존 로드테스트와 동일 관례) — 부분 문자열 오탐 방지용 종결자.
String _m(int i, {String prefix = 'MARKER'}) => '${prefix}_${i}_END';

/// [count]페이지 텍스트 PDF. 페이지 i에 [_m](i) 마커가 유일하게 박힌다.
Future<String> _buildMarkerPdf(Directory dir, String fileName, int count) async {
  final doc = pw.Document();
  for (var i = 0; i < count; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text(_m(i)))));
  }
  final bytes = await doc.save();
  final path = '${dir.path}/$fileName';
  await File(path).writeAsBytes(bytes);
  return path;
}

/// 각 페이지의 텍스트 전문을 순서대로 읽는다.
Future<List<String>> _pageTexts(String path) async {
  final doc = await pdfrx.PdfDocument.openFile(path);
  try {
    final result = <String>[];
    for (final page in doc.pages) {
      final text = await page.loadText();
      result.add(text?.fullText ?? '');
    }
    return result;
  } finally {
    await doc.dispose();
  }
}

void main() {
  late Directory root;
  late QpdfPdfEngine engine;
  var docCounter = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_stamp_');
    engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _canRunFfi ? _dllPath : null);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String newOutputPath() {
    docCounter++;
    final stagingDir = Directory('${root.path}/docs/case$docCounter.tmp');
    stagingDir.createSync(recursive: true);
    return '${stagingDir.path}/document.pdf';
  }

  group('T3-a : ImageMark/HighlightMark만 얹으면 텍스트 추출이 적용 전과 바이트 단위로 동일하다', () {
    test('형광펜만 스탬프 -- 페이지 수 동일 + 각 페이지 텍스트가 전/후 완전히 같다', () async {
      final src = await _buildMarkerPdf(root, 'src.pdf', 3);
      final before = await _pageTexts(src);
      final sourceBytes = await File(src).readAsBytes();

      final stampResult = await StampBuilder.build(
        pages: [
          for (var i = 0; i < 3; i++)
            StampPageSpec(
              widthPt: 595.276,
              heightPt: 841.890,
              marks: [
                HighlightMark(
                  rect: const StampRect(left: 0.1, top: 0.1, right: 0.6, bottom: 0.2),
                  colorArgb: 0xFFFFFF00,
                ),
              ],
            ),
        ],
      );
      expect(stampResult.error, isNull, reason: '스탬프 빌드 실패: ${stampResult.error}');

      final outputPath = newOutputPath();
      final result = await engine.stamp(
        sourcePdfPath: src,
        stampPdfBytes: stampResult.pdfBytes!,
        pageCount: 3,
        outputPath: outputPath,
        guardInput: GuardInput(op: SaveOp.stamp, baselineBytes: sourceBytes.length, stampBytes: stampResult.pdfBytes!.length),
      );

      switch (result) {
        case PdfErr<SaveOutcome>():
          fail('stamp 실패: ${result.failure}');
        case PdfOk<SaveOutcome>():
          final after = await _pageTexts(result.value.outputPath);
          expect(after.length, before.length, reason: 'T3-a 페이지 수 불일치');
          for (var i = 0; i < before.length; i++) {
            expect(after[i], before[i], reason: 'T3-a 위치 $i 텍스트가 스탬프 전후 바이트 단위로 다르다');
          }
      }
    }, skip: _ffiSkip);
  });

  group('T3-b : TextMark(비가시 포함)은 원본 텍스트가 결과에 온전히 보존된다(§9.1 절차)', () {
    test('페이지 0에 비가시 TextMark 1개 -- 원본 마커가 결과에 부분열로 남는다', () async {
      if (!_hasFont) {
        markTestSkipped('$_fontPath 없음');
        return;
      }
      final src = await _buildMarkerPdf(root, 'src_text.pdf', 2);
      final before = await _pageTexts(src);
      final sourceBytes = await File(src).readAsBytes();
      final fontBytes = await File(_fontPath).readAsBytes();

      const addedText = 'OCR추가텍스트';
      final stampResult = await StampBuilder.build(
        pages: [
          StampPageSpec(
            widthPt: 595.276,
            heightPt: 841.890,
            marks: [
              const TextMark(
                rect: StampRect(left: 0.1, top: 0.8, right: 0.9, bottom: 0.9),
                text: addedText,
                fontSizePt: 10,
                invisible: true,
              ),
            ],
          ),
          const StampPageSpec(widthPt: 595.276, heightPt: 841.890, marks: []),
        ],
        koreanFontBytes: fontBytes,
      );
      expect(stampResult.error, isNull, reason: '스탬프 빌드 실패: ${stampResult.error}');

      final outputPath = newOutputPath();
      final result = await engine.stamp(
        sourcePdfPath: src,
        stampPdfBytes: stampResult.pdfBytes!,
        pageCount: 2,
        outputPath: outputPath,
        guardInput: GuardInput(op: SaveOp.stamp, baselineBytes: sourceBytes.length, stampBytes: stampResult.pdfBytes!.length),
      );

      switch (result) {
        case PdfErr<SaveOutcome>():
          fail('stamp 실패: ${result.failure}');
        case PdfOk<SaveOutcome>():
          final after = await _pageTexts(result.value.outputPath);
          // 단언 1: 페이지 수 동일.
          expect(after.length, before.length, reason: 'T3-b 단언1 페이지 수 불일치');
          // 단언 2: 모든 위치에서 원본 텍스트가 결과에 부분열로 그대로 남아있다.
          for (var i = 0; i < before.length; i++) {
            expect(
              after[i].contains(before[i]),
              isTrue,
              reason:
                  'T3-b 단언2 위치 $i 원본 텍스트가 보존되지 않았다(추측으로 기준을 바꾸지 않는다 -- '
                  '§9.1: (a) 규칙 4 위반 또는 (b) 추출 순서 오탐, M5로 판정 필요). '
                  'before="${before[i]}" after="${after[i]}"',
            );
          }
          // 단언 3: 페이지 0의 추가분은 공백을 제외하면 TextMark.text와 일치한다.
          final remainder = after[0].replaceFirst(before[0], '');
          final normalizedRemainder = remainder.replaceAll(RegExp(r'\s+'), '');
          final normalizedAdded = addedText.replaceAll(RegExp(r'\s+'), '');
          expect(
            normalizedRemainder,
            normalizedAdded,
            reason: 'T3-b 단언3 추가분이 의도한 TextMark.text와 다르다(다른 텍스트가 섞여 들어감)',
          );
      }
    }, skip: _ffiSkip);
  });

  group('T7 : SizeGuard — SaveOp.stamp 한계식 및 classify() 비관여', () {
    test('limitFor(stamp) == (baseline + stampBytes) * 1.15', () {
      const input = GuardInput(op: SaveOp.stamp, baselineBytes: 1000, stampBytes: 200);
      final limit = SizeGuard.limitFor(input);
      expect(limit, ((1000 + 200) * SizeGuard.stampOverheadRatio).floor());
      expect(SizeGuard.stampOverheadRatio, SizeGuard.composeOverheadRatio);
    });

    test('classify()는 stamp를 절대 반환하지 않는다(호출부가 명시적으로 지정하는 값)', () {
      // classify()는 PageRef 비교만으로 판정한다 -- stamp는 그 입력만으로 유도할 수 있는 개념이
      // 아니므로(§2.7), 어떤 before/after 조합을 넣어도 SaveOp.stamp가 나올 수 없다는 것을
      // enum 값 목록으로 고정한다(회귀: 향후 classify()에 stamp 분기가 실수로 추가되면 이 테스트가
      // stamp 분기 자체를 실행할 방법이 없으므로, 대신 소스에 'SaveOp.stamp'가 classify() 함수
      // 본문에 나타나지 않는지를 별도로 고정한다).
      final source = File('lib/core/size_guard.dart').readAsStringSync();
      final classifyBody = source.substring(source.indexOf('static SaveOp classify'));
      expect(
        classifyBody.contains('SaveOp.stamp'),
        isFalse,
        reason: 'classify() 본문에 SaveOp.stamp가 등장함 -- 스탬프는 호출부가 명시적으로 지정해야 한다(§2.7)',
      );
    });
  });
}
