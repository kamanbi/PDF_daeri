import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('QPDF Device Smoke Tests', () {
    // 기기에서 실행되는 integration_test는 호스트 파일시스템의 상대 경로를
    // 읽을 수 없다. 앱 전용 외부 저장소(/sdcard/Android/data/<pkg>/files)는
    // flutter test가 매번 앱을 재설치하며 비운다는 것이 실측으로 확인되어,
    // 앱 설치와 무관하게 남는 /data/local/tmp/ 에 adb push로 올려둔 사본을
    // 절대 경로로 읽는다. 원본은 F:\PDF_daeri\test\fixtures\ 그대로 보존.
    final fixtureFile = File('/data/local/tmp/fixture.pdf');
    late Directory tempDir;

    setUpAll(() async {
      // Create temporary directory for test outputs
      tempDir = await Directory.systemTemp.createTemp('qpdf_test_');
    });

    tearDownAll(() async {
      // Clean up temporary files
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Test 1: DynamicLibrary.open success
    test('DynamicLibrary.open(libqpdf.so) should succeed', () async {
      try {
        final library = ffi.DynamicLibrary.open('libqpdf.so');
        expect(library, isNotNull);
        addTearDown(() => library.close());
      } catch (e) {
        fail('DynamicLibrary.open failed: $e');
      }
    });

    /// Test 2: Inspect original PDF — should report 116 pages
    test('Original PDF should have 116 pages', () async {
      expect(fixtureFile.existsSync(), true, reason: 'Fixture file not found');

      final result = await runInspect(pdfPath: fixtureFile.path);
      expect(result['ok'], true, reason: 'runInspect failed: ${result['detail']}');
      expect(result['pageCount'], 116, reason: 'Expected 116 pages, got ${result['pageCount']}');
      expect(result['isEncrypted'], false, reason: 'PDF should not be encrypted');
    });

    /// Test 3: Delete page at index 100 (1-based page 101) and measure output bytes
    test('Delete page index 100 and measure output bytes', () async {
      expect(fixtureFile.existsSync(), true, reason: 'Fixture file not found');

      final outputFile = File('${tempDir.path}/out_delete_idx100.pdf');
      final baselineBytes = fixtureFile.lengthSync();

      // Page indices for result: all pages except index 100
      final pageIndices = <int>[
        ...List.generate(100, (i) => i),  // 0-99
        ...List.generate(15, (i) => 101 + i),  // 101-115 (0-based, 116페이지 문서의 마지막 인덱스는 115)
      ];

      final result = await runSaveJob(
        sourcePath: fixtureFile.path,
        outputPath: outputFile.path,
        pageIndices: pageIndices,
      );

      expect(result['ok'], true, reason: 'runSaveJob failed: ${result['detail']}');
      expect(outputFile.existsSync(), true, reason: 'Output file not created');

      final outputBytes = result['bytes'] as int;
      final pageCount = result['pageCount'] as int;

      expect(pageCount, 115, reason: 'Expected 115 pages (116-1), got $pageCount');

      // Record measurements
      final ratio = outputBytes / baselineBytes;

      print('=== QPDF Device Smoke Test Results ===');
      print('Baseline (original) bytes: $baselineBytes');
      print('Result bytes (after delete): $outputBytes');
      print('Ratio (result/baseline): $ratio');
      print('Expected pages: 115');
      print('Actual pages: $pageCount');

      // Sanity check: output should not be larger than input (QPDF optimizes)
      expect(outputBytes <= baselineBytes, true,
        reason: 'Output should be ≤ original (QPDF optimizes), '
                'but got $outputBytes > $baselineBytes');

      // Clean up
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
    });
  });
}
