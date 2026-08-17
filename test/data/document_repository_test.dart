import 'dart:io';

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

/// [Q-D 2026-08-18] 정리 책임 회귀 테스트용 스텁. `save()`가 항상 지정된
/// [PdfResult]를 반환한다. 실패를 흉내 낼 뿐, 파일 시스템에 아무것도 남기지
/// 않는다 — Q-D 확정대로 "엔진은 실패 시 자기 출력 파일만 지운다"를 그대로
/// 흉내내려면 아무 파일도 만들지 않는 쪽이 더 엄격한 재현이다: 그래도 여전히
/// `docs/<docId>.tmp`가 남아 있으면 안 되므로, 디렉터리 정리가 전적으로
/// Repository→Workspace 경로에서 일어나는지만 검증한다.
class _StubPdfEngine implements PdfEngine {
  _StubPdfEngine(this._result);

  final PdfResult<SaveOutcome> Function() _result;

  @override
  Future<PdfResult<SaveOutcome>> save({
    required List<PageRef> pages,
    required String outputPath,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final result = _result();
    if (result is PdfOk<SaveOutcome>) {
      // 성공 경로 테스트에서만 실제로 파일을 쓴다(commitStaging이 rename할 대상).
      await File(outputPath).writeAsBytes([1, 2, 3]);
    }
    return result;
  }

  @override
  Future<PdfResult<SaveOutcome>> merge({
    required List<String> sourcePdfPaths,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<SaveOutcome>> split({
    required String sourcePdfPath,
    required List<int> pageIndices,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<PdfDocInfo>> inspect(String pdfPath, {String? password}) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late AppWorkspace workspace;
  late AppDatabase db;
  late String sourcePdfPath;
  late String sourceImagePath;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_repo_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
    db = AppDatabase(NativeDatabase.memory());

    // createDocument가 복사할 원본 소스 더미 파일들 (스테이징 밖의 임의 위치).
    sourcePdfPath = p.join(tempRoot.path, 'external', 'original.pdf');
    await File(sourcePdfPath).create(recursive: true);
    await File(sourcePdfPath).writeAsBytes(List.filled(100, 0xAB));

    sourceImagePath = p.join(tempRoot.path, 'external', 'scan.jpg');
    await File(sourceImagePath).writeAsBytes(List.filled(50, 0xCD));
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  DriftDocumentRepository repoWith(PdfResult<SaveOutcome> Function() saveResult) {
    return DriftDocumentRepository(
      db: db,
      workspace: workspace,
      engine: _StubPdfEngine(saveResult),
    );
  }

  Future<void> expectNoResidue() async {
    // docs/ 아래에 어떤 항목도 남아 있으면 안 된다 (.tmp든 반쪽 docDir이든).
    final docsDir = Directory(p.join(tempRoot.path, 'docs'));
    final entries = await docsDir.list().toList();
    expect(entries, isEmpty, reason: 'docs/ 아래에 잔재가 남으면 안 된다: $entries');

    final rows = await db.select(db.documents).get();
    expect(rows, isEmpty, reason: 'DB에 반쪽 문서 행이 남으면 안 된다');
  }

  group('Q-D 회귀: PdfEngine 실패 시 rollbackStaging이 호출되어 잔재가 없다', () {
    test('GuardBlocked (SizeGuardViolation) — 소스 복사까지 성공한 뒤 엔진이 거부하는 경우', () async {
      final repo = repoWith(
        () => const PdfErr(
          SizeGuardViolation(
            GuardBlocked(resultBytes: 200, limitBytes: 100, op: SaveOp.deletePages),
          ),
        ),
      );

      final result = await repo.createDocument(
        title: '테스트 문서',
        origin: DocOrigin.imported,
        pages: [PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: 0, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 100),
      );

      expect(result, isA<PdfErr<DocumentSummary>>());
      final failure = (result as PdfErr<DocumentSummary>).failure;
      expect(failure, isA<SizeGuardViolation>());
      await expectNoResidue();
    });

    test('취소(Cancelled) 실패', () async {
      final repo = repoWith(() => const PdfErr(Cancelled()));

      final result = await repo.createDocument(
        title: '테스트 문서',
        origin: DocOrigin.scan,
        pages: [ImagePageRef(imagePath: sourceImagePath, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 50),
      );

      expect(result, isA<PdfErr<DocumentSummary>>());
      expect((result as PdfErr<DocumentSummary>).failure, isA<Cancelled>());
      await expectNoResidue();
    });

    test('일반 오류(UnknownFailure) 실패', () async {
      final repo = repoWith(() => const PdfErr(UnknownFailure('boom')));

      final result = await repo.createDocument(
        title: '테스트 문서',
        origin: DocOrigin.imported,
        pages: [PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: 0, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 100),
      );

      expect(result, isA<PdfErr<DocumentSummary>>());
      expect((result as PdfErr<DocumentSummary>).failure, isA<UnknownFailure>());
      await expectNoResidue();
    });

    test('소스 복사 단계 실패(원본 소스 없음)도 동일하게 잔재 없이 정리된다', () async {
      // 엔진까지 가지 않고 _copySourcesToStaging에서 SourceMissing으로 실패하는 경로.
      final repo = repoWith(
        () => throw StateError('엔진이 호출되면 안 된다 — 소스 복사 단계에서 이미 실패해야 한다'),
      );

      final result = await repo.createDocument(
        title: '테스트 문서',
        origin: DocOrigin.imported,
        pages: [
          PdfPageRef(
            sourcePath: p.join(tempRoot.path, 'external', 'does_not_exist.pdf'),
            sourceIndex: 0,
            rotation: 0,
          ),
        ],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 100),
      );

      expect(result, isA<PdfErr<DocumentSummary>>());
      expect((result as PdfErr<DocumentSummary>).failure, isA<SourceMissing>());
      await expectNoResidue();
    });
  });

  group('B6 회귀: 성공 시 소스가 스테이징으로 복사되어 커밋된다', () {
    test('PdfPageRef 소스가 docs/<docId>/sources/ 로 복사되고 DB가 그 경로를 가리킨다', () async {
      final repo = repoWith(
        () => const PdfOk(
          SaveOutcome(
            outputPath: '',
            bytes: 123,
            pageCount: 2,
            guard: GuardPass(resultBytes: 123, limitBytes: 999),
          ),
        ),
      );

      // 같은 원본 PDF에서 두 페이지를 뽑는다 — 소스는 한 번만 복사되어야 한다(dedupe).
      final result = await repo.createDocument(
        title: '병합 문서',
        origin: DocOrigin.imported,
        pages: [
          PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: 0, rotation: 0),
          PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: 1, rotation: 90),
        ],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.merge, baselineBytes: 100),
      );

      expect(result, isA<PdfOk<DocumentSummary>>());
      final docId = (result as PdfOk<DocumentSummary>).value.id;

      final copiedSource = File(workspace.sourcePdf(docId, 1));
      expect(await copiedSource.exists(), isTrue);
      expect(
        await File(workspace.sourcePdf(docId, 2)).exists(),
        isFalse,
        reason: '동일 원본은 한 번만 복사되어야 한다(dedupe)',
      );

      final detail = await repo.load(docId);
      expect(detail, isA<PdfOk<DocumentDetail>>());
      final pages = (detail as PdfOk<DocumentDetail>).value.pages;
      expect(pages, hasLength(2));
      for (final page in pages) {
        expect(page, isA<PdfPageRef>());
        final sourcePath = (page as PdfPageRef).sourcePath;
        expect(
          sourcePath,
          copiedSource.path,
          reason: 'DB의 source_path는 원본이 아니라 스테이징에 복사된 경로를 가리켜야 한다(재편집 가능성 보장)',
        );
      }
    });

    test('ImagePageRef 소스도 docs/<docId>/sources/pages/ 로 복사된다', () async {
      final repo = repoWith(
        () => const PdfOk(
          SaveOutcome(
            outputPath: '',
            bytes: 55,
            pageCount: 1,
            guard: GuardPass(resultBytes: 55, limitBytes: 999),
          ),
        ),
      );

      final result = await repo.createDocument(
        title: '스캔 문서',
        origin: DocOrigin.scan,
        pages: [ImagePageRef(imagePath: sourceImagePath, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 50),
      );

      expect(result, isA<PdfOk<DocumentSummary>>());
      final docId = (result as PdfOk<DocumentSummary>).value.id;
      expect(await File(workspace.sourceImage(docId, 1)).exists(), isTrue);
    });
  });
}
