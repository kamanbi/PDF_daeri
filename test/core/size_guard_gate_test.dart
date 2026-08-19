// SizeGuard 실게이트 검증 -- 설계 §4(`36_architect_week3_design.md`)의 매트릭스를 구현한다.
//
// `test/pdf/pdf_engine_save_roundtrip_test.dart`는 `generousGuard`로 게이트를 의도적으로
// 무력화한 채 **저장 정확성**만 본다. 이 파일이 정반대다: 실제 `QpdfPdfEngine` 저장 결과
// 바이트로 게이트가 **실제로 걸리는지**(Pass/Blocked 둘 다)를 검증한다. 게이트 검증은
// 이 파일 하나가 한다 -- roundtrip 테스트를 게이트 증거로 읽지 않는다.
//
// 픽스처: `test/pdf/raw_pdf_fixture.dart`는 qpdf 구조 검사 전용(적격 판정 규칙만 보고
// 스트림을 열지 않는 가짜 이미지 바이트) 픽스처라 이 파일의 목적(실제 저장 파이프라인을
// 끝까지 태워 진짜 바이트 결과를 얻는 것)에 맞지 않는다 -- `ImagePageRef` 경로는 실제
// 디코드 가능한 JPEG을 요구한다(§2.4/§2.5). 대신 `pdf_engine_save_roundtrip_test.dart`가
// 이미 쓰는 방식(`package:pdf`로 마커 텍스트/실제 JPEG을 담은 진짜 PDF를 만드는 방식)을
// 그대로 따른다. baseline 문서 자체는 프로덕션 파이프라인을 거치지 않고 직접 조립한다
// (외부에서 이미 존재하는 문서를 편집 대상으로 여는 것과 동일한 상황을 흉내낸다) --
// 각 SaveOp 테스트가 그 baseline을 입력으로 실제 `QpdfPdfEngine`을 태운다.
//
// qpdf FFI 잡 실행은 Windows `test/native/qpdf30.dll`이 있어야 돈다. DLL/픽스처가 없으면
// 이 파일의 FFI 의존 테스트를 건너뛴다(`SizeGuard.classify` 단위 테스트는 순수 함수라
// 건너뛰지 않는다).
import 'dart:io';
import 'dart:typed_data';

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
final _ffiSkip = !_canRunFfi ? 'Windows qpdf30.dll 필요' : false;

/// 마커 문자열 생성기(`pdf_engine_save_roundtrip_test.dart`와 동일 관례) -- `_END` 종결자로
/// "MARKER_1"이 "MARKER_10"의 부분 문자열로 오탐되는 것을 막는다.
String _m(int i, {String prefix = 'MARKER'}) => '${prefix}_${i}_END';

/// 단색 테스트 JPEG. 정사각형으로 만들어 회전이 섞여도 픽셀 색 검증에 기하 보정이 필요 없다.
List<int> _solidJpeg(int size, int r, int g, int b) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return img.encodeJpg(image, quality: 85);
}

/// 서로 뚜렷이 구분되는 팔레트(RO 검증에서 재인코딩 손실에도 채널 오차를 넉넉히 흡수한다).
const _palette = <(int, int, int)>[
  (230, 25, 75),
  (60, 180, 75),
  (0, 130, 200),
  (245, 130, 48),
  (145, 30, 180),
  (70, 240, 240),
  (240, 50, 230),
  (210, 245, 60),
  (0, 128, 128),
  (170, 110, 40),
];

/// 결과 문서 한 페이지의 기대 정체성. `marker`(텍스트 페이지) `xor` `color`(이미지 페이지).
class _PageIdentity {
  const _PageIdentity.text(this.marker) : color = null;
  const _PageIdentity.image(this.color) : marker = null;
  final String? marker;
  final (int, int, int)? color;
}

class _Baseline {
  const _Baseline({required this.path, required this.bytes, required this.pageCount, required this.identities});
  final String path;
  final int bytes;
  final int pageCount;
  final List<_PageIdentity> identities;
}

enum _FixtureKind {
  text('F-T 텍스트'),
  scan('F-S 스캔'),
  mixed('F-M 혼합');

  const _FixtureKind(this.label);
  final String label;
}

