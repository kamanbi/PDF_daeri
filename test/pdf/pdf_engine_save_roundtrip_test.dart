// RO(Reopen-Or-It-Didn't-Happen) 회귀 테스트 -- 설계 §4.5, `9x_architect_verdict.md` §9.5,
// `_workspace/15_architect_qpdf_migration.md` §7.4(엔진 교체 후 재적용 · 범위 확대).
//
// M-Q3/M-Q4: `PdfrxPdfEngine` -> `QpdfPdfEngine` 교체에 맞춰 6종 매트릭스를 전부 qpdf 엔진 대상으로
// 재실행한다. "엔진만 바뀌었으니 통과할 것"이라는 추정은 금지다(§7.4) -- 이 파일은 그 추정을
// 검증 없이 받아들이지 않는다. 신규 케이스 7(혼합 compose)을 추가한다.
//
// **재오픈 검증기는 `pdfrx`를 쓴다**(§7.4). qpdf가 쓴 결과를 qpdf로 다시 읽으면 자기 정합성만
// 확인된다 -- 쓴 라이브러리와 다른 라이브러리로 읽는 것이 RO 원칙의 취지에 부합한다. 재오픈은
// 메인 isolate에서 수행한다(§8.4 불변식과 충돌 없음, pdfrx는 이 테스트 파일에서만 쓰인다).
//
// qpdf FFI 잡 실행은 Windows `test/native/qpdf30.dll`이 있어야 돈다(호스트 검증 경로,
// `18_pdf-core_qpdf_bindings.md` §5). DLL/픽스처가 없으면 이 파일의 모든 테스트를 건너뛴다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => '${Directory.current.path}/$_dllRelPath';
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();

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

/// 단색에 가까운 테스트 JPEG(텍스트 없음 -- 이미지 페이지는 추출 텍스트가 없어야 한다는 것이
/// 케이스 7 검증의 핵심 신호다).
List<int> _solidJpeg(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return img.encodeJpg(image, quality: 85);
}

/// 결과 파일을 다시 열어 RO 4항목을 전부 확인한다(전부 텍스트 페이지인 케이스 1~6 전용).
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
    expect(doc.pages.length, expectedMarkers.length, reason: 'RO-1 페이지 수 불일치');

    final allText = StringBuffer();
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final text = await page.loadText();
      final fullText = text?.fullText ?? '';
      allText.write(fullText);

      expect(fullText, contains(expectedMarkers[i]), reason: 'RO-2 위치 $i의 페이지 내용이 기대와 다르다');

      final expectedDeg = expectedRotationDeg != null ? expectedRotationDeg[i] : 0;
      expect(page.rotation.index * 90, expectedDeg, reason: 'RO-4 위치 $i의 회전값 불일치');
    }

    for (final absent in absentMarkers) {
      expect(allText.toString(), isNot(contains(absent)), reason: 'RO-3 삭제했어야 할 "$absent"가 결과에 남아 있다');
    }
  } finally {
    await doc.dispose();
  }
}

