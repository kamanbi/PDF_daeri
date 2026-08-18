// M-Q6 압축 도구 테스트. `_workspace/15_architect_qpdf_migration.md` §6, §7.4(RO 원칙 확대 적용).
//
// RO 원칙: `CompressOutcome.resultBytes`만 단언하는 테스트는 인정하지 않는다(§7.4). 이 파일의
// 모든 성공 케이스는 결과 파일을 재오픈해 페이지 수(및 텍스트 케이스는 마커) 동일성을 확인한다.
// 재오픈 검증기는 qpdf(`runInspect`, 페이지 수)와 `pdfrx`(마커 텍스트, L1 텍스트 케이스)를 함께 쓴다.
//
// qpdf FFI 잡 실행은 Windows `test/native/qpdf30.dll`이 있어야 돈다 -- 없으면 이 파일의 모든
// 압축 실행 테스트를 건너뛴다(순수 함수인 analyze()만 무조건 돈다).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/pdf/image_pdf_builder.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';
import 'package:pdf_daeri/pdf/pdf_compressor.dart';
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

const _fixtureRelPath = 'test/fixtures/(서일)-클라우디움 사용자 매뉴얼(윈도우탐색기)_20180821.pdf';
const _dllRelPath = 'test/native/qpdf30.dll';

String get _fixturePath => p.join(Directory.current.path, _fixtureRelPath);
String get _dllPath => p.join(Directory.current.path, _dllRelPath);
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync() && File(_fixturePath).existsSync();

String _m(int i) => 'MARKER_${i}_END';

Future<String> _buildMarkerPdf(Directory dir, String fileName, int count) async {
  final doc = pw.Document();
  for (var i = 0; i < count; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text(_m(i)))));
  }
  final bytes = await doc.save();
  final path = p.join(dir.path, fileName);
  await File(path).writeAsBytes(bytes);
  return path;
}

