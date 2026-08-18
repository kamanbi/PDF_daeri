// RO(Reopen-Or-It-Didn't-Happen) 회귀 테스트 -- 설계 §4.5, `9x_architect_verdict.md` §9.5.
//
// 배경: `PdfrxPdfEngine.save()`가 반환하는 `{'ok','bytes','pageCount'}`만 확인하는 테스트는
// pdfrx_engine 0.4.6의 무음 실패(§9.1 -- 삭제·순서변경이 setter/assemble 사이에서 소실되고
// 원본이 그대로 저장됨)를 전혀 잡지 못했다. `pageCount`는 우리가 요청한 값의 메아리일 뿐,
// 파일의 실제 상태와 무관하다.
//
// 원칙: 이 파일의 모든 테스트는 저장 후 결과 파일을 **다시 열어(`PdfDocument.openFile`)**
// 1) 페이지 수 2) 페이지 동일성(마커 텍스트 대조) 3) 삭제 음성 단언(지운 마커가 어디에도
// 없음) 4) 회전값을 실제 문서에서 확인한다. 인플레이스 경로는 §9.1 버그로 비활성화되어
// 있으므로(`pdf_engine_isolate.dart`) 이 테스트들은 항상 `_runComposeNew` 경로를 검증한다 --
// 다만 그 경로 자체가 앞으로 다시 깨지더라도(회귀) 이 테스트가 반드시 잡아야 한다는 것이
// RO 원칙의 취지다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfrx;

/// 마커 문자열 생성기. `_END` 종결자를 붙여 "MARKER_1"이 "MARKER_10"의 부분 문자열로
/// 오탐되는 것을 막는다(숫자 인덱스가 두 자리 이상으로 커지는 케이스 3에서 실제로 발생했다).
String _m(int i, {String prefix = 'MARKER'}) => '${prefix}_${i}_END';

/// [count]페이지짜리 PDF를 만든다. 페이지 i(0-based)에는 [_m](i, prefix: prefix) 마커
/// 텍스트가 유일하게 박힌다. 저장 경로 테스트 전용 -- 프로덕션 코드가 아니므로
/// `package:pdf`를 직접 써도 된다.
Future<String> _buildMarkerPdf(Directory dir, String fileName, int count, {String prefix = 'MARKER'}) async {
  final doc = pw.Document();
  for (var i = 0; i < count; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text(_m(i, prefix: prefix)))));
  }
  final bytes = await doc.save();
  final path = '${dir.path}/$fileName';
  await File(path).writeAsBytes(bytes);
  return path;
}

/// 결과 파일을 다시 열어 RO 4항목을 전부 확인한다.
/// [expectedMarkers]는 결과 페이지 순서대로 기대하는 마커 문자열.
/// [expectedRotationDeg]는 같은 순서의 기대 회전(도, 생략 시 0).
/// [absentMarkers]는 결과 어디에도 있으면 안 되는 마커(삭제 음성 단언).
Future<void> _verifyRoundtrip(
  String outputPath, {
  required List<String> expectedMarkers,
  List<int>? expectedRotationDeg,
  List<String> absentMarkers = const [],
}) async {
  final doc = await pdfrx.PdfDocument.openFile(outputPath);
  try {
    // 1) 페이지 수
    expect(doc.pages.length, expectedMarkers.length, reason: 'RO-1 페이지 수 불일치');

    final allText = StringBuffer();
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final text = await page.loadText();
      final fullText = text?.fullText ?? '';
      allText.write(fullText);

      // 2) 페이지 동일성 -- 이 위치가 기대한 원본 페이지인가
      expect(fullText, contains(expectedMarkers[i]), reason: 'RO-2 위치 $i의 페이지 내용이 기대와 다르다');

      // 4) 회전값
      final expectedDeg = expectedRotationDeg != null ? expectedRotationDeg[i] : 0;
      expect(page.rotation.index * 90, expectedDeg, reason: 'RO-4 위치 $i의 회전값 불일치');
    }

    // 3) 삭제 음성 단언 -- 지운 마커가 결과 전체 어디에도 없어야 한다
    for (final absent in absentMarkers) {
      expect(allText.toString(), isNot(contains(absent)), reason: 'RO-3 삭제했어야 할 "$absent"가 결과에 남아 있다');
    }
  } finally {
    await doc.dispose();
  }
}

