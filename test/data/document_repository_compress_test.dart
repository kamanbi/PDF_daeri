/// `DocumentRepository.compressToNewDocument` 회귀 테스트(M-E7,
/// `_workspace/31_architect_external_compress_l2.md` §2/§3.2/§4.5).
///
/// `PdfCompressor`는 페이크로 대체한다 — 이 파일의 관심사는 qpdf FFI 실행이 아니라
/// **Repository 층의 계약**(여유 공간 확인 → 스테이징 → 커밋/DB 기록, 실패·취소 시
/// 잔재 없음, L2-app/L2-ext 분기, 제목 규칙 `(압축)`)이다. FFI 실행 자체는
/// `test/pdf/pdf_compressor_test.dart`가 이미 검증한다.
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
import 'package:pdf_daeri/pdf/pdf_compressor.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';

/// `createDocument` 경로에서만 쓰인다(내 문서 픽스처를 만들 때). 실제로 스테이징
/// 경로에 파일을 써야 커밋이 성립한다(`document_repository_thumbnail_test.dart`와 동일).
class _StubPdfEngine implements PdfEngine {
  @override
  Future<PdfResult<SaveOutcome>> save({
    required List<PageRef> pages,
    required String outputPath,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await File(outputPath).writeAsBytes(List.filled(20, 0x22));
    return PdfOk(
      SaveOutcome(
        outputPath: '',
        bytes: 20,
        pageCount: pages.length,
        guard: const GuardPass(resultBytes: 20, limitBytes: 999),
      ),
    );
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

/// `openPageCount`만 고정값을 돌려주는 스텁. `compressToNewDocument`가 압축 결과
/// 페이지 수를 알아내는 유일한 경로다 — 저장 경로에 렌더러가 끼면 안 되므로 다른
/// 메서드는 호출되면 실패하게 둔다(§7.1과 같은 취지).
class _FixedPageCountRenderer implements PdfRenderer {
  _FixedPageCountRenderer(this.pageCount, {this.fail = false});
  final int pageCount;
  final bool fail;

  @override
  Future<PdfResult<int>> openPageCount(String pdfPath, {String? password}) async =>
      fail ? const PdfErr(SourceCorrupted('fake')) : PdfOk(pageCount);

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

/// 압축 결과를 미리 정한 대로 흉내 내는 페이크. 성공(`keptOriginal=false`)이면
/// [outputPath]에 실제로 바이트를 써서 이후 `File.copy`(sources/src_1.pdf 복제)와
/// `openPageCount` 호출이 실제 파일을 대상으로 성립하게 한다.
class _FakePdfCompressor implements PdfCompressor {
  _FakePdfCompressor(this._result, {this.cancelDuringCompress = false});

  final PdfResult<CompressOutcome> Function() _result;
  final bool cancelDuringCompress;

  String? capturedPdfPath;
  String? capturedOutputPath;
  List<String>? capturedImagePagePaths;
  String? capturedEmbeddedImageStagingDir;
  int callCount = 0;

  @override
  Future<PdfResult<CompressTarget>> analyze(String pdfPath, {required List<String> pageKinds}) =>
      throw UnimplementedError('compressToNewDocument는 analyze()를 호출하지 않는다(§4.1)');

  @override
  Future<PdfResult<CompressOutcome>> compress({
    required String pdfPath,
    required String outputPath,
    required ImageQuality preset,
    List<String>? imagePagePaths,
    String? embeddedImageStagingDir,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    capturedPdfPath = pdfPath;
    capturedOutputPath = outputPath;
    capturedImagePagePaths = imagePagePaths;
    capturedEmbeddedImageStagingDir = embeddedImageStagingDir;

    if (cancelDuringCompress) {
      cancelToken?.cancel();
    }

    final result = _result();
    if (result is PdfOk<CompressOutcome> && !result.value.keptOriginal) {
      await File(outputPath).writeAsBytes(List.filled(10, 0x33));
    }
    return result;
  }
}

/// `freeSpaceBytes()`만 고정값으로 바꾸는 얇은 위임 데코레이터(document_repository_test.dart의
/// `_FixedFreeSpaceWorkspace`와 같은 패턴 — private라 재사용할 수 없어 이 파일에도 둔다).
class _FixedFreeSpaceWorkspace implements Workspace {
  _FixedFreeSpaceWorkspace(this._inner, this._freeBytes);

  final Workspace _inner;
  final int _freeBytes;

  @override
  Future<int> freeSpaceBytes() async => _freeBytes;

  @override
  Future<void> ensureLayout() => _inner.ensureLayout();
  @override
  String docDir(String docId) => _inner.docDir(docId);
  @override
  String docPdf(String docId) => _inner.docPdf(docId);
  @override
  String sourcesDir(String docId) => _inner.sourcesDir(docId);
  @override
  String sourcePdf(String docId, int n) => _inner.sourcePdf(docId, n);
  @override
  String sourceImage(String docId, int n) => _inner.sourceImage(docId, n);
  @override
  String stagingDocPdf(String docId) => _inner.stagingDocPdf(docId);
  @override
  String stagingSourcePdf(String docId, int n) => _inner.stagingSourcePdf(docId, n);
  @override
  String stagingSourceImage(String docId, int n) => _inner.stagingSourceImage(docId, n);
  @override
  String stagingCompressImagesDir(String docId) => _inner.stagingCompressImagesDir(docId);
  @override
  String thumb(String docId) => _inner.thumb(docId);
  @override
  String recentFile(String id) => _inner.recentFile(id);
  @override
  String cacheFile(String key) => _inner.cacheFile(key);
  @override
  Future<String> beginStaging(String docId) => _inner.beginStaging(docId);
  @override
  Future<void> commitStaging(String docId) => _inner.commitStaging(docId);
  @override
  Future<void> rollbackStaging(String docId) => _inner.rollbackStaging(docId);
  @override
  Future<void> clearCache() => _inner.clearCache();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late AppWorkspace workspace;
  late AppDatabase db;
  late String externalPdfPath;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_compress_repo_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
    db = AppDatabase(NativeDatabase.memory());

    externalPdfPath = p.join(tempRoot.path, 'external', 'recent_import.pdf');
    await File(externalPdfPath).create(recursive: true);
    await File(externalPdfPath).writeAsBytes(List.filled(1000, 0xEE));
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  DriftDocumentRepository repoWith({
    required PdfCompressor compressor,
    Workspace? workspaceOverride,
    int fixedPageCount = 3,
    bool pageCountFails = false,
  }) {
    return DriftDocumentRepository(
      db: db,
      workspace: workspaceOverride ?? workspace,
      engine: _StubPdfEngine(),
      renderer: _FixedPageCountRenderer(fixedPageCount, fail: pageCountFails),
      compressor: compressor,
    );
  }

  Future<void> expectNoResidue() async {
    final docsDir = Directory(p.join(tempRoot.path, 'docs'));
    final entries = await docsDir.list().toList();
    expect(entries, isEmpty, reason: 'docs/ 아래에 잔재가 남으면 안 된다: $entries');
    final rows = await db.select(db.documents).get();
    expect(rows, isEmpty, reason: 'DB에 반쪽 문서 행이 남으면 안 된다');
  }

  group('여유 공간 확인(R3: 원본의 약 1.2배)', () {
    test('freeSpaceBytes()가 필요량보다 작으면 OutOfSpace 반환, 스테이징이 시작되지 않는다', () async {
      final originalBytes = await File(externalPdfPath).length();
      final requiredBytes = (originalBytes * 1.2).ceil() + Workspace.spaceSafetyBufferBytes;
      final tinyFreeSpace = _FixedFreeSpaceWorkspace(workspace, requiredBytes - 1);

      final compressor = _FakePdfCompressor(
        () => throw StateError('여유 공간 확인은 압축 호출보다 앞서야 한다'),
      );
      final repo = repoWith(compressor: compressor, workspaceOverride: tinyFreeSpace);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfErr<CompressToNewDocumentResult>>());
      final failure = (result as PdfErr<CompressToNewDocumentResult>).failure;
      expect(failure, isA<OutOfSpace>());
      expect((failure as OutOfSpace).requiredBytes, requiredBytes);
      expect(compressor.callCount, 0, reason: 'beginStaging보다도 앞서 막혀야 한다');

      final docsDir = Directory(p.join(tempRoot.path, 'docs'));
      expect(await docsDir.list().toList(), isEmpty);
    });

    test('freeSpaceBytes()가 -1(판단 불가)이면 막지 않는다(양성 대조)', () async {
      final unknownSpace = _FixedFreeSpaceWorkspace(workspace, -1);
      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 400, keptOriginal: false)),
      );
      final repo = repoWith(compressor: compressor, workspaceOverride: unknownSpace);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfOk<CompressToNewDocumentResult>>());
    });
  });

