// M-Q2 호스트 검증. Windows `qpdf30.dll`(`test/native/qpdf30.dll`, qpdf 12.4.0 공식 msvc64 배포물,
// `_workspace/16_pdf-core_qpdf_spike.md` §0에서 이미 승인·확보한 것과 동일 SHA-256)을 사용해
// `qpdf_isolate.dart`의 잡 빌더·워커·inspect를 실제 FFI 경로로 검증한다.
//
// BO 원칙: baseline은 항상 사용자 원본 픽스처의 실제 바이트다(§7.3). R5/스파이크와 동일 baseline
// (4,786,363 B, SHA-256 6a0df84c...)·동일 삭제 인덱스(0-based 100, 5)를 사용해 배율을 직접
// 비교할 수 있게 한다.
//
// FFI 잡 실행 테스트는 Windows에서만 돈다(qpdf30.dll이 Windows 전용 바이너리). 다른 플랫폼에서는
// 빌더(순수 함수) 테스트만 돈다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';

// SHA-256 6a0df84c42566a65a8e1ba61ae5276cd902be1d2b6b31fb4af8cc5eaa72cdca5(§16 스파이크에서 확인,
// 이 테스트는 `crypto` 패키지를 새 의존성으로 추가하지 않기 위해 바이트 수만 재확인한다).
const _fixtureRelPath = 'test/fixtures/(서일)-클라우디움 사용자 매뉴얼(윈도우탐색기)_20180821.pdf';
const _fixtureExpectedBytes = 4786363;
const _dllRelPath = 'test/native/qpdf30.dll';

String get _fixturePath => p.join(Directory.current.path, _fixtureRelPath);
String get _dllPath => p.join(Directory.current.path, _dllRelPath);

bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync() && File(_fixturePath).existsSync();

