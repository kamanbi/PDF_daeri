// 호스트 재현 시도 -- `_workspace/44_build-runner_week3_device.md` 실기기 크래시("split이
// SizeGuardViolation으로 막힌 직후 merge를 실행하면 앱 프로세스가 죽는다")를 Windows
// `test/native/qpdf30.dll`로 같은 순서(같은 프로세스, 같은 QpdfPdfEngine 인스턴스)로 재현한다.
//
// `pdf-core.md` 진단 절차 1번: 호스트 재현 시도. `_workspace/45_pdf-core_split_merge_crash.md`에
// 결과를 기록한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';

const _fixtureRelPath = 'test/fixtures/(서일)-클라우디움 사용자 매뉴얼(윈도우탐색기)_20180821.pdf';
const _dllRelPath = 'test/native/qpdf30.dll';

String get _fixturePath => p.join(Directory.current.path, _fixtureRelPath);
String get _dllPath => p.join(Directory.current.path, _dllRelPath);

bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync() && File(_fixturePath).existsSync();

void main() {
  test(
    'split(GuardBlocked) 직후 merge -- 앱(테스트 프로세스) 생존 확인',
    () async {
      final root = Directory.systemTemp.createTempSync('pdf_daeri_crash_repro_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      final engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _dllPath);

      // 1) split -- baseline을 의도적으로 작게 줘서 SizeGuardViolation으로 막히게 한다.
      //    116p 픽스처 중 4페이지(0,10,55,90) 발췌. limit = baseline*(4/116)*1.2.
      //    baseline을 1바이트로 주면 limit이 0에 가까워 결과가 반드시 초과한다.
      final splitOut = Directory('${root.path}/docs/split1.tmp')..createSync(recursive: true);
      final splitOutputPath = '${splitOut.path}/document.pdf';

      // GuardInput.baselineBytes는 split() 내부에서 실제 inspect() 결과(info.bytes)로 재계산되므로
      // 여기서는 개입할 수 없다 -- 대신 pageIndices를 원본 페이지수 대비 극히 일부만 선택해
      // splitRatio(1.2)를 곱해도 실제 qpdf 출력(구조 오버헤드 포함)이 넘도록 유도한다.
      // 116p 중 1페이지만 선택 -> limit = baseline*(1/116)*1.2 ≈ baseline*0.0103.
      // qpdf 출력은 폰트/리소스가 포함된 페이지라 원본의 1%보다 훨씬 크므로 반드시 Blocked.
      final splitResult = await engine.split(
        sourcePdfPath: _fixturePath,
        pageIndices: const [0],
        outputPath: splitOutputPath,
      );

      expect(splitResult, isA<PdfErr<SaveOutcome>>(), reason: 'split이 게이트를 통과해버림 -- 재현 전제가 깨짐: $splitResult');
      final splitFailure = (splitResult as PdfErr<SaveOutcome>).failure;
      expect(
        splitFailure,
        isA<SizeGuardViolation>(),
        reason: 'split 실패 사유가 SizeGuardViolation이 아님(재현 전제 불일치): $splitFailure',
      );

      // 2) 곧바로(같은 isolate 생명주기, 같은 engine 인스턴스) merge 실행.
      final mergeOut = Directory('${root.path}/docs/merge1.tmp')..createSync(recursive: true);
      final mergeOutputPath = '${mergeOut.path}/document.pdf';

      final mergeResult = await engine.merge(
        sourcePdfPaths: [_fixturePath, _fixturePath],
        outputPath: mergeOutputPath,
      );

      // 실기기 증상은 "결과가 무엇이든" 이 지점까지 프로세스가 살아있느냐다.
      // 여기 도달했다는 것 자체가 이미 크래시가 아니라는 증거(크래시면 이 테스트 프로세스가 죽는다).
      expect(mergeResult, isA<PdfOk<SaveOutcome>>(), reason: 'merge 실패: $mergeResult');
    },
    skip: !_canRunFfi ? 'Windows qpdf30.dll + 픽스처 필요' : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'split(GuardBlocked) 직후 merge -- 15회 반복(누적 누수형 크래시 탐지)',
    () async {
      final root = Directory.systemTemp.createTempSync('pdf_daeri_crash_repro_loop_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _dllPath);

      for (var i = 0; i < 15; i++) {
        final splitOut = Directory('${root.path}/docs/loopsplit$i.tmp')..createSync(recursive: true);
        final splitResult = await engine.split(
          sourcePdfPath: _fixturePath,
          pageIndices: const [0],
          outputPath: '${splitOut.path}/document.pdf',
        );
        expect(splitResult, isA<PdfErr<SaveOutcome>>(), reason: '[iter $i] split이 게이트를 통과함');

        final mergeOut = Directory('${root.path}/docs/loopmerge$i.tmp')..createSync(recursive: true);
        final mergeResult = await engine.merge(
          sourcePdfPaths: [_fixturePath, _fixturePath],
          outputPath: '${mergeOut.path}/document.pdf',
        );
        expect(mergeResult, isA<PdfOk<SaveOutcome>>(), reason: '[iter $i] merge 실패: $mergeResult');
      }
    },
    skip: !_canRunFfi ? 'Windows qpdf30.dll + 픽스처 필요' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
