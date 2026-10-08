/// [47_platform-integration] `_workspace/46_build-runner_split_merge_crash_logs.md`가 실기기에서
/// 재현한 "SaveOp.split이 GuardBlocked로 실패한 직후 SaveOp.merge를 호출하면 응답 없이 멈춘다"
/// 현상을 호스트에서 재현하기 위한 테스트다.
///
/// 가설(§47 지시): `DriftDocumentRepository.createDocument`의 실패 경로(게이트 차단)에서
/// DB 트랜잭션·동시성 잠금이 풀리지 않아 다음 호출이 무한 대기한다.
///
/// `QpdfPdfEngine`을 스텁으로 교체해 실제 FFI/isolate 없이 순수하게 Repository/Workspace/Drift
/// 계층만 검증한다 — 이 스텁은 실기기 시나리오와 동일한 형태로 첫 호출(split 역할)에서
/// `PdfErr(SizeGuardViolation(GuardBlocked(...)))`를 반환하고, 곧이은 두 번째 호출(merge 역할)에서
/// `PdfOk(SaveOutcome(...))`를 반환한다. **같은 `DriftDocumentRepository` 인스턴스**로 두 호출을
/// 순차 실행한다(실기기 재현과 동일 조건 — 별개 인스턴스면 인스턴스 소유 상태(예: 썸네일 캐시)가
/// 격리되어 재현이 무의미해진다).
///
/// 검증 핵심: 이 테스트가 **타임아웃 없이 완료되는지**. 무한 대기가 실제로 존재한다면
/// `expectLater(..., completes)` + 짧은 `timeout`으로 테스트 자체가 명확히 실패한다.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/db/app_database.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';

/// 실기기 시나리오를 그대로 흉내내는 스텁: 첫 `save()` 호출은 GuardBlocked, 두 번째 호출부터는
/// 성공을 돌려준다. 실제 `QpdfPdfEngine`이 하는 파일 쓰기(성공 시 outputPath에 결과 파일을 남기는
/// 동작)만 흉내내고 FFI/isolate는 전혀 쓰지 않는다.
class _SplitThenMergeStubEngine implements PdfEngine {
  int _callCount = 0;

  @override
  Future<PdfResult<SaveOutcome>> save({
    required List<PageRef> pages,
    required String outputPath,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _callCount++;
    if (_callCount == 1) {
      // 1번째 호출("split" 역할): 게이트 차단으로 실패. 실제 QpdfPdfEngine처럼 출력 파일을
      // 만들지 않는다(§46 로그의 split=PdfErr<DocumentSummary> 재현).
      return const PdfErr(
        SizeGuardViolation(
          GuardBlocked(resultBytes: 200, limitBytes: 100, op: SaveOp.split),
        ),
      );
    }
    // 2번째 호출("merge" 역할): 성공. commitStaging이 rename할 대상 파일을 실제로 쓴다.
    await File(outputPath).writeAsBytes([1, 2, 3]);
    return const PdfOk(
      SaveOutcome(
        outputPath: '',
        bytes: 3,
        pageCount: 2,
        guard: GuardPass(resultBytes: 3, limitBytes: 999),
      ),
    );
  }

  @override
  Future<PdfResult<SaveOutcome>> merge({
    required List<String> sourcePdfPaths,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError('createDocument는 engine.merge()를 호출하지 않는다(§ pdf_engine.dart)');

  @override
  Future<PdfResult<SaveOutcome>> split({
    required String sourcePdfPath,
    required List<int> pageIndices,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError('createDocument는 engine.split()를 호출하지 않는다(§ pdf_engine.dart)');

  @override
  Future<PdfResult<PdfDocInfo>> inspect(String pdfPath, {String? password}) =>
      throw UnimplementedError();

  @override
  Future<PdfResult<SaveOutcome>> stamp({
    required String sourcePdfPath,
    required Uint8List stampPdfBytes,
    required int pageCount,
    required String outputPath,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

class _StubPdfRenderer implements PdfRenderer {
  @override
  Future<PdfResult<int>> openPageCount(String pdfPath, {String? password}) =>
      throw UnimplementedError();
  @override
  Future<PdfResult<PdfPageTextData>> pageText({
    required String pdfPath,
    required int pageIndex,
    String? password,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
  @override
  Future<PdfResult<Uint8List>> renderPage({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
  @override
  Future<PdfResult<Uint8List>> renderThumbnail({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
  }) => throw UnimplementedError();
  @override
  Future<PdfResult<Uint8List>> renderPageThumbnail({
    required PageRef page,
    required int targetWidthPx,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
  @override
  void evictCache() => throw UnimplementedError();
  @override
  Future<PdfResult<PdfPageGeometry>> pageGeometry(String pdfPath, {String? password}) =>
      throw UnimplementedError();
  @override
  void evictDocument(String pdfPath, {String? password}) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '§47 재현: split(GuardBlocked) 직후 같은 Repository 인스턴스로 merge를 호출해도 멈추지 않는다',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_hang_repro_');
      addTearDown(() async {
        if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
      });

      final workspace = AppWorkspace(tempRoot.path);
      await workspace.ensureLayout();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      final sourcePdfPath = p.join(tempRoot.path, 'external', 'original.pdf');
      await File(sourcePdfPath).create(recursive: true);
      await File(sourcePdfPath).writeAsBytes(List.filled(100, 0xAB));

      // §46 로그와 동일 조건 재현 필수 요소: 같은 인스턴스.
      final repo = DriftDocumentRepository(
        db: db,
        workspace: workspace,
        engine: _SplitThenMergeStubEngine(),
        renderer: _StubPdfRenderer(),
      );

      // 1번째 호출 — "split" 역할, GuardBlocked로 실패해야 한다(§46 로그와 일치).
      final splitResult = await repo.createDocument(
        title: 'T7-split',
        origin: DocOrigin.imported,
        pages: [PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: 0, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(
          op: SaveOp.split,
          baselineBytes: 100,
          totalPages: 116,
          selectedPages: 4,
        ),
      );
      expect(splitResult, isA<PdfErr<DocumentSummary>>(), reason: '스텁이 1번째 호출에서 실패를 반환해야 한다');
      expect((splitResult as PdfErr<DocumentSummary>).failure, isA<SizeGuardViolation>());

      // 2번째 호출 — "merge" 역할. 여기서 무한 대기가 있다면 아래 completes 매처가
      // 지정된 시간(10초) 안에 완료되지 않아 테스트가 명확히 실패한다(타임아웃 없는 그냥
      // await라면 CI 자체가 무한정 멈춰버려 실패 신호조차 못 준다 — 그래서 completes+timeout 사용).
      final mergeFuture = repo.createDocument(
        title: 'T7-merge',
        origin: DocOrigin.imported,
        pages: [PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: 0, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.merge, baselineBytes: 200),
      );

      await expectLater(mergeFuture, completes);

      final mergeResult = await mergeFuture;
      expect(mergeResult, isA<PdfOk<DocumentSummary>>(), reason: '스텁이 2번째 호출에서 성공을 반환해야 한다');
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