  group('실패·취소 시 스테이징 잔재 없음', () {
    test('PdfCompressor.compress()가 실패하면 rollbackStaging으로 잔재가 없다', () async {
      final compressor = _FakePdfCompressor(() => const PdfErr(UnknownFailure('boom')));
      final repo = repoWith(compressor: compressor);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfErr<CompressToNewDocumentResult>>());
      expect((result as PdfErr<CompressToNewDocumentResult>).failure, isA<UnknownFailure>());
      await expectNoResidue();
    });

    test('PdfCompressor.compress()가 Cancelled를 반환하면 잔재가 없다', () async {
      final compressor = _FakePdfCompressor(() => const PdfErr(Cancelled()));
      final repo = repoWith(compressor: compressor);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfErr<CompressToNewDocumentResult>>());
      expect((result as PdfErr<CompressToNewDocumentResult>).failure, isA<Cancelled>());
      await expectNoResidue();
    });

    test('압축 성공 직후 취소되면 커밋 전에 롤백되어 잔재가 없다', () async {
      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 400, keptOriginal: false)),
        cancelDuringCompress: true,
      );
      final repo = repoWith(compressor: compressor);
      final cancelToken = CancelToken();

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
        cancelToken: cancelToken,
      );

      expect(result, isA<PdfErr<CompressToNewDocumentResult>>());
      expect((result as PdfErr<CompressToNewDocumentResult>).failure, isA<Cancelled>());
      await expectNoResidue();
    });

    test('원본 파일이 없으면 SourceMissing, 스테이징이 시작되지 않는다', () async {
      final compressor = _FakePdfCompressor(
        () => throw StateError('원본이 없으면 compress()가 호출되면 안 된다'),
      );
      final repo = repoWith(compressor: compressor);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(
          pdfPath: p.join(tempRoot.path, 'external', 'does_not_exist.pdf'),
          title: '없는 문서',
        ),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfErr<CompressToNewDocumentResult>>());
      expect((result as PdfErr<CompressToNewDocumentResult>).failure, isA<SourceMissing>());
      await expectNoResidue();
    });

    test('압축 성공 후 페이지 수 조회(openPageCount) 실패도 잔재 없이 정리된다', () async {
      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 400, keptOriginal: false)),
      );
      final repo = repoWith(compressor: compressor, pageCountFails: true);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfErr<CompressToNewDocumentResult>>());
      expect((result as PdfErr<CompressToNewDocumentResult>).failure, isA<SourceCorrupted>());
      await expectNoResidue();
    });
  });

  group('keptOriginal — 압축 효과 없으면 새 문서를 만들지 않는다(§4.3 상태3)', () {
    test('keptOriginal=true면 summary가 null이고 docs/에 아무것도 남지 않는다', () async {
      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 1000, keptOriginal: true)),
      );
      final repo = repoWith(compressor: compressor);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfOk<CompressToNewDocumentResult>>());
      final value = (result as PdfOk<CompressToNewDocumentResult>).value;
      expect(value.keptOriginal, isTrue);
      expect(value.summary, isNull);
      await expectNoResidue();
    });
  });

  group('L2-app/L2-ext 분기 — 압축 대상 판별', () {
    test('외부 PDF(CompressSource.externalPdf)는 항상 embeddedImageStagingDir(L2-ext)로 호출된다', () async {
      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 400, keptOriginal: false)),
      );
      final repo = repoWith(compressor: compressor, fixedPageCount: 1);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '외부 문서'),
        preset: ImageQuality.min,
      );

      expect(result, isA<PdfOk<CompressToNewDocumentResult>>());
      expect(compressor.capturedImagePagePaths, isNull);
      expect(compressor.capturedEmbeddedImageStagingDir, isNotNull);
      expect(compressor.capturedPdfPath, externalPdfPath, reason: '원본을 읽기 전용으로 그대로 넘겨야 한다');
    });

    test('내 문서(전량 ImagePageRef)는 imagePagePaths(L2-app)로 호출된다', () async {
      // 픽스처: ImagePageRef 페이지 2장짜리 "내 문서"를 먼저 만든다.
      final img1 = p.join(tempRoot.path, 'external', 'p1.jpg');
      final img2 = p.join(tempRoot.path, 'external', 'p2.jpg');
      await File(img1).create(recursive: true);
      await File(img1).writeAsBytes([1]);
      await File(img2).writeAsBytes([2]);

      final createRepo = DriftDocumentRepository(
        db: db,
        workspace: workspace,
        engine: _StubPdfEngine(),
        renderer: _FixedPageCountRenderer(2),
      );
      final createResult = await createRepo.createDocument(
        title: '내 스캔 문서',
        origin: DocOrigin.scan,
        pages: [ImagePageRef(imagePath: img1, rotation: 0), ImagePageRef(imagePath: img2, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 50),
      );
      expect(createResult, isA<PdfOk<DocumentSummary>>());
      final myDocId = (createResult as PdfOk<DocumentSummary>).value.id;

      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 400, keptOriginal: false)),
      );
      final repo = repoWith(compressor: compressor, fixedPageCount: 2);

      final result = await repo.compressToNewDocument(
        source: CompressSource.myDocument(myDocId),
        preset: ImageQuality.high,
      );

      expect(result, isA<PdfOk<CompressToNewDocumentResult>>());
      expect(compressor.capturedImagePagePaths, hasLength(2), reason: '전량 이미지 문서는 L2-app으로 호출돼야 한다');
      expect(compressor.capturedEmbeddedImageStagingDir, isNull);
      expect(compressor.capturedPdfPath, workspace.docPdf(myDocId));
    });

    test('내 문서(혼합/PDF 페이지 포함)는 embeddedImageStagingDir(L2-ext)로 호출된다', () async {
      final srcPdf = p.join(tempRoot.path, 'external', 'src.pdf');
      await File(srcPdf).create(recursive: true);
      await File(srcPdf).writeAsBytes(List.filled(30, 0x9));

      final createRepo = DriftDocumentRepository(
        db: db,
        workspace: workspace,
        engine: _StubPdfEngine(),
        renderer: _FixedPageCountRenderer(1),
      );
      final createResult = await createRepo.createDocument(
        title: '가져온 문서',
        origin: DocOrigin.imported,
        pages: [PdfPageRef(sourcePath: srcPdf, sourceIndex: 0, rotation: 0)],
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.deletePages, baselineBytes: 30),
      );
      expect(createResult, isA<PdfOk<DocumentSummary>>());
      final myDocId = (createResult as PdfOk<DocumentSummary>).value.id;

      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 400, keptOriginal: false)),
      );
      final repo = repoWith(compressor: compressor, fixedPageCount: 1);

      final result = await repo.compressToNewDocument(
        source: CompressSource.myDocument(myDocId),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfOk<CompressToNewDocumentResult>>());
      expect(compressor.capturedImagePagePaths, isNull);
      expect(compressor.capturedEmbeddedImageStagingDir, isNotNull, reason: 'PdfPageRef가 섞이면 L2-app을 쓸 수 없다(§6.1 Q15)');
    });
  });

  group('성공 시 새 문서가 커밋되고 제목·소스·pages 행이 규칙대로 만들어진다', () {
    test('제목은 <원본 제목> (압축)이고, docId는 새 UUID이며 원본은 수정되지 않는다', () async {
      final originalBytesBefore = await File(externalPdfPath).readAsBytes();
      final compressor = _FakePdfCompressor(
        () => const PdfOk(CompressOutcome(originalBytes: 1000, resultBytes: 250, keptOriginal: false)),
      );
      final repo = repoWith(compressor: compressor, fixedPageCount: 5);

      final result = await repo.compressToNewDocument(
        source: CompressSource.externalPdf(pdfPath: externalPdfPath, title: '보고서'),
        preset: ImageQuality.standard,
      );

      expect(result, isA<PdfOk<CompressToNewDocumentResult>>());
      final value = (result as PdfOk<CompressToNewDocumentResult>).value;
      expect(value.keptOriginal, isFalse);
      final summary = value.summary!;
      expect(summary.title, '보고서 (압축)');
      expect(summary.pageCount, 5);
      expect(summary.fileSize, 250);

      // 원본 미수정(절대 규칙 6).
      expect(await File(externalPdfPath).readAsBytes(), originalBytesBefore);

      // 새 문서 파일이 실제로 존재한다.
      expect(await File(workspace.docPdf(summary.id)).exists(), isTrue);
      expect(await File(workspace.sourcePdf(summary.id, 1)).exists(), isTrue, reason: '재편집 가능성 보장을 위해 sources/에도 남아야 한다');

      // pages 행이 pageCount만큼 PdfPageRef(sources/src_1.pdf, sourceIndex 0..N-1)로 생성된다.
      final detail = await repo.load(summary.id);
      final pages = (detail as PdfOk<DocumentDetail>).value.pages;
      expect(pages, hasLength(5));
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i] as PdfPageRef;
        expect(page.sourcePath, workspace.sourcePdf(summary.id, 1));
        expect(page.sourceIndex, i);
      }

      // L2-ext 임시 스테이징 폴더는 최종 docDir에 남지 않는다.
      final leftover = Directory(p.join(workspace.docDir(summary.id), '_compress_staging'));
      expect(await leftover.exists(), isFalse);
    });
  });
}
