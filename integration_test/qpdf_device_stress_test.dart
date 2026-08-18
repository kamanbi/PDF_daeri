// M-Q5 실기기 대용량/취소/손상 파일 스트레스 측정용. §21(_workspace/21_...) 산출물.
// 합성 픽스처는 리포지토리에 커밋하지 않는다 -- /data/local/tmp/에 adb push로만 올린다
// (integration_test는 매 실행마다 앱을 재설치하며 앱 전용 외부 저장소를 비우기 때문).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('QPDF Device Stress Tests', () {
    final bigFile = File('/data/local/tmp/big_fixture.pdf');
    final truncatedFile = File('/data/local/tmp/corrupt_truncated.pdf');
    final headerOnlyFile = File('/data/local/tmp/corrupt_headeronly.pdf');
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('qpdf_stress_');
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Big fixture exists and inspect reports page count', () async {
      expect(bigFile.existsSync(), true, reason: 'big_fixture.pdf not found at /data/local/tmp/');
      final bytes = bigFile.lengthSync();
      print('=== Big fixture ===');
      print('bytes: $bytes');

      final sw = Stopwatch()..start();
      final result = await runInspect(pdfPath: bigFile.path);
      sw.stop();
      print('inspect elapsed ms: ${sw.elapsedMilliseconds}');
      print('inspect ok: ${result['ok']}, pageCount: ${result['pageCount']}, detail: ${result['detail']}');
      expect(result['ok'], true, reason: 'runInspect failed: ${result['detail']}');
    });

    test('Delete 1 page from big fixture and measure save time', () async {
      expect(bigFile.existsSync(), true);
      final inspect = await runInspect(pdfPath: bigFile.path);
      expect(inspect['ok'], true, reason: 'pre-inspect failed: ${inspect['detail']}');
      final pageCount = inspect['pageCount'] as int;
      print('=== Delete-1-page save timing ===');
      print('source pageCount: $pageCount, source bytes: ${bigFile.lengthSync()}');

      final outputFile = File('${tempDir.path}/out_delete1.pdf');
      final pageIndices = List<int>.generate(pageCount - 1, (i) => i); // 마지막 페이지 삭제

      final sw = Stopwatch()..start();
      final result = await runSaveJob(sourcePath: bigFile.path, outputPath: outputFile.path, pageIndices: pageIndices);
      sw.stop();

      print('save elapsed ms: ${sw.elapsedMilliseconds}');
      print('save ok: ${result['ok']}, bytes: ${result['bytes']}, pageCount: ${result['pageCount']}, detail: ${result['detail']}');
      expect(result['ok'], true, reason: 'runSaveJob failed: ${result['detail']}');
      expect(outputFile.existsSync(), true);

      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('Cancel during save reflects only after job completion (not immediate)', () async {
      expect(bigFile.existsSync(), true);
      final inspect = await runInspect(pdfPath: bigFile.path);
      expect(inspect['ok'], true);
      final pageCount = inspect['pageCount'] as int;

      final outputFile = File('${tempDir.path}/out_cancel.pdf');
      final pageIndices = List<int>.generate(pageCount - 1, (i) => i);

      final cancelToken = CancelToken();
      final overallSw = Stopwatch()..start();

      // 잡 시작 후 200ms 뒤 취소 신호를 건다. §7.1/§5.4 규칙: 잡 시작 후 취소는 완료를
      // 기다린 뒤 출력 삭제이므로, 취소 신호 시각과 runSaveJob이 실제로 완료(future resolve)한
      // 시각의 간격을 측정해 "즉시 vs 완료 후"를 실측으로 구분한다.
      Timer(const Duration(milliseconds: 200), () {
        cancelToken.cancel();
        print('cancel signal sent at ms: ${overallSw.elapsedMilliseconds}');
      });

      final result = await runSaveJob(
        sourcePath: bigFile.path,
        outputPath: outputFile.path,
        pageIndices: pageIndices,
        cancelToken: cancelToken,
      );
      overallSw.stop();

      print('=== Cancel timing ===');
      print('runSaveJob future resolved at ms: ${overallSw.elapsedMilliseconds}');
      print('result ok: ${result['ok']}, error: ${result['error']}');
      print('output file exists after cancel: ${outputFile.existsSync()}');

      expect(result['ok'], false, reason: 'expected cancelled result, got: $result');
      expect(result['error'], 'cancelled');
      expect(outputFile.existsSync(), false, reason: 'output should be deleted after cancellation');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('pdfrx render/thumbnail timing on big fixture', () async {
      expect(bigFile.existsSync(), true);
      final renderer = PdfxRenderer();
      try {
        final openSw = Stopwatch()..start();
        final countResult = await renderer.openPageCount(bigFile.path);
        openSw.stop();
        print('=== pdfrx render timing ===');
        print('openFile+pageCount elapsed ms: ${openSw.elapsedMilliseconds}');
        print('openPageCount ok: ${countResult is PdfOk}');
        if (countResult is! PdfOk<int>) {
          print('openPageCount failed, skipping render');
          return;
        }
        final pageCount = countResult.value;
        print('pdfrx pageCount: $pageCount');

        final firstSw = Stopwatch()..start();
        final firstPage = await renderer.renderPage(pdfPath: bigFile.path, pageIndex: 0, targetWidthPx: 200);
        firstSw.stop();
        print('renderPage(0, w=200) thumbnail elapsed ms: ${firstSw.elapsedMilliseconds}, ok: ${firstPage is PdfOk}');

        final midIndex = pageCount ~/ 2;
        final midSw = Stopwatch()..start();
        final midPage = await renderer.renderPage(pdfPath: bigFile.path, pageIndex: midIndex, targetWidthPx: 200);
        midSw.stop();
        print('renderPage($midIndex, w=200) thumbnail elapsed ms: ${midSw.elapsedMilliseconds}, ok: ${midPage is PdfOk}');

        final fullSw = Stopwatch()..start();
        final fullPage = await renderer.renderPage(pdfPath: bigFile.path, pageIndex: 0, targetWidthPx: 1200);
        fullSw.stop();
        print('renderPage(0, w=1200) full-res elapsed ms: ${fullSw.elapsedMilliseconds}, ok: ${fullPage is PdfOk}');
      } finally {
        renderer.evictCache();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('Corrupted file (truncated) does not crash and returns clear error', () async {
      expect(truncatedFile.existsSync(), true, reason: 'corrupt_truncated.pdf not found');
      print('=== Corrupted: truncated ===');
      print('truncated bytes: ${truncatedFile.lengthSync()}');

      final inspectResult = await runInspect(pdfPath: truncatedFile.path);
      print('inspect result: $inspectResult');

      final outputFile = File('${tempDir.path}/out_truncated.pdf');
      final saveResult = await runSaveJob(sourcePath: truncatedFile.path, outputPath: outputFile.path, pageIndices: const [0]);
      print('save result: $saveResult');
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }

      // 크래시 없이 이 지점까지 도달한 것 자체가 검증. ok가 false든 true든 무음 실패가
      // 아니라 result map(error/detail)이 채워져 있어야 한다.
      if (inspectResult['ok'] != true) {
        expect(inspectResult['error'], isNotNull);
      }
      if (saveResult['ok'] != true) {
        expect(saveResult['error'], isNotNull);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Corrupted file (header-only random bytes) does not crash and returns clear error', () async {
      expect(headerOnlyFile.existsSync(), true, reason: 'corrupt_headeronly.pdf not found');
      print('=== Corrupted: header-only ===');
      print('header-only bytes: ${headerOnlyFile.lengthSync()}');

      final inspectResult = await runInspect(pdfPath: headerOnlyFile.path);
      print('inspect result: $inspectResult');

      final outputFile = File('${tempDir.path}/out_headeronly.pdf');
      final saveResult = await runSaveJob(sourcePath: headerOnlyFile.path, outputPath: outputFile.path, pageIndices: const [0]);
      print('save result: $saveResult');
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }

      if (inspectResult['ok'] != true) {
        expect(inspectResult['error'], isNotNull);
      }
      if (saveResult['ok'] != true) {
        expect(saveResult['error'], isNotNull);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
