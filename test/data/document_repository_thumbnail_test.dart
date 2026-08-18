/// `DocumentRepository.ensureThumbnail` 회귀 테스트. (설계 §1.1·§1.4, T3)
///
/// **RO 원칙**: 반환값이 아니라 `thumbs/<docId>.png` 파일을 다시 읽어 PNG
/// 시그니처와 폭을 확인한다 — 반환 경로 단언만으로는 "경로는 맞고 파일은
/// 없는" 결함을 잡지 못한다(설계 §1.1 명시 요구사항).
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

/// `document.pdf`를 실제로 스테이징 경로에 써주는 최소 엔진 스텁 —
/// `ensureThumbnail`이 `Workspace.docPdf(docId)`를 렌더러에 넘기므로 파일이
/// 실존해야 `createDocument`의 커밋 흐름이 성립한다.
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
    await File(outputPath).writeAsBytes([1, 2, 3]);
    return const PdfOk(
      SaveOutcome(
        outputPath: '',
        bytes: 3,
        pageCount: 1,
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

/// 호출 횟수를 세고, 지정한 결과를 순서대로(또는 마지막 값을 반복) 돌려주는
/// 렌더러 스텁. 재렌더 억제(캐시 재사용) 검증에 호출 카운트가 필요하다.
class _CountingPdfRenderer implements PdfRenderer {
  _CountingPdfRenderer(this._results);

  final List<PdfResult<Uint8List>> Function() _results;
  int renderThumbnailCalls = 0;
  int? lastTargetWidthPx;

  @override
  Future<PdfResult<Uint8List>> renderThumbnail({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
  }) async {
    renderThumbnailCalls++;
    lastTargetWidthPx = targetWidthPx;
    final results = _results();
    return results[(renderThumbnailCalls - 1).clamp(0, results.length - 1)];
  }

  @override
  Future<PdfResult<int>> openPageCount(String pdfPath, {String? password}) =>
      throw UnimplementedError();

  @override
  Future<PdfResult<Uint8List>> renderPage({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
    CancelToken? cancelToken,
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

/// 1x1 PNG 시그니처가 포함된 최소 유효 바이트열(실제 디코딩은 하지 않는다 —
/// 여기서는 "PNG 시그니처가 그대로 파일에 쓰였는가"만 확인한다).
final _fakePngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late AppWorkspace workspace;
  late AppDatabase db;
  late String sourceImagePath;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_thumb_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
    db = AppDatabase(NativeDatabase.memory());

    sourceImagePath = p.join(tempRoot.path, 'external', 'scan.jpg');
    await File(sourceImagePath).create(recursive: true);
    await File(sourceImagePath).writeAsBytes(List.filled(10, 0xCD));
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<String> createDoc(DriftDocumentRepository repo) async {
    final result = await repo.createDocument(
      title: '테스트 문서',
      origin: DocOrigin.scan,
      pages: [ImagePageRef(imagePath: sourceImagePath, rotation: 0)],
      quality: ImageQuality.standard,
      guardInput: const GuardInput(op: SaveOp.merge, baselineBytes: 10),
    );
    expect(result, isA<PdfOk<DocumentSummary>>());
    return (result as PdfOk<DocumentSummary>).value.id;
  }

  test('썸네일이 없으면 렌더해서 thumbs/<docId>.png로 쓰고 경로를 돌려준다', () async {
    final renderer = _CountingPdfRenderer(() => [PdfOk(_fakePngBytes)]);
    final repo = DriftDocumentRepository(
      db: db,
      workspace: workspace,
      engine: _StubPdfEngine(),
      renderer: renderer,
    );
    final docId = await createDoc(repo);

    final result = await repo.ensureThumbnail(docId);

    expect(result, isA<PdfOk<String?>>());
    final path = (result as PdfOk<String?>).value;
    expect(path, workspace.thumb(docId));

    // RO: 반환값이 아니라 파일 자체를 다시 읽어 확인한다.
    final bytes = await File(path!).readAsBytes();
    expect(bytes.sublist(0, 8), _fakePngBytes.sublist(0, 8), reason: 'PNG 시그니처가 그대로 남아야 한다');
    expect(renderer.lastTargetWidthPx, DocumentRepository.thumbWidthPx);
  });

  test('이미 존재하면 재렌더하지 않는다', () async {
    final renderer = _CountingPdfRenderer(() => [PdfOk(_fakePngBytes)]);
    final repo = DriftDocumentRepository(
      db: db,
      workspace: workspace,
      engine: _StubPdfEngine(),
      renderer: renderer,
    );
    final docId = await createDoc(repo);

    final first = await repo.ensureThumbnail(docId);
    expect(first, isA<PdfOk<String?>>());
    expect(renderer.renderThumbnailCalls, 1);

    final second = await repo.ensureThumbnail(docId);
    expect(second, isA<PdfOk<String?>>());
    expect(renderer.renderThumbnailCalls, 1, reason: '파일이 이미 있으면 다시 렌더하면 안 된다');
    expect((second as PdfOk<String?>).value, workspace.thumb(docId));
  });

  test('손상·암호 등으로 렌더가 실패하면 PdfOk(null)이고 파일을 만들지 않으며, 같은 세션에서 재시도하지 않는다', () async {
    final renderer = _CountingPdfRenderer(() => [const PdfErr(SourceCorrupted('x'))]);
    final repo = DriftDocumentRepository(
      db: db,
      workspace: workspace,
      engine: _StubPdfEngine(),
      renderer: renderer,
    );
    final docId = await createDoc(repo);

    final first = await repo.ensureThumbnail(docId);
    expect(first, isA<PdfOk<String?>>());
    expect((first as PdfOk<String?>).value, isNull);
    expect(await File(workspace.thumb(docId)).exists(), isFalse);
    expect(renderer.renderThumbnailCalls, 1);

    final second = await repo.ensureThumbnail(docId);
    expect(second, isA<PdfOk<String?>>());
    expect((second as PdfOk<String?>).value, isNull);
    expect(renderer.renderThumbnailCalls, 1, reason: '같은 세션에서 실패한 문서는 다시 렌더를 시도하지 않는다');
  });

  test('동일 docId 동시 호출은 1개로 합쳐 렌더가 1번만 일어난다', () async {
    final renderer = _CountingPdfRenderer(() => [PdfOk(_fakePngBytes)]);
    final repo = DriftDocumentRepository(
      db: db,
      workspace: workspace,
      engine: _StubPdfEngine(),
      renderer: renderer,
    );
    final docId = await createDoc(repo);

    final results = await Future.wait([
      repo.ensureThumbnail(docId),
      repo.ensureThumbnail(docId),
      repo.ensureThumbnail(docId),
    ]);

    expect(results, everyElement(isA<PdfOk<String?>>()));
    expect(renderer.renderThumbnailCalls, 1, reason: '동시 호출은 1개로 합쳐져야 한다');
  });

  test('존재하지 않는 docId는 PdfOk(null)을 반환하고 렌더러를 호출하지 않는다', () async {
    final renderer = _CountingPdfRenderer(() => [PdfOk(_fakePngBytes)]);
    final repo = DriftDocumentRepository(
      db: db,
      workspace: workspace,
      engine: _StubPdfEngine(),
      renderer: renderer,
    );

    final result = await repo.ensureThumbnail('존재하지-않는-id');

    expect(result, isA<PdfOk<String?>>());
    expect((result as PdfOk<String?>).value, isNull);
    expect(renderer.renderThumbnailCalls, 0);
  });
}