/// [dir]에 baseline 문서를 직접 조립한다(프로덕션 파이프라인을 거치지 않는다 -- "이미
/// 존재하는 원본 문서"를 흉내낸다). 각 SaveOp 테스트가 이 문서를 `PdfPageRef` 소스로 삼아
/// 실제 `QpdfPdfEngine`을 태운다.
Future<_Baseline> _buildBaseline(_FixtureKind kind, Directory dir, String tag) async {
  switch (kind) {
    case _FixtureKind.text:
      return _buildTextBaseline(dir, tag);
    case _FixtureKind.scan:
      return _buildScanBaseline(dir, tag);
    case _FixtureKind.mixed:
      return _buildMixedBaseline(dir, tag);
  }
}

const _textPageCount = 10;
const _scanPageCount = 10;

Future<_Baseline> _buildTextBaseline(Directory dir, String tag) async {
  final doc = pw.Document();
  for (var i = 0; i < _textPageCount; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text(_m(i, prefix: tag)))));
  }
  final bytes = await doc.save();
  final path = '${dir.path}/$tag.pdf';
  await File(path).writeAsBytes(bytes);
  return _Baseline(
    path: path,
    bytes: bytes.length,
    pageCount: _textPageCount,
    identities: [for (var i = 0; i < _textPageCount; i++) _PageIdentity.text(_m(i, prefix: tag))],
  );
}

Future<_Baseline> _buildScanBaseline(Directory dir, String tag) async {
  final doc = pw.Document();
  final colors = [for (var i = 0; i < _scanPageCount; i++) _palette[i % _palette.length]];
  for (final c in colors) {
    final jpeg = _solidJpeg(64, c.$1, c.$2, c.$3);
    doc.addPage(pw.Page(build: (context) => pw.Image(pw.MemoryImage(Uint8List.fromList(jpeg)))));
  }
  final bytes = await doc.save();
  final path = '${dir.path}/$tag.pdf';
  await File(path).writeAsBytes(bytes);
  return _Baseline(
    path: path,
    bytes: bytes.length,
    pageCount: _scanPageCount,
    identities: [for (final c in colors) _PageIdentity.image(c)],
  );
}

Future<_Baseline> _buildMixedBaseline(Directory dir, String tag) async {
  final doc = pw.Document();
  for (var i = 0; i < 3; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text(_m(i, prefix: '${tag}_T')))));
  }
  final imageColors = [_palette[0], _palette[1]];
  for (final c in imageColors) {
    final jpeg = _solidJpeg(64, c.$1, c.$2, c.$3);
    doc.addPage(pw.Page(build: (context) => pw.Image(pw.MemoryImage(Uint8List.fromList(jpeg)))));
  }
  final bytes = await doc.save();
  final path = '${dir.path}/$tag.pdf';
  await File(path).writeAsBytes(bytes);
  return _Baseline(
    path: path,
    bytes: bytes.length,
    pageCount: 5,
    identities: [
      for (var i = 0; i < 3; i++) _PageIdentity.text(_m(i, prefix: '${tag}_T')),
      for (final c in imageColors) _PageIdentity.image(c),
    ],
  );
}

/// RO 검증: 결과 파일을 재오픈해 페이지 수·마커(또는 이미지 색)·회전값을 확인한다(설계 §4.5).
Future<void> _verifyIdentities(
  String outputPath, {
  required List<_PageIdentity> expected,
  required List<int> expectedRotationDeg,
}) async {
  final doc = await pdfrx.PdfDocument.openFile(outputPath);
  try {
    expect(doc.pages.length, expected.length, reason: 'RO-1 페이지 수 불일치');
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      expect(page.rotation.index * 90, expectedRotationDeg[i], reason: 'RO-4 위치 $i의 회전값 불일치');

      final id = expected[i];
      if (id.marker != null) {
        final text = await page.loadText();
        expect(text?.fullText ?? '', contains(id.marker!), reason: 'RO-2 위치 $i의 텍스트 마커 불일치');
      } else if (id.color != null) {
        await _expectDominantColor(page, id.color!, position: i);
      }
    }
  } finally {
    await doc.dispose();
  }
}

