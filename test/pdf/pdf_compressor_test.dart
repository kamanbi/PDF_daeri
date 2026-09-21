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
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/pdf/image_pdf_builder.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';
import 'package:pdf_daeri/pdf/pdf_compressor.dart';
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'raw_pdf_fixture.dart';

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

    // T2(§76 §7): "원본"은 저장 화질이지 압축 강도가 아니다(§76 §1.5) -- qpdf/파일 존재
    // 여부와 무관하게 진입 즉시 거부돼야 한다. 존재하지 않는 경로로 호출해 이 거부가
    // SourceMissing보다 먼저 일어난다는 것까지 확인한다.
    test('T2: preset이 패스스루(original)이면 진입 즉시 PdfErr를 반환한다', () async {
      final result = await compressor.compress(
        pdfPath: '/no/such/file.pdf',
        outputPath: '/tmp/out.pdf',
        preset: ImageQuality.original,
      );
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

  // ── M-E5/M-E6: L2-ext(외부 PDF 임베디드 이미지 압축, `_workspace/31_...md` §2.2/§2.6) ─────────
  group('compress() — L2-ext(embeddedImageStagingDir) 3-패스 오케스트레이션', () {
    test('상호 배타(§2.6 검사24): imagePagePaths와 embeddedImageStagingDir를 동시에 주면 즉시 거부', () async {
      final tempDir = await Directory.systemTemp.createTemp('l2ext_mutex_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await _buildMarkerPdf(tempDir, 'src.pdf', 1);
      final stagingDir = p.join(tempDir.path, 'staging');
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = const QpdfCompressor(); // FFI 호출 이전에 거부되므로 libraryPathOverride 불필요.

      final result = await compressor.compress(
        pdfPath: srcPath,
        outputPath: outputPath,
        preset: ImageQuality.standard,
        imagePagePaths: const ['fake.jpg'],
        embeddedImageStagingDir: stagingDir,
      );
      expect(result, isA<PdfErr<CompressOutcome>>());
      expect((result as PdfErr<CompressOutcome>).failure, isA<UnknownFailure>());
      expect(File(outputPath).existsSync(), isFalse);
    });

    test('텍스트 PDF -- 적격 이미지 0개(L1만 실행), RO(페이지 수 + **텍스트 바이트 동일성**) 통과, 원본 미수정', () async {
      final tempDir = await Directory.systemTemp.createTemp('l2ext_text_');
      addTearDown(() => tempDir.delete(recursive: true));
      const pageCount = 6;
      final srcPath = await _buildMarkerPdf(tempDir, 'src.pdf', pageCount);
      final srcBytesBefore = await File(srcPath).readAsBytes();

      // 압축 전 원본에서 추출한 텍스트(비교 기준선) -- 설계 문서가 요구하는 "바이트 단위 동일성"은
      // PDF 파일 전체의 바이트 동일성이 아니라(L1이 항상 컨테이너를 재작성하므로 그건 불가능하다)
      // **추출 텍스트 문자열의 완전 동일성**이다(§31 §2.5, 절대 규칙 2 봉쇄 실측).
      final beforeDoc = await pdfrx.PdfDocument.openFile(srcPath);
      final beforeTexts = <String>[];
      try {
        for (var i = 0; i < pageCount; i++) {
          beforeTexts.add((await beforeDoc.pages[i].loadText())?.fullText ?? '');
        }
      } finally {
        await beforeDoc.dispose();
      }

      final stagingDir = p.join(tempDir.path, 'staging');
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      final result = await compressor.compress(
        pdfPath: srcPath,
        outputPath: outputPath,
        preset: ImageQuality.standard,
        embeddedImageStagingDir: stagingDir,
      );
      final outcome = (result as PdfOk<CompressOutcome>).value;

      // 원본 미수정(절대 규칙 6) -- 패스 A는 읽기 전용이어야 한다.
      expect(await File(srcPath).readAsBytes(), srcBytesBefore);

      final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(inspected['ok'], true);
      expect(inspected['pageCount'], pageCount);

      final afterDoc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(afterDoc.pages.length, pageCount);
        for (var i = 0; i < pageCount; i++) {
          final afterText = (await afterDoc.pages[i].loadText())?.fullText ?? '';
          expect(afterText, equals(beforeTexts[i]), reason: '텍스트 바이트 동일성(§31 §2.5): 페이지 $i의 추출 텍스트가 압축 전후 완전히 같아야 한다');
        }
      } finally {
        await afterDoc.dispose();
      }
      // 참고 기록용(단언 아님): keptOriginal 여부는 L1 자체의 효과에 좌우된다.
      // ignore: avoid_print
      print('[L2-ext 텍스트] keptOriginal=${outcome.keptOriginal} reduction=${(outcome.reduction * 100).toStringAsFixed(1)}%');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('스캔형 외부 PDF(DCTDecode/DeviceRGB, 상한 초과) -- 실제로 작아짐, RO(페이지 수) 통과, 원본 미수정', () async {
      final tempDir = await Directory.systemTemp.createTemp('l2ext_scan_');
      addTearDown(() => tempDir.delete(recursive: true));
      const pageCount = 4;
      final jpegs = [for (var i = 0; i < pageCount; i++) _scanLikeJpeg(2400, 3000, seed: 200 + i)];
      final srcBytes = buildMultiPageImagePdf(jpegPagesBytes: jpegs, width: 2400, height: 3000);
      final srcPath = p.join(tempDir.path, 'src.pdf');
      await File(srcPath).writeAsBytes(srcBytes);
      final srcBytesBefore = await File(srcPath).readAsBytes();

      final stagingDir = p.join(tempDir.path, 'staging');
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      final result = await compressor.compress(
        pdfPath: srcPath,
        outputPath: outputPath,
        preset: ImageQuality.min,
        embeddedImageStagingDir: stagingDir,
      );
      final outcome = (result as PdfOk<CompressOutcome>).value;

      expect(outcome.keptOriginal, isFalse, reason: '2400x3000 DCT 원본을 min(1240px)로 다운샘플링하면 반드시 작아져야 한다');
      expect(outcome.resultBytes, lessThan(outcome.originalBytes));
      expect(await File(srcPath).readAsBytes(), srcBytesBefore, reason: '원본 미수정(절대 규칙 6)');

      final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(inspected['ok'], true);
      expect(inspected['pageCount'], pageCount);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));

    test('혼합 PDF(텍스트 페이지 + 이미지 페이지) -- 결과가 작아지고, 텍스트 페이지 내용은 그대로 유지된다', () async {
      final tempDir = await Directory.systemTemp.createTemp('l2ext_mixed_');
      addTearDown(() => tempDir.delete(recursive: true));

      // 텍스트 페이지 1장 + (상한을 넘는) 이미지 페이지 1장을 qpdf runComposeJob(기존, 무변경)으로
      // 하나의 혼합 문서로 합친다 -- 두 소스 모두 이미 검증된 빌더로 만들어 구조적으로 안전하다.
      final textOnlyPath = p.join(tempDir.path, 'text_only.pdf');
      await File(textOnlyPath).writeAsBytes(await File(await _buildMarkerPdf(tempDir, 'marker.pdf', 1)).readAsBytes());
      final imageJpeg = _scanLikeJpeg(2400, 3000, seed: 300);
      final imageOnlyPath = p.join(tempDir.path, 'image_only.pdf');
      await File(
        imageOnlyPath,
      ).writeAsBytes(buildMultiPageImagePdf(jpegPagesBytes: [imageJpeg], width: 2400, height: 3000));

      final mixedPath = p.join(tempDir.path, 'mixed_src.pdf');
      final composeResult = await runComposeJob(
        pages: [
          QpdfPageSource(sourcePath: textOnlyPath, sourceIndex: 0),
          QpdfPageSource(sourcePath: imageOnlyPath, sourceIndex: 0),
        ],
        outputPath: mixedPath,
        libraryPathOverride: _dllPath,
      );
      expect(composeResult['ok'], true, reason: '${composeResult['error']}: ${composeResult['detail']}');

      final beforeDoc = await pdfrx.PdfDocument.openFile(mixedPath);
      final beforeTextPage0 = (await beforeDoc.pages[0].loadText())?.fullText ?? '';
      await beforeDoc.dispose();

      final stagingDir = p.join(tempDir.path, 'staging');
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);
      final result = await compressor.compress(
        pdfPath: mixedPath,
        outputPath: outputPath,
        preset: ImageQuality.min,
        embeddedImageStagingDir: stagingDir,
      );
      final outcome = (result as PdfOk<CompressOutcome>).value;
      expect(outcome.keptOriginal, isFalse);
      expect(outcome.resultBytes, lessThan(outcome.originalBytes));

      final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(inspected['ok'], true);
      expect(inspected['pageCount'], 2, reason: '혼합 문서(텍스트1+이미지1)의 페이지 수는 그대로 유지돼야 한다');

      final afterDoc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        final afterTextPage0 = (await afterDoc.pages[0].loadText())?.fullText ?? '';
        expect(afterTextPage0, equals(beforeTextPage0), reason: '혼합 문서에서도 텍스트 페이지는 이미지 치환의 영향을 받지 않아야 한다');
      } finally {
        await afterDoc.dispose();
      }
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ── T5(§76 §7): compressToTarget 반복 알고리즘 계약 ──────────────────────────────────
  group('compressToTarget() — T5 계약', () {
    // L1-only 경로(imagePagePaths/embeddedImageStagingDir 둘 다 지정하지 않음)를 쓴다 --
    // 이 경로에서는 CompressRung이 결과에 영향을 주지 않으므로(§76 §3.3 _compressOnce가
    // rung을 L2에서만 쓴다), 매 시도의 resultBytes가 항상 같아 완전히 결정론적으로
    // "몇 번 실패하는지"를 설계할 수 있다. 실측(마커 PDF, 8~60페이지)으로 L1 압축비가
        // 항상 원본의 약 0.55~0.58배로 나온다는 것을 확인했다 -- 이 사실에 기대어 targetBytes를
    // 산술로 고른다(파일을 먼저 압축해 보지 않고도 시작 rung과 실패/성공을 예측한다).
    Future<String> buildMarkerFile(Directory dir, int count) => _buildMarkerPdf(dir, 'target_src.pdf', count);

    test('① targetBytes >= 원본이면 압축을 한 번도 실행하지 않는다', () async {
      final tempDir = await Directory.systemTemp.createTemp('target_t1_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = p.join(tempDir.path, 'src.pdf');
      await File(srcPath).writeAsBytes(List.filled(1000, 7));
      final originalBytes = await File(srcPath).length();
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = const QpdfCompressor();

      var onAttemptCalls = 0;
      final result = await compressor.compressToTarget(
        pdfPath: srcPath,
        outputPath: outputPath,
        targetBytes: originalBytes, // ==원본이어도 "즉시 반환" 조건을 만족해야 한다.
        onAttempt: (_) => onAttemptCalls++,
      );

      final target = (result as PdfOk<TargetCompressOutcome>).value;
      expect(target.attempts, 0);
      expect(target.reachedTarget, isTrue);
      expect(target.outcome.keptOriginal, isTrue);
      expect(target.outcome.originalBytes, originalBytes);
      expect(target.outcome.resultBytes, originalBytes);
      expect(onAttemptCalls, 0, reason: '시도 0회면 onAttempt도 호출되지 않아야 한다');
      // 압축이 실행되지 않았으므로 outputPath에 새 파일이 생기지 않는다.
      expect(File(outputPath).existsSync(), isFalse);
      expect(File('$outputPath.prev').existsSync(), isFalse);
    });

    test('② 1회 시도로 목표를 달성하면 더 내려가지 않고 즉시 채택한다', () async {
      final tempDir = await Directory.systemTemp.createTemp('target_t2_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await buildMarkerFile(tempDir, 20);
      final originalBytes = await File(srcPath).length();
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      // predictedBytes(standard)=0.65*원본 <= target이 되도록 넉넉히 잡는다 -- startIndexFor가
      // standard(인덱스1)를 시작 단으로 고르고, 실측상 L1 결과(~0.56배)가 이보다 훨씬 작으므로
      // 첫 시도에서 반드시 성공한다.
      final targetBytes = (originalBytes * 0.75).round();
      final attempts = <TargetAttempt>[];
      final result = await compressor.compressToTarget(
        pdfPath: srcPath,
        outputPath: outputPath,
        targetBytes: targetBytes,
        onAttempt: attempts.add,
      );

      final target = (result as PdfOk<TargetCompressOutcome>).value;
      expect(target.attempts, 1);
      expect(target.reachedTarget, isTrue);
      expect(target.outcome.keptOriginal, isFalse);
      expect(target.outcome.resultBytes, lessThanOrEqualTo(targetBytes));
      expect(attempts, hasLength(1));
      expect(attempts.single.attempt, 1);
      expect(attempts.single.lastResultBytes, isNull, reason: '첫 시도는 직전 결과가 없다');

      // 최종 산출물은 outputPath 하나뿐이다(T5 ⑤).
      expect(File(outputPath).existsSync(), isTrue);
      expect(File('$outputPath.prev').existsSync(), isFalse);

      final inspected = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(inspected['ok'], true);
      expect(inspected['pageCount'], 20);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('③ maxAttempts 소진 후 reachedTarget:false로 종료한다(사다리 끝 도달이 아니다)', () async {
      final tempDir = await Directory.systemTemp.createTemp('target_t3_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await buildMarkerFile(tempDir, 20);
      final originalBytes = await File(srcPath).length();
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      // targetBytes를 [predictedBytes(min)=0.45*원본, 실측 L1 결과~0.56*원본) 구간에 두면
      // startIndexFor는 산술만으로 min(인덱스2)을 시작 단으로 고른다. 이 경로는 L1-only라
      // rung이 결과에 영향을 주지 않으므로(위 설명) 어떤 rung을 시도해도 항상 target보다
      // 큰 동일한 결과가 나와 반드시 실패한다 -- maxAttempts(2)를 다 쓸 때까지 사다리 끝
      // (인덱스4)에는 닿지 않는다(2->3까지만 진행).
      final targetBytes = (originalBytes * 0.5).round();
      final attempts = <TargetAttempt>[];
      final result = await compressor.compressToTarget(
        pdfPath: srcPath,
        outputPath: outputPath,
        targetBytes: targetBytes,
        maxAttempts: 2,
        onAttempt: attempts.add,
      );

      final target = (result as PdfOk<TargetCompressOutcome>).value;
      expect(target.attempts, 2, reason: 'maxAttempts(2)를 다 써야 한다');
      expect(target.reachedTarget, isFalse);
      expect(target.outcome.keptOriginal, isFalse);
      expect(target.outcome.resultBytes, greaterThan(targetBytes));
      expect(target.finalRungIndex, lessThan(4), reason: '사다리 끝(인덱스4)에 닿기 전에 시도 소진으로 멈춰야 한다');
      expect(attempts, hasLength(2));
      expect(attempts[0].attempt, 1);
      expect(attempts[1].attempt, 2);
      expect(attempts[1].lastResultBytes, isNotNull, reason: '2번째 시도부터는 직전 결과가 있어야 한다');

      // 그때까지의 최선 결과가 outputPath 하나에만 남는다(T5 ⑤) -- .prev 잔재가 없어야 한다.
      expect(File(outputPath).existsSync(), isTrue);
      expect(File('$outputPath.prev').existsSync(), isFalse);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('④ 취소 토큰이 시도 사이에서도 듣는다(다음 시도를 시작하지 않는다)', () async {
      final tempDir = await Directory.systemTemp.createTemp('target_t4_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await buildMarkerFile(tempDir, 20);
      final originalBytes = await File(srcPath).length();
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      // ③과 같은 구간 -- 1회로는 목표를 달성하지 못해 2번째 시도가 예정된다.
      final targetBytes = (originalBytes * 0.5).round();
      final cancelToken = CancelToken();
      final attempts = <TargetAttempt>[];

      final result = await compressor.compressToTarget(
        pdfPath: srcPath,
        outputPath: outputPath,
        targetBytes: targetBytes,
        maxAttempts: 3,
        cancelToken: cancelToken,
        onAttempt: (a) {
          attempts.add(a);
          if (a.attempt == 1) {
            // 1번째 시도가 보고된 직후 취소한다 -- 1번째 압축 자체는 이미 시작됐으므로 끝까지
            // 돌지만, 2번째 시도는 루프 상단의 취소 확인에서 걸려 시작조차 하지 않아야 한다.
            cancelToken.cancel();
          }
        },
      );

      expect(result, isA<PdfErr<TargetCompressOutcome>>());
      expect((result as PdfErr<TargetCompressOutcome>).failure, isA<Cancelled>());
      expect(attempts, hasLength(1), reason: '2번째 시도는 onAttempt조차 호출되지 않아야 한다(취소가 시도 사이에서 걸린다)');

      // 취소 시 잔여 파일을 남기지 않는다(T5 ⑤와 같은 원칙 -- 실패 시에도 산출물이 없어야 한다).
      expect(File(outputPath).existsSync(), isFalse);
      expect(File('$outputPath.prev').existsSync(), isFalse);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('⑤ 최종 산출물은 항상 outputPath 하나뿐이다(여러 시나리오 교차 확인)', () async {
      final tempDir = await Directory.systemTemp.createTemp('target_t5_');
      addTearDown(() => tempDir.delete(recursive: true));
      final srcPath = await buildMarkerFile(tempDir, 20);
      final originalBytes = await File(srcPath).length();
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      // 성공 시나리오.
      final outSuccess = p.join(tempDir.path, 'out_success.pdf');
      await compressor.compressToTarget(
        pdfPath: srcPath,
        outputPath: outSuccess,
        targetBytes: (originalBytes * 0.75).round(),
      );
      expect(File(outSuccess).existsSync(), isTrue);
      expect(File('$outSuccess.prev').existsSync(), isFalse);

      // 소진 시나리오(3회 시도, prev/cur가 여러 번 번갈아 쓰인다).
      final outExhausted = p.join(tempDir.path, 'out_exhausted.pdf');
      await compressor.compressToTarget(
        pdfPath: srcPath,
        outputPath: outExhausted,
        targetBytes: (originalBytes * 0.5).round(),
        maxAttempts: 3,
      );
      expect(File(outExhausted).existsSync(), isTrue);
      expect(File('$outExhausted.prev').existsSync(), isFalse);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));
  });
}