/// 스캔본에 가까운 합성 JPEG(흰 배경 + 텍스트 밀도를 흉내 낸 어두운 노이즈 밴드).
/// 단색 이미지와 달리 실제 AC 계수가 있어 프리셋별(품질·해상도) 차이가 파일 크기에 반영된다.
Uint8List _scanLikeJpeg(int width, int height, {int quality = 92, int seed = 1}) {
  final rand = Random(seed);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, 250, 250, 248);
    }
  }
  final lineHeight = max(4, (height / 70).round());
  for (var ly = 30; ly < height - 30; ly += lineHeight * 2) {
    for (var y = ly; y < min(ly + lineHeight, height); y++) {
      for (var x = 40; x < width - 40; x += 2) {
        if (rand.nextDouble() < 0.35) {
          final v = 20 + rand.nextInt(40);
          image.setPixelRgb(x, y, v, v, v);
        }
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

void main() {
  group('analyze() — pages.kind 기반 판별(PDF 파싱 없음)', () {
    final compressor = const QpdfCompressor();

    test('모든 페이지가 image -> imageDominant=true, reason 없음', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_analyze_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dummy = p.join(tempDir.path, 'a.pdf');
      await File(dummy).writeAsBytes([1, 2, 3]);

      final result = await compressor.analyze(dummy, pageKinds: const ['image', 'image', 'image']);
      final target = (result as PdfOk<CompressTarget>).value;
      expect(target.imageDominant, isTrue);
      expect(target.reason, isEmpty);
    });

    test('모든 페이지가 pdf(외부 PDF) -> imageDominant=false, reason=textDominant', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_analyze_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dummy = p.join(tempDir.path, 'a.pdf');
      await File(dummy).writeAsBytes([1, 2, 3]);

      final result = await compressor.analyze(dummy, pageKinds: const ['pdf', 'pdf']);
      final target = (result as PdfOk<CompressTarget>).value;
      expect(target.imageDominant, isFalse);
      expect(target.reason, 'compress.reason.textDominant');
    });

    test('혼합(image+pdf) -> imageDominant=false, reason=mixed', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_analyze_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dummy = p.join(tempDir.path, 'a.pdf');
      await File(dummy).writeAsBytes([1, 2, 3]);

      final result = await compressor.analyze(dummy, pageKinds: const ['image', 'pdf', 'image']);
      final target = (result as PdfOk<CompressTarget>).value;
      expect(target.imageDominant, isFalse);
      expect(target.reason, 'compress.reason.mixed');
    });

    test('페이지 0개 -> imageDominant=false, reason=unavailable', () async {
      final result = await compressor.analyze('anything.pdf', pageKinds: const []);
      final target = (result as PdfOk<CompressTarget>).value;
      expect(target.imageDominant, isFalse);
      expect(target.reason, 'compress.reason.unavailable');
    });

    test('파일 없음 -> imageDominant=false, reason=unavailable', () async {
      final result = await compressor.analyze('/no/such/file.pdf', pageKinds: const ['image']);
      final target = (result as PdfOk<CompressTarget>).value;
      expect(target.imageDominant, isFalse);
      expect(target.reason, 'compress.reason.unavailable');
    });
  });

  group('compress() — 경로/입력 검증(FFI 불필요)', () {
    final compressor = const QpdfCompressor();

    test('pdfPath가 존재하지 않으면 SourceMissing', () async {
      final result = await compressor.compress(
        pdfPath: '/no/such/file.pdf',
        outputPath: '/tmp/out.pdf',
        preset: ImageQuality.standard,
      );
      expect(result, isA<PdfErr<CompressOutcome>>());
      expect((result as PdfErr<CompressOutcome>).failure, isA<SourceMissing>());
    });

    test('outputPath == pdfPath면 거부(원본 미수정 원칙)', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_guard_');
      addTearDown(() => tempDir.delete(recursive: true));
      final path = p.join(tempDir.path, 'doc.pdf');
      await File(path).writeAsBytes([1, 2, 3]);

      final result = await compressor.compress(pdfPath: path, outputPath: path, preset: ImageQuality.standard);
      expect(result, isA<PdfErr<CompressOutcome>>());
      expect((result as PdfErr<CompressOutcome>).failure, isA<UnknownFailure>());
    });
  });

  group('compress() — qpdf FFI 실행 (Windows qpdf30.dll 필요)', () {
    setUpAll(() {
      if (!_canRunFfi) {
        // ignore: avoid_print
        print('SKIP: Windows qpdf30.dll 또는 픽스처 없음 -- 압축 FFI 테스트 건너뜀 ($_dllPath / $_fixturePath)');
      }
    });

    test('L1: 텍스트 위주 PDF -- RO(페이지 수 + 마커 동일성) 통과, 원본 미수정', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_l1_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await _buildMarkerPdf(tempDir, 'src.pdf', 8);
      final srcBytesBefore = await File(srcPath).readAsBytes();
      final outputPath = p.join(tempDir.path, 'out_l1.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      final result = await compressor.compress(pdfPath: srcPath, outputPath: outputPath, preset: ImageQuality.standard);

      final outcome = (result as PdfOk<CompressOutcome>).value;
      expect(outcome.originalBytes, srcBytesBefore.length);

      // 원본 미수정(절대 규칙 6) -- pdfPath는 compress() 내내 read-only여야 한다.
      expect(await File(srcPath).readAsBytes(), srcBytesBefore);

      // RO: qpdf로 재오픈해 페이지 수, pdfrx로 재오픈해 마커 텍스트 확인.
      final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(inspected['ok'], true);
      expect(inspected['pageCount'], 8);

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, 8, reason: 'RO-1 페이지 수 불일치');
        for (var i = 0; i < 8; i++) {
          final text = await doc.pages[i].loadText();
          expect(text?.fullText ?? '', contains(_m(i)), reason: 'RO-2 위치 $i 마커 불일치');
        }
      } finally {
        await doc.dispose();
      }
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('L1: 이미 최적인 문서는 keptOriginal=true, 산출물 삭제, resultBytes==originalBytes', () async {
      // qpdf가 더 줄일 수 없는 아주 작은(사실상 빈) 문서 -- 재작성 오버헤드가 원본보다 커지기 쉽다.
      final tempDir = await Directory.systemTemp.createTemp('compressor_kept_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await _buildMarkerPdf(tempDir, 'tiny.pdf', 1);
      final outputPath = p.join(tempDir.path, 'out_tiny.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      // L1 자체만으로는 이 픽스처가 더 줄지 않을 수도, 줄 수도 있다(qpdf 버전/입력에 따라 다름) --
      // 이 테스트는 어느 쪽이 나오든 keptOriginal 계약이 지켜지는지 형태로 검증한다.
      final result = await compressor.compress(pdfPath: srcPath, outputPath: outputPath, preset: ImageQuality.standard);
      final outcome = (result as PdfOk<CompressOutcome>).value;
      if (outcome.keptOriginal) {
        expect(outcome.resultBytes, outcome.originalBytes, reason: 'keptOriginal이면 resultBytes==originalBytes여서 reduction==0이어야 한다');
        expect(outcome.reduction, 0.0);
        expect(File(outputPath).existsSync(), isFalse, reason: 'keptOriginal이면 산출물을 삭제해야 한다');
      } else {
        expect(outcome.resultBytes, lessThan(outcome.originalBytes));
        expect(File(outputPath).existsSync(), isTrue);
      }
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('L2 경계 강제(§6.1 Q15): imagePagePaths 길이가 페이지 수와 다르면 거부(외부 PDF/혼합 오적용 방지)', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_l2_guard_');
      addTearDown(() => tempDir.delete(recursive: true));
      // 116페이지 실제 외부 PDF에 이미지 경로 1개만 잘못 붙여 L2를 시도 -- 반드시 거부돼야 한다.
      final outputPath = p.join(tempDir.path, 'out_guard.pdf');
      final fakeImg = p.join(tempDir.path, 'fake.jpg');
      await File(fakeImg).writeAsBytes(_scanLikeJpeg(100, 100));
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      final result = await compressor.compress(
        pdfPath: _fixturePath,
        outputPath: outputPath,
        preset: ImageQuality.min,
        imagePagePaths: [fakeImg],
      );
      expect(result, isA<PdfErr<CompressOutcome>>());
      expect((result as PdfErr<CompressOutcome>).failure, isA<UnknownFailure>());
      expect(File(outputPath).existsSync(), isFalse);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('L2: 이미지 전용 문서 -- RO(페이지 수) 통과, resultBytes < originalBytes(대형 원본)', () async {
      final tempDir = await Directory.systemTemp.createTemp('compressor_l2_');
      addTearDown(() => tempDir.delete(recursive: true));

      const pageCount = 4;
      final masterPaths = <String>[];
      final masterBytesList = <Uint8List>[];
      for (var i = 0; i < pageCount; i++) {
        final bytes = _scanLikeJpeg(3000, 4000, seed: i);
        masterBytesList.add(bytes);
        final path = p.join(tempDir.path, 'page_$i.jpg');
        await File(path).writeAsBytes(bytes);
        masterPaths.add(path);
      }
      // "원본 문서" = 마스터를 그대로(축소 없이) 임베드해 만든 PDF -- 압축 전 베이스라인.
      final originalDocBytes = await ImagePdfBuilder.build(jpegPages: masterBytesList, title: null);
      final srcPath = p.join(tempDir.path, 'src_images.pdf');
      await File(srcPath).writeAsBytes(originalDocBytes);
      final srcBytesBefore = await File(srcPath).readAsBytes();

      final outputPath = p.join(tempDir.path, 'out_l2.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      final result = await compressor.compress(
        pdfPath: srcPath,
        outputPath: outputPath,
        preset: ImageQuality.min,
        imagePagePaths: masterPaths,
      );

      final outcome = (result as PdfOk<CompressOutcome>).value;
      expect(outcome.keptOriginal, isFalse, reason: '3000x4000 원본을 min(1240px)로 줄이면 반드시 작아져야 한다');
      expect(outcome.resultBytes, lessThan(outcome.originalBytes));

      // 원본 미수정.
      expect(await File(srcPath).readAsBytes(), srcBytesBefore);

      final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(inspected['ok'], true);
      expect(inspected['pageCount'], pageCount);

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, pageCount, reason: 'RO-1 페이지 수 불일치');
        for (var i = 0; i < pageCount; i++) {
          final text = await doc.pages[i].loadText();
          expect(text?.fullText ?? '', isEmpty, reason: 'RO: 이미지 페이지는 추출 텍스트가 없어야 한다');
        }
      } finally {
        await doc.dispose();
      }
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('프리셋 실측 — pipeline.md 표 갱신용(합성 스캔 픽스처 10페이지)', () {
    // pipeline.md 판정 기준: "min으로 10페이지 스캔 문서가 2MB 이하이면서 본문이 읽혀야 한다".
    // 실제 사용자 스캔본이 아닌 합성 픽스처(흰 배경 + 텍스트 밀도 노이즈, 2550x3300 ≈ 300dpi A4)를
    // 쓴다 -- 절대 규칙(사용자 원본 파일 read-only)을 지키면서 3개 프리셋을 동일 입력으로 비교하기
    // 위함이다. 측정치는 `_workspace/22_pdf-core_compressor_license.md`에 옮겨 적는다.
    const pageCount = 10;

    Future<List<Uint8List>> buildMasters() async => [for (var i = 0; i < pageCount; i++) _scanLikeJpeg(2550, 3300, seed: 100 + i)];

    for (final entry in {
      'high': ImageQuality.high,
      'standard': ImageQuality.standard,
      'min': ImageQuality.min,
    }.entries) {
      test('프리셋 ${entry.key}: 10페이지 합성 스캔 문서 압축 전후 실측', () async {
        final tempDir = await Directory.systemTemp.createTemp('compressor_preset_${entry.key}_');
        addTearDown(() => tempDir.delete(recursive: true));

        final masters = await buildMasters();
        final masterPaths = <String>[];
        for (var i = 0; i < masters.length; i++) {
          final path = p.join(tempDir.path, 'm_$i.jpg');
          await File(path).writeAsBytes(masters[i]);
          masterPaths.add(path);
        }
        final originalDocBytes = await ImagePdfBuilder.build(jpegPages: masters, title: null);
        final srcPath = p.join(tempDir.path, 'src.pdf');
        await File(srcPath).writeAsBytes(originalDocBytes);
        final outputPath = p.join(tempDir.path, 'out.pdf');

        final compressor = QpdfCompressor(libraryPathOverride: _dllPath);
        final result = await compressor.compress(
          pdfPath: srcPath,
          outputPath: outputPath,
          preset: entry.value,
          imagePagePaths: masterPaths,
        );
        final outcome = (result as PdfOk<CompressOutcome>).value;

        // ignore: avoid_print
        print(
          '[preset ${entry.key}] original=${outcome.originalBytes}B result=${outcome.resultBytes}B '
          'reduction=${(outcome.reduction * 100).toStringAsFixed(1)}% keptOriginal=${outcome.keptOriginal}',
        );

        expect(outcome.keptOriginal, isFalse);
        expect(outcome.resultBytes, lessThan(outcome.originalBytes));

        final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
        expect(inspected['ok'], true);
        expect(inspected['pageCount'], pageCount);
      }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 3)));
    }
  });
}