Future<void> _expectDominantColor(pdfrx.PdfPage page, (int, int, int) expected, {required int position}) async {
  final rendered = await page.render(fullWidth: 32, fullHeight: 32);
  expect(rendered, isNotNull, reason: 'RO-2 위치 $position 렌더 실패');
  final image = rendered!;
  try {
    final pixels = image.pixels; // bgra8888(§ pdf_renderer.dart와 동일 포맷)
    final cx = image.width ~/ 2;
    final cy = image.height ~/ 2;
    final idx = (cy * image.width + cx) * 4;
    final b = pixels[idx];
    final g = pixels[idx + 1];
    final r = pixels[idx + 2];
    const tolerance = 40;
    expect(r, closeTo(expected.$1, tolerance), reason: 'RO-2 위치 $position R채널 불일치');
    expect(g, closeTo(expected.$2, tolerance), reason: 'RO-2 위치 $position G채널 불일치');
    expect(b, closeTo(expected.$3, tolerance), reason: 'RO-2 위치 $position B채널 불일치');
  } finally {
    image.dispose();
  }
}

void main() {
  late Directory root;
  late QpdfPdfEngine engine;
  var docCounter = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_gate_');
    engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _canRunFfi ? _dllPath : null);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 매 테스트마다 고유 docId로 스테이징 출력 경로를 만든다(§3.3/C4 화이트리스트 요건).
  String newOutputPath(String label) {
    docCounter++;
    final stagingDir = Directory('${root.path}/docs/$label$docCounter.tmp');
    stagingDir.createSync(recursive: true);
    return '${stagingDir.path}/document.pdf';
  }

  group('SizeGuard.classify — 단위 테스트(5개 분기 + 2개 경계, 설계 §1.6)', () {
    const pdfA = PdfPageRef(sourcePath: '/src.pdf', sourceIndex: 0, rotation: 0);
    const pdfB = PdfPageRef(sourcePath: '/src.pdf', sourceIndex: 1, rotation: 0);
    const pdfC = PdfPageRef(sourcePath: '/src.pdf', sourceIndex: 2, rotation: 0);
    const img0 = ImagePageRef(imagePath: '/img0.jpg', rotation: 0);
    const img1 = ImagePageRef(imagePath: '/img1.jpg', rotation: 0);

    test('1. before가 비었으면 신규 생성 — freshDocument 미도입(Q-W6) 임시 규약대로 merge를 반환', () {
      // 설계 §3.4: "freshDocument (§7 Q-W6까지 merge 임시 유지)". SaveOp.freshDocument는
      // Q-W6(R·K 상수) 승인 전까지 도입하지 않는다 -- 도입하면 lib/features/common/failure_ui.dart의
      // 기존 op별 switch(비-default, U 소유 · T1 범위 밖)가 컴파일 에러가 난다.
      final result = SizeGuard.classify(before: const [], after: const [img0], intent: EditIntent.edit);
      expect(result, SaveOp.merge);
    });

    test('2. intent == split이면 무조건 split', () {
      final result = SizeGuard.classify(before: [pdfA, pdfB, pdfC], after: [pdfA, pdfC], intent: EditIntent.split);
      expect(result, SaveOp.split);
    });

    test('3. before에 없던 ImagePageRef가 after에 있으면 compose', () {
      final result = SizeGuard.classify(before: [pdfA, pdfB], after: [pdfA, pdfB, img0], intent: EditIntent.edit);
      expect(result, SaveOp.compose);
    });

    test('4. after가 before의 진부분집합이면 deletePages', () {
      final result = SizeGuard.classify(before: [pdfA, pdfB, pdfC], after: [pdfA, pdfC], intent: EditIntent.edit);
      expect(result, SaveOp.deletePages);
    });

    test('5. 삭제·추가 없이 순서/회전만 바뀌면 reorderOrRotate', () {
      final reordered = PdfPageRef(sourcePath: pdfB.sourcePath, sourceIndex: pdfB.sourceIndex, rotation: 90);
      final result = SizeGuard.classify(
        before: [pdfA, pdfB, pdfC],
        after: [reordered, pdfA, pdfC],
        intent: EditIntent.edit,
      );
      expect(result, SaveOp.reorderOrRotate);
    });

    test('경계 1. 삭제 + 순서변경 동시 → deletePages(삭제가 하나라도 있으면 우선)', () {
      // before: [A,B,C] -> after: [C,A] (B 삭제 + 순서도 바뀜)
      final result = SizeGuard.classify(before: [pdfA, pdfB, pdfC], after: [pdfC, pdfA], intent: EditIntent.edit);
      expect(result, SaveOp.deletePages);
    });

    test('경계 2. rotation은 동일성 판정에서 제외 — 회전만 바뀐 것은 삭제로 오판하지 않는다', () {
      final rotatedOnly = ImagePageRef(imagePath: img0.imagePath, rotation: 180);
      final result = SizeGuard.classify(
        before: [pdfA, img0, img1],
        after: [pdfA, rotatedOnly, img1],
        intent: EditIntent.edit,
      );
      // rotation 차이만으로는 img0 정체성이 바뀌지 않으므로 "새 이미지 추가"(compose)로도,
      // "삭제"로도 분류되지 않는다 -- reorderOrRotate여야 한다.
      expect(result, SaveOp.reorderOrRotate);
    });
  });

  group('차단 케이스(음성 단언) — baselineBytes를 실제보다 작게 주면 저장이 중단되고 출력이 삭제된다', () {
    test('deletePages: 허위로 작은 baselineBytes → SizeGuardViolation + 출력 파일 없음', () async {
      final baseline = await _buildTextBaseline(root, 'blocked_src');
      final outputPath = newOutputPath('blocked');
      final pages = [for (var i = 1; i < baseline.pageCount; i++) PdfPageRef(sourcePath: baseline.path, sourceIndex: i, rotation: 0)];

      // 실제 결과보다 훨씬 작은 baseline을 준다 -- deleteRatio=1.00이므로 이 값으로는 절대 통과할 수 없다.
      final guardInput = GuardInput(op: SaveOp.deletePages, baselineBytes: 1);
      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: guardInput,
      );

      expect(result, isA<PdfErr<SaveOutcome>>(), reason: '작은 baseline인데 저장이 통과함 -- 게이트가 걸리지 않는 결함');
      final failure = (result as PdfErr<SaveOutcome>).failure;
      expect(failure, isA<SizeGuardViolation>());
      expect(File(outputPath).existsSync(), isFalse, reason: '게이트 차단 후에도 출력 파일이 남아 있다');
    }, skip: _ffiSkip);
  });

  for (final kind in _FixtureKind.values) {
    group('${kind.label} 픽스처 × 5 SaveOp', () {
      test('deletePages — 1장 삭제 → Pass, 결과 < 원본', () async {
        final baseline = await _buildBaseline(kind, root, '${kind.name}_del_src');
        final outputPath = newOutputPath('${kind.name}_del');
        final deleteAt = baseline.pageCount ~/ 2; // 중간 페이지 삭제
        final keepIndices = [for (var i = 0; i < baseline.pageCount; i++) if (i != deleteAt) i];
        final pages = keepIndices.map((i) => PdfPageRef(sourcePath: baseline.path, sourceIndex: i, rotation: 0)).toList();

        final guardInput = GuardInput(op: SaveOp.deletePages, baselineBytes: baseline.bytes);
        final result = await engine.save(
          pages: pages,
          outputPath: outputPath,
          quality: ImageQuality.standard,
          guardInput: guardInput,
        );

        expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
        final outcome = (result as PdfOk<SaveOutcome>).value;
        expect(outcome.bytes, lessThan(baseline.bytes), reason: '삭제 후 결과가 원본보다 작아야 한다');

        await _verifyIdentities(
          outputPath,
          expected: [for (final i in keepIndices) baseline.identities[i]],
          expectedRotationDeg: List.filled(keepIndices.length, 0),
        );
      }, skip: _ffiSkip);

      test('reorderOrRotate — 0↔1 교체 + 90° → Pass', () async {
        final baseline = await _buildBaseline(kind, root, '${kind.name}_reorder_src');
        final outputPath = newOutputPath('${kind.name}_reorder');
        final order = [1, 0, for (var i = 2; i < baseline.pageCount; i++) i];
        final pages = [
          for (var pos = 0; pos < order.length; pos++)
            PdfPageRef(sourcePath: baseline.path, sourceIndex: order[pos], rotation: pos == 0 ? 90 : 0),
        ];

        final guardInput = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseline.bytes);
        final result = await engine.save(
          pages: pages,
          outputPath: outputPath,
          quality: ImageQuality.standard,
          guardInput: guardInput,
        );

        expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

        await _verifyIdentities(
          outputPath,
          expected: [for (final i in order) baseline.identities[i]],
          expectedRotationDeg: [90, for (var i = 1; i < order.length; i++) 0],
        );
      }, skip: _ffiSkip);

      test('split — 비연속 3페이지 발췌 → Pass', () async {
        final baseline = await _buildBaseline(kind, root, '${kind.name}_split_src');
        final outputPath = newOutputPath('${kind.name}_split');
        final indices = baseline.pageCount == 5 ? const [0, 2, 4] : [0, baseline.pageCount ~/ 2, baseline.pageCount - 1];

        final result = await engine.split(sourcePdfPath: baseline.path, pageIndices: indices, outputPath: outputPath);

        expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

        await _verifyIdentities(
          outputPath,
          expected: [for (final i in indices) baseline.identities[i]],
          expectedRotationDeg: List.filled(indices.length, 0),
        );
      }, skip: _ffiSkip);

      test('merge — 원본 3개 → Pass, 결과 ≤ 합계×1.05', () async {
        final b1 = await _buildBaseline(kind, root, '${kind.name}_merge_a');
        final b2 = await _buildBaseline(kind, root, '${kind.name}_merge_b');
        final b3 = await _buildBaseline(kind, root, '${kind.name}_merge_c');
        final outputPath = newOutputPath('${kind.name}_merge');

        final result = await engine.merge(sourcePdfPaths: [b1.path, b2.path, b3.path], outputPath: outputPath);

        expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
        final outcome = (result as PdfOk<SaveOutcome>).value;
        final sumBaseline = b1.bytes + b2.bytes + b3.bytes;
        expect(outcome.bytes, lessThanOrEqualTo((sumBaseline * SizeGuard.mergeRatio).floor()));

        final expectedIdentities = [...b1.identities, ...b2.identities, ...b3.identities];
        await _verifyIdentities(
          outputPath,
          expected: expectedIdentities,
          expectedRotationDeg: List.filled(expectedIdentities.length, 0),
        );
      }, skip: _ffiSkip);

      test('compose — 원본 + 이미지 2장 추가 → Pass', () async {
        final baseline = await _buildBaseline(kind, root, '${kind.name}_compose_src');
        final outputPath = newOutputPath('${kind.name}_compose');

        final imagesDir = Directory('${File(outputPath).parent.path}/sources/pages')..createSync(recursive: true);
        final addedColors = [_palette[8], _palette[9]];
        final addedImagePaths = <String>[];
        for (var i = 0; i < addedColors.length; i++) {
          final c = addedColors[i];
          final path = '${imagesDir.path}/${i.toString().padLeft(3, '0')}.jpg';
          await File(path).writeAsBytes(_solidJpeg(64, c.$1, c.$2, c.$3));
          addedImagePaths.add(path);
        }
        final addedImageBytes = addedImagePaths.fold<int>(0, (sum, p) => sum + File(p).lengthSync());

        final pages = [
          for (var i = 0; i < baseline.pageCount; i++) PdfPageRef(sourcePath: baseline.path, sourceIndex: i, rotation: 0),
          for (final p in addedImagePaths) ImagePageRef(imagePath: p, rotation: 0),
        ];

        final guardInput = GuardInput(op: SaveOp.compose, baselineBytes: baseline.bytes, addedImageBytes: addedImageBytes);
        final result = await engine.save(
          pages: pages,
          outputPath: outputPath,
          quality: ImageQuality.standard,
          guardInput: guardInput,
        );

        expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
        final outcome = (result as PdfOk<SaveOutcome>).value;
        expect(
          outcome.bytes,
          lessThanOrEqualTo(((baseline.bytes + addedImageBytes) * SizeGuard.composeOverheadRatio).floor()),
        );

        final expectedIdentities = [...baseline.identities, for (final c in addedColors) _PageIdentity.image(c)];
        await _verifyIdentities(
          outputPath,
          expected: expectedIdentities,
          expectedRotationDeg: List.filled(expectedIdentities.length, 0),
        );
      }, skip: _ffiSkip);
    });
  }
}
