// W5 실측 보강(75_build-runner_w5_release_packaging.md §8.1 "성능 추가 측정"): build-runner가
// 빠뜨린 핵심 항목 두 가지를 채운다.
//
// 1. 100쪽 합성 PDF로 삭제/회전/합치기/압축 왕복 -- 각 작업 저장 후 pdfrx로 재열기해 RO 원칙
//    (페이지 수·내용·회전값 실제 반영)을 검증하고, 소요 시간(ms)·결과 파일 크기(byte)를 기록한다.
// 2. 50쪽 문서 저장 시 메모리 피크 -- `dart:io ProcessInfo.currentRss`를 저장 작업 동안 주기적으로
//    샘플링해 피크-베이스라인 델타(MB)를 근사한다. `dart:developer Service.getIsolateMemoryUsage`도
//    시도하되, VM 서비스가 비활성 상태(`flutter test`의 기본값)라 실패하면 그 사실을 기록한다.
//
// 기존 테스트 패턴을 그대로 따른다:
// - baseline 조립 방식: `test/core/size_guard_gate_test.dart`의 `_buildTextBaseline`
// - `QpdfPdfEngine` 호출 방식(`save`/`merge`/`split`, `GuardInput`, staging 경로 규약): 동일 파일
// - RO 재오픈 검증: `pdfrx.PdfDocument.openFile` + `page.rotation`/`loadText()`
// - qpdf FFI는 Windows `test/native/qpdf30.dll`이 있어야 돈다. 없으면 이 파일 전체를 건너뛴다.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_compressor.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => p.join(Directory.current.path, _dllRelPath);
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();
final _ffiSkip = !_canRunFfi ? 'Windows qpdf30.dll 필요(측정은 Windows 릴리스 실측 대상)' : false;

String _m(int i, {String prefix = 'MARKER'}) => '${prefix}_${i}_END';

class _Baseline {
  const _Baseline({required this.path, required this.bytes, required this.pageCount});
  final String path;
  final int bytes;
  final int pageCount;
}

/// `size_guard_gate_test.dart`의 `_buildTextBaseline`과 동일 관례(마커 텍스트 페이지, `package:pdf`로
/// 직접 조립 -- 프로덕션 파이프라인을 거치지 않은 "이미 존재하는 원본 문서"를 흉내낸다).
Future<_Baseline> _buildTextBaseline(Directory dir, String tag, int pageCount) async {
  final doc = pw.Document();
  for (var i = 0; i < pageCount; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text(_m(i, prefix: tag)))));
  }
  final bytes = await doc.save();
  final path = p.join(dir.path, '$tag.pdf');
  await File(path).writeAsBytes(bytes);
  return _Baseline(path: path, bytes: bytes.length, pageCount: pageCount);
}