void main() {
  late Directory root;
  late PdfrxPdfEngine engine;
  var docCounter = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_roundtrip_');
    engine = PdfrxPdfEngine(appRoot: root.path);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 매 케이스마다 고유 docId로 스테이징 출력 경로를 만든다(§3.3/C4 화이트리스트 요건 충족).
  String newOutputPath() {
    docCounter++;
    final stagingDir = Directory('${root.path}/docs/case$docCounter.tmp');
    stagingDir.createSync(recursive: true);
    return '${stagingDir.path}/document.pdf';
  }

  // 게이트 통과 자체가 아니라 저장된 내용의 정확성이 목적이므로, 넉넉한 baseline으로
  // GuardPass를 보장한다(R1~R4 측정 코드와 동일한 관례).
  const generousGuard = GuardInput(op: SaveOp.deletePages, baselineBytes: 1 << 30);

  test('1. 중간 페이지 1장 삭제 -- 무음 삭제 실패를 잡는다', () async {
    final src = await _buildMarkerPdf(root, 'src1.pdf', 5);
    final outputPath = newOutputPath();

    final pages = [0, 1, 3, 4].map((i) => PdfPageRef(sourcePath: src, sourceIndex: i, rotation: 0)).toList();

    final result = await engine.save(
      pages: pages,
      outputPath: outputPath,
      quality: ImageQuality.standard,
      guardInput: generousGuard,
    );
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(outputPath, expectedMarkers: [_m(0), _m(1), _m(3), _m(4)], absentMarkers: [_m(2)]);
  });

  test('2. 순서 교체(0<->1) -- 무음 재배열 실패를 잡는다', () async {
    final src = await _buildMarkerPdf(root, 'src2.pdf', 3);
    final outputPath = newOutputPath();

    final pages = [1, 0, 2].map((i) => PdfPageRef(sourcePath: src, sourceIndex: i, rotation: 0)).toList();

    final result = await engine.save(
      pages: pages,
      outputPath: outputPath,
      quality: ImageQuality.standard,
      guardInput: generousGuard,
    );
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(outputPath, expectedMarkers: [_m(1), _m(0), _m(2)]);
  });

  test('3. 앞에서 연속되지 않은 중간 구간 발췌 -- §9.2 항등 인덱스 결함을 잡는다', () async {
    // 20페이지 중 10~14번(0-idx)만 뽑는다. 버그가 있었다면 "앞에서 5장만 남기고 자른다"가
    // 되어 결과는 0~4번 페이지가 나왔을 것이다 -- 요청한 10~14번이 아니라.
    final src = await _buildMarkerPdf(root, 'src3.pdf', 20);
    final outputPath = newOutputPath();

    final pages = [10, 11, 12, 13, 14].map((i) => PdfPageRef(sourcePath: src, sourceIndex: i, rotation: 0)).toList();

    final result = await engine.save(
      pages: pages,
      outputPath: outputPath,
      quality: ImageQuality.standard,
      guardInput: generousGuard,
    );
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(
      outputPath,
      expectedMarkers: [_m(10), _m(11), _m(12), _m(13), _m(14)],
      absentMarkers: [_m(0), _m(1), _m(5), _m(9), _m(15), _m(19)],
    );
  });

  test('4. 회전만 -- 회전 경로 회귀를 잡는다', () async {
    final src = await _buildMarkerPdf(root, 'src4.pdf', 3);
    final outputPath = newOutputPath();

    final pages = [
      PdfPageRef(sourcePath: src, sourceIndex: 0, rotation: 90),
      PdfPageRef(sourcePath: src, sourceIndex: 1, rotation: 0),
      PdfPageRef(sourcePath: src, sourceIndex: 2, rotation: 180),
    ];

    final result = await engine.save(
      pages: pages,
      outputPath: outputPath,
      quality: ImageQuality.standard,
      guardInput: generousGuard,
    );
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(
      outputPath,
      expectedMarkers: [_m(0), _m(1), _m(2)],
      expectedRotationDeg: [90, 0, 180],
    );
  });

  test('5. 비연속 발췌 + 회전 동시 -- "회전이 있으면 괜찮다"는 착각을 잡는다', () async {
    // §9.2: 회전이 섞여도 indices는 여전히 항등 리스트라 [0,3,6]을 요청해도 버그 코드는
    // 앞 3장(0,1,2)을 내놓았을 것이다. 회전만으로는 이 결함이 가려진다는 것이 핵심.
    final src = await _buildMarkerPdf(root, 'src5.pdf', 8);
    final outputPath = newOutputPath();

    final pages = [
      PdfPageRef(sourcePath: src, sourceIndex: 0, rotation: 90),
      PdfPageRef(sourcePath: src, sourceIndex: 3, rotation: 0),
      PdfPageRef(sourcePath: src, sourceIndex: 6, rotation: 270),
    ];

    final result = await engine.save(
      pages: pages,
      outputPath: outputPath,
      quality: ImageQuality.standard,
      guardInput: generousGuard,
    );
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(
      outputPath,
      expectedMarkers: [_m(0), _m(3), _m(6)],
      expectedRotationDeg: [90, 0, 270],
      absentMarkers: [_m(1), _m(2), _m(4), _m(5), _m(7)],
    );
  });

  test('6. merge(원본 N개) -- compose 경로 회귀를 잡는다', () async {
    final srcA = await _buildMarkerPdf(root, 'srcA.pdf', 2, prefix: 'A');
    final srcB = await _buildMarkerPdf(root, 'srcB.pdf', 3, prefix: 'B');
    final outputPath = newOutputPath();

    final pages = [
      PdfPageRef(sourcePath: srcA, sourceIndex: 0, rotation: 0),
      PdfPageRef(sourcePath: srcA, sourceIndex: 1, rotation: 0),
      PdfPageRef(sourcePath: srcB, sourceIndex: 0, rotation: 0),
      PdfPageRef(sourcePath: srcB, sourceIndex: 1, rotation: 0),
      PdfPageRef(sourcePath: srcB, sourceIndex: 2, rotation: 0),
    ];

    final result = await engine.save(
      pages: pages,
      outputPath: outputPath,
      quality: ImageQuality.standard,
      guardInput: const GuardInput(op: SaveOp.merge, baselineBytes: 1 << 30),
    );
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(
      outputPath,
      expectedMarkers: [_m(0, prefix: 'A'), _m(1, prefix: 'A'), _m(0, prefix: 'B'), _m(1, prefix: 'B'), _m(2, prefix: 'B')],
    );
  });
}