void main() {
  group('qpdf job builders (순수 함수, FFI 불필요)', () {
    test('buildSaveJob: 공통 쓰기 옵션 + range(순서 보존)', () {
      final job = buildSaveJob(sourcePath: 'in.pdf', outputPath: 'out.pdf', pageIndices: [2, 0, 1]);
      expect(job['inputFile'], 'in.pdf');
      expect(job['outputFile'], 'out.pdf');
      expect(job['pages'], [
        {'file': 'in.pdf', 'range': '3,1,2'},
      ]);
      expect(job['objectStreams'], 'generate');
      expect(job['compressStreams'], 'y');
      expect(job['recompressFlate'], '');
      expect(job['compressionLevel'], '9');
      expect(job['removeUnreferencedResources'], 'auto');
      expect(job['normalizeContent'], 'n');
      expect(job.containsKey('rotate'), isFalse);
    });

    test('buildRotateJob: 출력 위치(1-based) 기준 rotate 스펙, 상대 회전(+각도)', () {
      final job = buildRotateJob(
        sourcePath: 'in.pdf',
        outputPath: 'out.pdf',
        pages: const [
          QpdfPageEntry(sourceIndex: 1, rotation: 0),
          QpdfPageEntry(sourceIndex: 0, rotation: 90),
          QpdfPageEntry(sourceIndex: 2, rotation: 90),
          QpdfPageEntry(sourceIndex: 3, rotation: 180),
        ],
      );
      expect(job['pages'], [
        {'file': 'in.pdf', 'range': '2,1,3,4'},
      ]);
      // 회전 0인 항목(원본 index1, 출력위치1)은 rotate에 등장하지 않는다.
      // 90도 두 항목은 출력위치 2,3에 걸린다. 180도 한 항목은 출력위치 4.
      expect(job['rotate'], containsAll(<String>['+90:2,3', '+180:4']));
      expect((job['rotate'] as List).length, 2);
    });

    test('buildMergeJob: --empty + 소스 순서대로 pages, range 없음(전체 페이지)', () {
      final job = buildMergeJob(sourcePdfPaths: ['a.pdf', 'b.pdf'], outputPath: 'out.pdf');
      expect(job['empty'], '');
      expect(job['pages'], [
        {'file': 'a.pdf'},
        {'file': 'b.pdf'},
      ]);
      expect(job.containsKey('inputFile'), isFalse);
    });

    test('buildSplitJob: buildSaveJob과 동일 형태(§5.2, --split-pages 미사용)', () {
      final split = buildSplitJob(sourcePath: 'in.pdf', outputPath: 'out.pdf', pageIndices: [0, 2, 4]);
      final save = buildSaveJob(sourcePath: 'in.pdf', outputPath: 'out.pdf', pageIndices: [0, 2, 4]);
      expect(split, save);
    });

    test('buildCompressJob(L1): 페이지 선택 없이 공통 쓰기 옵션만', () {
      final job = buildCompressJob(sourcePath: 'in.pdf', outputPath: 'out.pdf');
      expect(job.containsKey('pages'), isFalse);
      expect(job['inputFile'], 'in.pdf');
      expect(job['objectStreams'], 'generate');
    });

    test('§5.3 금지 키가 5개 빌더 어느 출력에도 나타나지 않는다', () {
      final jobs = [
        buildSaveJob(sourcePath: 'a.pdf', outputPath: 'b.pdf', pageIndices: [0]),
        buildRotateJob(sourcePath: 'a.pdf', outputPath: 'b.pdf', pages: const [QpdfPageEntry(sourceIndex: 0, rotation: 90)]),
        buildMergeJob(sourcePdfPaths: ['a.pdf', 'b.pdf'], outputPath: 'c.pdf'),
        buildSplitJob(sourcePath: 'a.pdf', outputPath: 'b.pdf', pageIndices: [0]),
        buildCompressJob(sourcePath: 'a.pdf', outputPath: 'b.pdf'),
      ];
      const banned = ['replaceInput', 'splitPages', 'qdf', 'encrypt', 'linearize'];
      for (final job in jobs) {
        final encoded = jsonEncode(job);
        for (final key in banned) {
          expect(encoded.contains(key), isFalse, reason: '$key must not appear in $encoded');
        }
        // streamData는 아예 키를 넣지 않는다(기본값 유지) -- "uncompress" 값이 존재할 수 없다.
        expect(encoded.contains('uncompress'), isFalse);
      }
    });
  });

  group('qpdf FFI 잡 실행 (Windows qpdf30.dll 필요)', () {
    setUpAll(() {
      if (!_canRunFfi) {
        // ignore: avoid_print
        print('SKIP: Windows qpdf30.dll 또는 픽스처 없음 -- FFI 테스트 건너뜀 ($_dllPath / $_fixturePath)');
      }
    });

    test('픽스처 바이트 수(BO 원칙 baseline 확인, 원본 미수정 확인용)', () {
      final bytes = File(_fixturePath).readAsBytesSync();
      expect(bytes.length, _fixtureExpectedBytes);
    }, skip: !File(_fixturePath).existsSync() ? '픽스처 없음' : false);

    test('inspect: 원본 116페이지, 암호화 아님, 바이트 일치', () async {
      final result = await runInspect(pdfPath: _fixturePath, libraryPathOverride: _dllPath);
      expect(result['ok'], true);
      expect(result['pageCount'], 116);
      expect(result['isEncrypted'], false);
      expect(result['bytes'], _fixtureExpectedBytes);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('inspect: 존재하지 않는 파일 -> missing', () async {
      final result = await runInspect(
        pdfPath: p.join(Directory.current.path, 'test/fixtures/__no_such_file__.pdf'),
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], false);
      expect(result['error'], 'missing');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('R5 재현 1-A: idx100(0-based) 삭제, 배율이 스파이크(0.926)와 사실상 동일', () async {
      final tempDir = await Directory.systemTemp.createTemp('qpdf_isolate_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = p.join(tempDir.path, 'out_idx100.pdf');

      final indices = [for (var i = 0; i < 116; i++) i]..removeAt(100);
      final result = await runSaveJob(
        sourcePath: _fixturePath,
        outputPath: outputPath,
        pageIndices: indices,
        libraryPathOverride: _dllPath,
      );

      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect(result['pageCount'], 115);
      final ratio = (result['bytes'] as int) / _fixtureExpectedBytes;
      // 스파이크 실측 0.9260158496127435. 동일 옵션·동일 qpdf 버전이므로 결정적 재현을 기대하되,
      // 부동소수 표시나 타임스탬프성 메타데이터의 미세한 차이 가능성을 감안해 넉넉한 허용오차를 둔다.
      expect(ratio, closeTo(0.926, 0.01));
      expect(ratio, lessThan(1.0)); // size_guard deletePages 규칙(결과 <= 원본)

      // RO 원칙: 결과 파일을 재오픈해 페이지 수를 재확인한다.
      final reopened = await runInspect(pdfPath: outputPath, libraryPathOverride: _dllPath);
      expect(reopened['ok'], true);
      expect(reopened['pageCount'], 115);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));

    test('R5 재현 1-B: idx5(0-based) 삭제, 배율이 스파이크(0.9256)와 사실상 동일', () async {
      final tempDir = await Directory.systemTemp.createTemp('qpdf_isolate_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = p.join(tempDir.path, 'out_idx5.pdf');

      final indices = [for (var i = 0; i < 116; i++) i]..removeAt(5);
      final result = await runSaveJob(
        sourcePath: _fixturePath,
        outputPath: outputPath,
        pageIndices: indices,
        libraryPathOverride: _dllPath,
      );

      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect(result['pageCount'], 115);
      final ratio = (result['bytes'] as int) / _fixtureExpectedBytes;
      expect(ratio, closeTo(0.9256, 0.01));
      expect(ratio, lessThan(1.0));
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));

    test('R5 재현 merge: 원본 + 원본(바이트 동일 사본, 별개 경로), 232페이지, 배율이 스파이크(0.9147)와 사실상 동일', () async {
      final tempDir = await Directory.systemTemp.createTemp('qpdf_isolate_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = p.join(tempDir.path, 'out_merge.pdf');
      // 스파이크(§16 §2)와 동일하게 "물리적으로 다른 두 파일"을 합친다. 같은 경로를 두 번 넘기면
      // qpdf가 소스 파일을 경로 기준으로 캐시해 공유 리소스(폰트 등)를 중복 임베드하지 않고
      // 재사용한다 -- 실측(첫 시도, 배율 0.458)으로 확인된 사실이며, 실제 두 개의 다른 파일을
      // 합치는 시나리오를 대표하지 않으므로 바이트 동일 사본을 별도 경로에 만들어 사용한다.
      final copyPath = p.join(tempDir.path, 'copy_of_fixture.pdf');
      await File(_fixturePath).copy(copyPath);

      final result = await runMergeJob(
        sourcePdfPaths: [_fixturePath, copyPath],
        outputPath: outputPath,
        libraryPathOverride: _dllPath,
      );

      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect(result['pageCount'], 232);
      final baselineBytes = _fixtureExpectedBytes * 2;
      final ratio = (result['bytes'] as int) / baselineBytes;
      expect(ratio, closeTo(0.9147, 0.01));
      expect(ratio, lessThan(1.05)); // size_guard merge 규칙
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));

    test('rotate: 3페이지 발췌 + 회전 1개 -- 잡 성공, 페이지 수 유지(회전 자체의 시각적 검증은 '
        '_workspace/18 문서의 별도 CLI 실측 참고)', () async {
      final tempDir = await Directory.systemTemp.createTemp('qpdf_isolate_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = p.join(tempDir.path, 'out_rotate.pdf');

      final result = await runRotateJob(
        sourcePath: _fixturePath,
        outputPath: outputPath,
        pages: const [
          QpdfPageEntry(sourceIndex: 1, rotation: 0),
          QpdfPageEntry(sourceIndex: 0, rotation: 90),
          QpdfPageEntry(sourceIndex: 2, rotation: 0),
        ],
        libraryPathOverride: _dllPath,
      );

      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect(result['pageCount'], 3);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('cancel: 진입 직전 취소 -> Cancelled, 출력 파일 생성 안 됨', () async {
      final tempDir = await Directory.systemTemp.createTemp('qpdf_isolate_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = p.join(tempDir.path, 'out_cancelled.pdf');
      final token = CancelToken()..cancel();

      final result = await runSaveJob(
        sourcePath: _fixturePath,
        outputPath: outputPath,
        pageIndices: const [0, 1, 2],
        cancelToken: token,
        libraryPathOverride: _dllPath,
      );

      expect(result, {'ok': false, 'error': 'cancelled'});
      expect(File(outputPath).existsSync(), isFalse);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('progress: onProgress가 최소 1회 이상 호출된다(merge, 상대적으로 느린 잡)', () async {
      final tempDir = await Directory.systemTemp.createTemp('qpdf_isolate_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final outputPath = p.join(tempDir.path, 'out_progress.pdf');
      var callCount = 0;

      final result = await runMergeJob(
        sourcePdfPaths: [_fixturePath, _fixturePath],
        outputPath: outputPath,
        onProgress: (progress) => callCount++,
        libraryPathOverride: _dllPath,
      );

      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      // qpdf progress reporter는 잡 규모·내부 판단에 따라 호출 횟수가 달라질 수 있다 -- 0회가
      // 아님만 단언한다(콜백 자체가 배선돼 있는지가 검증 대상).
      expect(callCount, greaterThan(0));
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 2)));
  });
}