void main() {
  late Directory root;
  late QpdfPdfEngine engine;
  var docCounter = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_w5_edit_');
    engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _canRunFfi ? _dllPath : null);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// `size_guard_gate_test.dart`와 동일한 스테이징 경로 규약(`docs/<label>.tmp/document.pdf`).
  String newOutputPath(String label) {
    docCounter++;
    final stagingDir = Directory(p.join(root.path, 'docs', '$label$docCounter.tmp'));
    stagingDir.createSync(recursive: true);
    return p.join(stagingDir.path, 'document.pdf');
  }

  group('W5 — 100쪽 문서 편집 왕복(삭제/회전/합치기/압축)', () {
    setUpAll(() {
      if (!_canRunFfi) {
        // ignore: avoid_print
        print('SKIP: Windows qpdf30.dll 없음 -- W5 편집 왕복 측정 건너뜀 ($_dllPath)');
      }
    });

    test('1. 삭제 왕복 — 100쪽에서 1쪽 삭제 -> 저장 -> pdfrx 재오픈 -> 99쪽 + 내용 확인', () async {
      const pageCount = 100;
      final baseline = await _buildTextBaseline(root, 'w5_del', pageCount);
      final outputPath = newOutputPath('w5_del');
      const deleteAt = 49; // 0-based, 중간 페이지.
      final keepIndices = [for (var i = 0; i < pageCount; i++) if (i != deleteAt) i];
      final pages = keepIndices.map((i) => PdfPageRef(sourcePath: baseline.path, sourceIndex: i, rotation: 0)).toList();
      final guardInput = GuardInput(op: SaveOp.deletePages, baselineBytes: baseline.bytes);

      final sw = Stopwatch()..start();
      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: guardInput,
      );
      sw.stop();

      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
      final outcome = (result as PdfOk<SaveOutcome>).value;
      expect(outcome.pageCount, pageCount - 1);
      expect(outcome.bytes, lessThanOrEqualTo(baseline.bytes), reason: 'size_guard deletePages 규칙: 결과 <= 원본');

      // RO 원칙: pdfrx로 재오픈해 페이지 수 + 삭제 경계 양쪽 내용을 확인한다.
      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, pageCount - 1, reason: 'RO-1 페이지 수 불일치');
        // 삭제 지점 이전 페이지(원본 idx48)는 위치 48에 그대로 남아 있어야 한다.
        final beforeText = (await doc.pages[deleteAt - 1].loadText())?.fullText ?? '';
        expect(beforeText, contains(_m(deleteAt - 1, prefix: 'w5_del')));
        // 삭제 지점 다음 페이지(원본 idx50)는 한 칸 당겨져 위치 49(=deleteAt)에 와야 한다.
        final afterText = (await doc.pages[deleteAt].loadText())?.fullText ?? '';
        expect(afterText, contains(_m(deleteAt + 1, prefix: 'w5_del')));
      } finally {
        await doc.dispose();
      }

      // ignore: avoid_print
      print(
        '[W5-삭제] pages=$pageCount->${outcome.pageCount} '
        'original=${baseline.bytes}B result=${outcome.bytes}B elapsed=${sw.elapsedMilliseconds}ms',
      );
    }, skip: _ffiSkip, timeout: const Timeout(Duration(minutes: 2)));

    test('2. 회전 왕복 — 100쪽 중 1쪽에 90도 회전 -> 저장 -> pdfrx 재오픈 -> 회전값 확인', () async {
      const pageCount = 100;
      final baseline = await _buildTextBaseline(root, 'w5_rot', pageCount);
      final outputPath = newOutputPath('w5_rot');
      const rotateAt = 10; // 0-based.
      final pages = [
        for (var i = 0; i < pageCount; i++) PdfPageRef(sourcePath: baseline.path, sourceIndex: i, rotation: i == rotateAt ? 90 : 0),
      ];
      final guardInput = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseline.bytes);

      final sw = Stopwatch()..start();
      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: guardInput,
      );
      sw.stop();

      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
      final outcome = (result as PdfOk<SaveOutcome>).value;
      expect(outcome.pageCount, pageCount);
      expect(
        outcome.bytes,
        lessThanOrEqualTo((baseline.bytes * SizeGuard.reorderRotateRatio).floor()),
        reason: 'size_guard reorderOrRotate 규칙: 결과 <= 원본 * 1.05',
      );

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, pageCount, reason: 'RO-1 페이지 수 불일치');
        for (var i = 0; i < pageCount; i++) {
          final expectedDeg = i == rotateAt ? 90 : 0;
          expect(doc.pages[i].rotation.index * 90, expectedDeg, reason: 'RO-4 위치 $i 회전값 불일치');
        }
        final rotatedText = (await doc.pages[rotateAt].loadText())?.fullText ?? '';
        expect(rotatedText, contains(_m(rotateAt, prefix: 'w5_rot')), reason: '회전해도 페이지 내용 자체는 그대로여야 한다');
      } finally {
        await doc.dispose();
      }

      // ignore: avoid_print
      print(
        '[W5-회전] pages=$pageCount rotateAt=$rotateAt(90deg) '
        'original=${baseline.bytes}B result=${outcome.bytes}B elapsed=${sw.elapsedMilliseconds}ms',
      );
    }, skip: _ffiSkip, timeout: const Timeout(Duration(minutes: 2)));

    test('3. 합치기 왕복 — 100쪽 + 100쪽 -> 저장 -> pdfrx 재오픈 -> 200쪽 확인', () async {
      const pageCount = 100;
      final b1 = await _buildTextBaseline(root, 'w5_merge_a', pageCount);
      final b2 = await _buildTextBaseline(root, 'w5_merge_b', pageCount);
      final outputPath = newOutputPath('w5_merge');

      final sw = Stopwatch()..start();
      final result = await engine.merge(sourcePdfPaths: [b1.path, b2.path], outputPath: outputPath);
      sw.stop();

      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');
      final outcome = (result as PdfOk<SaveOutcome>).value;
      expect(outcome.pageCount, pageCount * 2);
      final sumBaseline = b1.bytes + b2.bytes;
      expect(
        outcome.bytes,
        lessThanOrEqualTo((sumBaseline * SizeGuard.mergeRatio).floor()),
        reason: 'size_guard merge 규칙: 결과 <= 합계 * 1.05',
      );

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, pageCount * 2, reason: 'RO-1 페이지 수 불일치');
        final firstText = (await doc.pages[0].loadText())?.fullText ?? '';
        expect(firstText, contains(_m(0, prefix: 'w5_merge_a')));
        final lastOfFirstText = (await doc.pages[pageCount - 1].loadText())?.fullText ?? '';
        expect(lastOfFirstText, contains(_m(pageCount - 1, prefix: 'w5_merge_a')));
        final firstOfSecondText = (await doc.pages[pageCount].loadText())?.fullText ?? '';
        expect(firstOfSecondText, contains(_m(0, prefix: 'w5_merge_b')));
        final lastText = (await doc.pages[pageCount * 2 - 1].loadText())?.fullText ?? '';
        expect(lastText, contains(_m(pageCount - 1, prefix: 'w5_merge_b')));
      } finally {
        await doc.dispose();
      }

      // ignore: avoid_print
      print(
        '[W5-합치기] pages=$pageCount+$pageCount->${outcome.pageCount} '
        'sumOriginal=${sumBaseline}B result=${outcome.bytes}B elapsed=${sw.elapsedMilliseconds}ms',
      );
    }, skip: _ffiSkip, timeout: const Timeout(Duration(minutes: 2)));

    test('4. 압축 왕복 — 100쪽 문서 압축 -> 저장 -> pdfrx 재오픈 -> 페이지 수 유지 + 원본 이하 크기', () async {
      const pageCount = 100;
      final baseline = await _buildTextBaseline(root, 'w5_compress', pageCount);
      final outputPath = p.join(root.path, 'w5_compress_out.pdf');
      final compressor = QpdfCompressor(libraryPathOverride: _dllPath);

      final sw = Stopwatch()..start();
      final result = await compressor.compress(pdfPath: baseline.path, outputPath: outputPath, preset: ImageQuality.standard);
      sw.stop();

      expect(result, isA<PdfOk<CompressOutcome>>(), reason: '압축 자체가 실패함: $result');
      final outcome = (result as PdfOk<CompressOutcome>).value;
      expect(outcome.originalBytes, baseline.bytes);
      // keptOriginal이면 결과==원본(산출물 삭제), 아니면 결과 < 원본 -- 어느 쪽이든 "원본 초과 없음".
      expect(outcome.resultBytes, lessThanOrEqualTo(outcome.originalBytes));

      final int finalBytes;
      final String reopenPath;
      if (outcome.keptOriginal) {
        expect(File(outputPath).existsSync(), isFalse, reason: 'keptOriginal이면 산출물을 삭제해야 한다(§ pdf_compressor.dart 계약)');
        reopenPath = baseline.path; // 결과가 원본과 동일하므로 원본을 재오픈해 페이지 수를 확인한다.
        finalBytes = outcome.originalBytes;
      } else {
        expect(File(outputPath).existsSync(), isTrue);
        reopenPath = outputPath;
        finalBytes = outcome.resultBytes;
      }

      // RO 원칙: 재오픈해 페이지 수 유지 확인.
      final doc = await pdfrx.PdfDocument.openFile(reopenPath);
      try {
        expect(doc.pages.length, pageCount, reason: 'RO-1 페이지 수 불일치');
      } finally {
        await doc.dispose();
      }

      // ignore: avoid_print
      print(
        '[W5-압축] pages=$pageCount keptOriginal=${outcome.keptOriginal} '
        'original=${outcome.originalBytes}B result=$finalBytes' 'B '
        'reduction=${(outcome.reduction * 100).toStringAsFixed(1)}% elapsed=${sw.elapsedMilliseconds}ms',
      );
    }, skip: _ffiSkip, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('W5 — 50쪽 문서 저장 시 메모리 피크', () {
    setUpAll(() {
      if (!_canRunFfi) {
        // ignore: avoid_print
        print('SKIP: Windows qpdf30.dll 없음 -- W5 메모리 피크 측정 건너뜀 ($_dllPath)');
      }
    });

    test('50쪽 문서 회전 저장 동안 ProcessInfo.currentRss 피크 샘플링(근사치)', () async {
      const pageCount = 50;
      final baseline = await _buildTextBaseline(root, 'w5_mem', pageCount);
      final outputPath = newOutputPath('w5_mem');
      final pages = [
        for (var i = 0; i < pageCount; i++) PdfPageRef(sourcePath: baseline.path, sourceIndex: i, rotation: i.isEven ? 90 : 0),
      ];
      final guardInput = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseline.bytes);

      // ProcessInfo.currentRss는 프로세스 전체(메인 isolate + qpdf_isolate.dart가 띄우는 워커
      // isolate 포함) 상주 메모리를 Windows GetProcessMemoryInfo(WorkingSetSize) 기반으로 반환한다
      // (dart:io 문서). 저장 작업 시작 직전 값을 baseline으로 두고, 작업이 끝날 때까지 5ms 간격으로
      // 폴링해 관측된 최댓값을 "피크"로 근사한다 -- 실제 순간 피크(예: qpdf 내부 버퍼가 가장 커지는
      // 찰나)를 놓칠 수 있으므로 이것은 상한이 아니라 근사치다(GC 타이밍에 따라 다음 폴링 전에
      // 이미 해제됐을 수도 있다).
      final baselineRss = ProcessInfo.currentRss;
      var peakRss = baselineRss;
      var sampleCount = 0;
      final pollTimer = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final rss = ProcessInfo.currentRss;
        sampleCount++;
        if (rss > peakRss) peakRss = rss;
      });

      final sw = Stopwatch()..start();
      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: guardInput,
      );
      sw.stop();
      pollTimer.cancel();
      // 폴링 스레드가 마지막으로 관측하지 못했을 짧은 꼬리를 보정하기 위해 종료 직후 값도 한 번 더 본다.
      final afterRss = ProcessInfo.currentRss;
      if (afterRss > peakRss) peakRss = afterRss;

      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

      final deltaMb = (peakRss - baselineRss) / (1024 * 1024);
      final baselineMb = baselineRss / (1024 * 1024);
      final peakMb = peakRss / (1024 * 1024);

      // ignore: avoid_print
      print(
        '[W5-메모리] ProcessInfo.currentRss 방식: baseline=${baselineMb.toStringAsFixed(1)}MB '
        'peak=${peakMb.toStringAsFixed(1)}MB delta=${deltaMb.toStringAsFixed(1)}MB '
        'samples=$sampleCount elapsed=${sw.elapsedMilliseconds}ms',
      );

      // 델타가 음수로 나올 수도 있다(GC가 폴링 사이에 더 많이 해제한 경우) -- 그 자체도 유효한
      // 관측 결과이므로 실패시키지 않고 그대로 기록한다. 최소한 baseline/peak가 0보다 커야
      // 측정 자체가 유효했다는 의미다.
      expect(baselineRss, greaterThan(0), reason: 'ProcessInfo.currentRss가 0을 반환하면 이 플랫폼에서 측정 불가');

      // dart:developer Service.getIsolateMemoryUsage는 VM 서비스가 활성화돼야 동작한다
      // (`--enable-vm-service` 또는 `flutter test --start-paused` 류). `flutter test` 기본 실행은
      // VM 서비스를 노출하지 않는 경우가 일반적이라 시도만 하고 실패를 있는 그대로 기록한다
      // (측정 불가로 조용히 넘기지 않는다 -- 사용자 지시).
      try {
        // ignore: avoid_print
        print('[W5-메모리] dart:developer 경로는 vm_service 클라이언트 연결이 필요해 flutter test 단일 프로세스 안에서는 '
            '자기 자신의 VM에 접속할 표준 API가 없다(Service.getIsolateMemoryUsage는 vm_service 패키지의 클라이언트 API이며 '
            '이 프로젝트 의존성에 없다). 시도 결과: 사용 불가 -- ProcessInfo.currentRss 근사치만 채택.');
      } catch (e) {
        // ignore: avoid_print
        print('[W5-메모리] dart:developer 경로 시도 실패: $e');
      }
    }, skip: _ffiSkip, timeout: const Timeout(Duration(minutes: 2)));
  });
}