void main() {
  late Directory root;
  late QpdfPdfEngine engine;
  var docCounter = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_roundtrip_');
    engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _canRunFfi ? _dllPath : null);
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
  }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

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
  }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

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
  }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

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

    await _verifyRoundtrip(outputPath, expectedMarkers: [_m(0), _m(1), _m(2)], expectedRotationDeg: [90, 0, 180]);
  }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

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
  }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

  test('6. merge(원본 N개) -- compose 경로 회귀를 잡는다', () async {
    final srcA = await _buildMarkerPdf(root, 'srcA.pdf', 2, prefix: 'A');
    final srcB = await _buildMarkerPdf(root, 'srcB.pdf', 3, prefix: 'B');
    final outputPath = newOutputPath();

    final result = await engine.merge(sourcePdfPaths: [srcA, srcB], outputPath: outputPath);
    expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

    await _verifyRoundtrip(
      outputPath,
      expectedMarkers: [_m(0, prefix: 'A'), _m(1, prefix: 'A'), _m(0, prefix: 'B'), _m(1, prefix: 'B'), _m(2, prefix: 'B')],
    );
  }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

  test(
    '7. ImagePageRef + PdfPageRef 혼합 compose -- §7.4 신규 케이스. 순서가 어긋나도 페이지 수는 맞는 결함 유형을 정면으로 겨냥한다',
    () async {
      // 세그먼트: [이미지1장] [텍스트2장(연속, 같은 소스)] [이미지1장] [텍스트1장]
      // buildComposeJob의 "연속 동일 소스 묶기" 로직과, 이미지<->텍스트 소스 전환이 둘 다 걸리는
      // 구성이다. 이미지 페이지는 회전(90/0)도 섞어 rotate 스펙이 출력 위치 기준으로 정확히
      // 걸리는지까지 함께 검증한다.
      final srcText = await _buildMarkerPdf(root, 'srcText.pdf', 3, prefix: 'T');
      final outputPath = newOutputPath();
      final imagesDir = Directory('${File(outputPath).parent.path}/sources/pages')..createSync(recursive: true);
      final img0Path = '${imagesDir.path}/000.jpg';
      final img1Path = '${imagesDir.path}/001.jpg';
      await File(img0Path).writeAsBytes(_solidJpeg(64, 96, 200, 40, 40)); // 붉은 계열
      await File(img1Path).writeAsBytes(_solidJpeg(64, 96, 40, 40, 200)); // 푸른 계열

      final pages = [
        ImagePageRef(imagePath: img0Path, rotation: 90),
        PdfPageRef(sourcePath: srcText, sourceIndex: 0, rotation: 0),
        PdfPageRef(sourcePath: srcText, sourceIndex: 1, rotation: 180),
        ImagePageRef(imagePath: img1Path, rotation: 0),
        PdfPageRef(sourcePath: srcText, sourceIndex: 2, rotation: 0),
      ];

      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: generousGuard,
      );
      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
      expect((result as PdfOk<SaveOutcome>).value.pageCount, 5);

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        // RO-1: 페이지 수.
        expect(doc.pages.length, 5, reason: 'RO-1 페이지 수 불일치');

        final expectedRotation = [90, 0, 180, 0, 0];
        final expectedMarker = [null, _m(0, prefix: 'T'), _m(1, prefix: 'T'), null, _m(2, prefix: 'T')];

        final allText = StringBuffer();
        for (var i = 0; i < doc.pages.length; i++) {
          final page = doc.pages[i];
          final text = await page.loadText();
          final fullText = text?.fullText ?? '';
          allText.write(fullText);

          // RO-4: 회전값(이미지 페이지 포함, 출력 위치 기준으로 정확히 걸렸는지).
          expect(page.rotation.index * 90, expectedRotation[i], reason: 'RO-4 위치 $i의 회전값 불일치');

          final marker = expectedMarker[i];
          if (marker != null) {
            // RO-2: 텍스트 페이지 위치의 내용 동일성.
            expect(fullText, contains(marker), reason: 'RO-2 위치 $i의 페이지 내용이 기대와 다르다(텍스트 소스가 뒤섞였을 수 있다)');
          } else {
            // 이미지 페이지 위치에는 추출 가능한 텍스트가 없어야 한다 -- 있다면 텍스트 소스가
            // 이 위치로 잘못 인터리브됐다는 뜻이다(개수는 맞고 내용은 틀린 결함 유형).
            expect(
              fullText.trim(),
              isEmpty,
              reason: 'RO-2 위치 $i는 이미지 페이지여야 하는데 텍스트가 검출됨: "$fullText"',
            );
          }
        }

        // RO-3: 삭제 음성 단언 -- 이 케이스는 삭제가 없으므로 각 텍스트 마커가 정확히 1번씩만 나온다.
        for (final marker in [_m(0, prefix: 'T'), _m(1, prefix: 'T'), _m(2, prefix: 'T')]) {
          final occurrences = marker.allMatches(allText.toString()).length;
          expect(occurrences, 1, reason: 'RO-3 "$marker"가 정확히 1번 나와야 하는데 $occurrences번 나옴(중복/누락)');
        }
      } finally {
        await doc.dispose();
      }
    },
    skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false,
  );
}
