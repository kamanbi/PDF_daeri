// [47_platform-integration] `_workspace/46_build-runner_split_merge_crash_logs.md`가 실기기에서
// 재현한 "split(GuardBlocked) 직후 merge를 실행하면 응답 없이 멈춘다" 현상의 재현 시도.
//
// `test/pdf/qpdf_split_then_merge_crash_repro_test.dart`(pdf-core 작성)는 `QpdfPdfEngine.split()`
// → `QpdfPdfEngine.merge()`를 **직접** 호출해 재현을 시도했고 성공적으로 살아남았다(호스트 재현 실패,
// crash 아님으로 결론). 그런데 `DriftDocumentRepository.createDocument`는 `split()`/`merge()`를
// 전혀 호출하지 않는다 — 항상 `PdfEngine.save()`만 호출한다(`lib/data/repository/document_repository.dart`
// 참조). `QpdfPdfEngine.save()` 내부에서:
//   - 페이지가 전부 동일 소스 PdfPageRef면 `runRotateJob`(inputFile 경로, buildRotateJob)을 탄다.
//   - 페이지가 복수 소스에 걸치면(§46 로그의 merge 시나리오, 서로 다른 두 문서를 합침) `_saveCompose`
//     → `runComposeJob`(--empty + range 세그먼트, buildComposeJob)을 탄다.
// 즉 실기기 로그가 재현한 것은 "rotate 잡이 게이트에 막힌 직후 compose 잡을 실행"이지,
// "split 잡 직후 merge 잡"이 아니다. 이 파일은 Repository가 실제로 밟는 잡 종류 조합(rotate → compose)을
// `QpdfPdfEngine.save()` 직접 호출로 재현한다 — Repository/DB 계층 없이 순수 엔진 경계만 검증한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';

const _fixtureRelPath = 'test/fixtures/(서일)-클라우디움 사용자 매뉴얼(윈도우탐색기)_20180821.pdf';
const _dllRelPath = 'test/native/qpdf30.dll';

String get _fixturePath => p.join(Directory.current.path, _fixtureRelPath);
String get _dllPath => p.join(Directory.current.path, _dllRelPath);

bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync() && File(_fixturePath).existsSync();

void main() {
  test(
    'save(rotate-job, GuardBlocked) 직후 save(compose-job, 다중 소스) -- 프로세스 생존 + 응답 확인',
    () async {
      final root = Directory.systemTemp.createTempSync('pdf_daeri_rotate_compose_repro_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _dllPath);

      // 1) "split" 역할이지만 Repository가 실제로 호출하는 것은 save()다 -- 단일 소스,
      //    페이지 몇 장만 선택(week3_device_verification_test.dart의 split 테스트와 동일 형태:
      //    116p 중 4p 발췌, 동일 소스 -> hasImages=false && pdfSources.length==1 -> runRotateJob).
      final splitOut = Directory('${root.path}/docs/split1.tmp')..createSync(recursive: true);
      final splitOutputPath = '${splitOut.path}/document.pdf';
      final splitPages = [
        for (final i in const [0, 10, 55, 90]) PdfPageRef(sourcePath: _fixturePath, sourceIndex: i, rotation: 0),
      ];

      final splitResult = await engine.save(
        pages: splitPages,
        outputPath: splitOutputPath,
        quality: ImageQuality.standard,
        // baseline을 원본 파일 크기로 주되 totalPages/selectedPages 비율로 limit이 작게 나오도록
        // GuardInput.op=split을 쓴다(§46 로그와 동일 조건). 원본 크기를 baseline으로 쓴다.
        guardInput: GuardInput(
          op: SaveOp.split,
          baselineBytes: File(_fixturePath).lengthSync(),
          totalPages: 116,
          selectedPages: 4,
        ),
      );

      expect(splitResult, isA<PdfErr<SaveOutcome>>(), reason: 'save(rotate-job)이 게이트를 통과해버림 -- 재현 전제가 깨짐: $splitResult');
      expect(
        (splitResult as PdfErr<SaveOutcome>).failure,
        isA<SizeGuardViolation>(),
        reason: 'split 실패 사유가 SizeGuardViolation이 아님(재현 전제 불일치): ${splitResult.failure}',
      );

      // 2) "merge" 역할 -- 서로 다른 두 소스(같은 파일을 두 소스인 것처럼 각기 다른 경로로 위장할
      //    수는 없으니, 실제 Repository 시나리오처럼 sourcePath가 다른 두 PdfPageRef를 만들기 위해
      //    같은 픽스처를 두 개의 물리적으로 다른 경로에 복사해 서로 다른 소스로 만든다(§46 로그의
      //    baseDoc/baseDoc2가 서로 다른 sources/src_1.pdf 경로였던 것과 동일 조건).
      final copyA = p.join(root.path, 'copyA.pdf');
      final copyB = p.join(root.path, 'copyB.pdf');
      await File(_fixturePath).copy(copyA);
      await File(_fixturePath).copy(copyB);

      final mergeOut = Directory('${root.path}/docs/merge1.tmp')..createSync(recursive: true);
      final mergeOutputPath = '${mergeOut.path}/document.pdf';
      final mergePages = [
        for (var i = 0; i < 20; i++) PdfPageRef(sourcePath: copyA, sourceIndex: i, rotation: 0),
        for (var i = 0; i < 20; i++) PdfPageRef(sourcePath: copyB, sourceIndex: i, rotation: 0),
      ];

      final mergeFuture = engine.save(
        pages: mergePages,
        outputPath: mergeOutputPath,
        quality: ImageQuality.standard,
        guardInput: GuardInput(
          op: SaveOp.merge,
          baselineBytes: File(copyA).lengthSync() + File(copyB).lengthSync(),
        ),
      );

      // 무한 대기라면 여기서 타임아웃으로 명확히 실패한다(그냥 await면 테스트 러너 자체가 멈춘다).
      await expectLater(mergeFuture, completes);
      final mergeResult = await mergeFuture;
      expect(mergeResult, isA<PdfOk<SaveOutcome>>(), reason: 'merge(compose-job) 실패: $mergeResult');
    },
    skip: !_canRunFfi ? 'Windows qpdf30.dll + 픽스처 필요' : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
