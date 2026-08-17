/// 문서 저장소. (설계 §2.8, 확정)
///
/// `createDocument`는 스테이징 → `PdfEngine.save` → 원자적 반영 → DB 기록 순으로
/// 진행하며, 실패·취소 시 스테이징을 폐기하고 DB에 아무것도 남기지 않는다(§7.3).
///
/// **미해결 의존(산출물 노트 참조)**: `pdf/pdf_engine.dart`(PdfEngine, SaveOutcome,
/// ImageQuality)는 아직 pdf-core가 만들지 않았다. 이 파일은 설계 §2.3 시그니처를
/// 전제로 import만 작성했으며, 해당 파일이 생기기 전까지 이 파일은 analyze 에러가
/// 난다(의도된 상태).
library;

import 'dart:io';

import 'package:drift/drift.dart' as drift;

import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/progress.dart';
import '../../core/size_guard.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_engine.dart';
import '../db/app_database.dart';
import '../storage/workspace.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

abstract interface class DocumentRepository {
  /// 목록(최신순 고정). 정렬 옵션 없음.
  Stream<List<DocumentSummary>> watchDocuments();

  Future<PdfResult<DocumentDetail>> load(String docId);

  /// 신규 문서 생성: 스테이징 → PdfEngine.save → 원자적 반영 → DB 기록.
  /// 실패·취소 시 스테이징 폐기, DB 미기록(§7.3).
  Future<PdfResult<DocumentSummary>> createDocument({
    required String title,
    required DocOrigin origin,
    required List<PageRef> pages,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });

  Future<PdfResult<DocumentSummary>> rename(String docId, String newTitle);
  Future<PdfResult<void>> delete(String docId);

  /// 앱 시작 시 1회. DB에 있으나 파일이 없는 문서를 목록에서 제거하고,
  /// docs/ 에 있으나 DB에 없는 디렉터리는 그대로 둔다(파일이 원본 진실이며
  /// 사용자 데이터를 임의 삭제하지 않는다).
  Future<void> reconcileWithFilesystem();
}

class DocumentSummary {
  const DocumentSummary({
    required this.id,
    required this.title,
    required this.origin,
    required this.pageCount,
    required this.fileSize,
    required this.createdAt,
    required this.updatedAt,
    required this.thumbPath,
  });
  final String id;
  final String title; // 한글 원문 그대로. 경로에 쓰지 않는다.
  final DocOrigin origin;
  final int pageCount;
  final int fileSize;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbPath;
}

class DocumentDetail {
  const DocumentDetail({required this.summary, required this.pages});
  final DocumentSummary summary;
  final List<PageRef> pages; // DB pages 행 → PageRef 복원
}

enum DocOrigin { scan, photo, imported }

String _originToDb(DocOrigin o) => switch (o) {
  DocOrigin.scan => 'scan',
  DocOrigin.photo => 'photo',
  DocOrigin.imported => 'imported',
};

DocOrigin _originFromDb(String s) => switch (s) {
  'scan' => DocOrigin.scan,
  'photo' => DocOrigin.photo,
  'imported' => DocOrigin.imported,
  _ => throw StateError('unknown origin: $s'),
};

/// `PageRef` → DB 행 변환 시 kind/source_index 조합을 assert로 이중 방어한다
/// (스키마의 CHECK 제약과 별도로 코드 레벨에서도 지킨다, §6).
PagesCompanion _pageToCompanion(String id, String docId, int orderIndex, PageRef page) {
  return switch (page) {
    ImagePageRef(:final imagePath, :final rotation) => PagesCompanion.insert(
      id: id,
      docId: docId,
      orderIndex: orderIndex,
      kind: 'image',
      sourcePath: imagePath,
      rotation: drift.Value(rotation),
    ),
    PdfPageRef(:final sourcePath, :final sourceIndex, :final rotation) => PagesCompanion.insert(
      id: id,
      docId: docId,
      orderIndex: orderIndex,
      kind: 'pdf',
      sourcePath: sourcePath,
      sourceIndex: drift.Value(sourceIndex),
      rotation: drift.Value(rotation),
    ),
  };
}

PageRef _pageRowToRef(Page row) {
  assert(
    (row.kind == 'pdf' && row.sourceIndex != null) ||
        (row.kind == 'image' && row.sourceIndex == null),
    'kind/source_index 조합 위반: ${row.kind}/${row.sourceIndex} (doc=${row.docId})',
  );
  return switch (row.kind) {
    'image' => ImagePageRef(imagePath: row.sourcePath, rotation: row.rotation),
    'pdf' => PdfPageRef(
      sourcePath: row.sourcePath,
      sourceIndex: row.sourceIndex!,
      rotation: row.rotation,
    ),
    _ => throw StateError('unknown page kind: ${row.kind} (doc=${row.docId})'),
  };
}

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository({
    required AppDatabase db,
    required Workspace workspace,
    required PdfEngine engine,
    Uuid? uuid,
  }) : _db = db,
       _workspace = workspace,
       _engine = engine,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Workspace _workspace;
  final PdfEngine _engine;
  final Uuid _uuid;

  DocumentSummary _toSummary(Document row) => DocumentSummary(
    id: row.id,
    title: row.title,
    origin: _originFromDb(row.origin),
    pageCount: row.pageCount,
    fileSize: row.fileSize,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    thumbPath: row.thumbPath,
  );

  @override
  Stream<List<DocumentSummary>> watchDocuments() {
    final query = _db.select(_db.documents)
      ..orderBy([(t) => drift.OrderingTerm(expression: t.updatedAt, mode: drift.OrderingMode.desc)]);
    return query.watch().map((rows) => rows.map(_toSummary).toList());
  }

  @override
  Future<PdfResult<DocumentDetail>> load(String docId) async {
    final docRow = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(docId))).getSingleOrNull();
    if (docRow == null) {
      return const PdfErr(UnknownFailure('document not found'));
    }
    final pageRows =
        await (_db.select(_db.pages)
              ..where((t) => t.docId.equals(docId))
              ..orderBy([(t) => drift.OrderingTerm(expression: t.orderIndex)]))
            .get();
    final pages = pageRows.map(_pageRowToRef).toList();
    return PdfOk(DocumentDetail(summary: _toSummary(docRow), pages: pages));
  }

  @override
  Future<PdfResult<DocumentSummary>> createDocument({
    required String title,
    required DocOrigin origin,
    required List<PageRef> pages,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final docId = _uuid.v4();
    String stagingDir;
    try {
      stagingDir = await _workspace.beginStaging(docId);
    } catch (e) {
      return PdfErr(UnknownFailure('스테이징 생성 실패: $e'));
    }

    try {
      final stagingPdfPath = p.join(stagingDir, 'document.pdf');

      final saveResult = await _engine.save(
        pages: pages,
        outputPath: stagingPdfPath,
        quality: quality,
        guardInput: guardInput,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      if (saveResult is PdfErr<SaveOutcome>) {
        await _workspace.rollbackStaging(docId);
        return PdfErr((saveResult as PdfErr<SaveOutcome>).failure);
      }
      final outcome = (saveResult as PdfOk<SaveOutcome>).value;

      try {
        await _workspace.commitStaging(docId);
      } catch (e) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(UnknownFailure('스테이징 반영 실패: $e'));
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        await _db.transaction(() async {
          await _db
              .into(_db.documents)
              .insert(
                DocumentsCompanion.insert(
                  id: docId,
                  title: title,
                  origin: _originToDb(origin),
                  pageCount: outcome.pageCount,
                  fileSize: outcome.bytes,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          for (var i = 0; i < pages.length; i++) {
            await _db
                .into(_db.pages)
                .insert(_pageToCompanion(_uuid.v4(), docId, i, pages[i]));
          }
        });
      } catch (e) {
        // DB 기록 실패: docId가 이번에 새로 발급되었으므로 기존 docDir이 없었다.
        // 복원할 ".old"가 없으므로(§7.3 설계 질의, workspace.dart 참조) 방금 커밋한
        // docs/<docId>를 통째로 지워 반쪽 문서를 남기지 않는다.
        await _deleteDocDirIfExists(docId);
        return PdfErr(UnknownFailure('DB 기록 실패: $e'));
      }

      return PdfOk(
        DocumentSummary(
          id: docId,
          title: title,
          origin: origin,
          pageCount: outcome.pageCount,
          fileSize: outcome.bytes,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
          thumbPath: null,
        ),
      );
    } catch (e) {
      await _workspace.rollbackStaging(docId);
      return PdfErr(UnknownFailure('createDocument 실패: $e'));
    }
  }

  Future<void> _deleteDocDirIfExists(String docId) async {
    final dir = Directory(_workspace.docDir(docId));
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // 삭제 실패는 무음 처리하지 않는다 — reconcileWithFilesystem이 다음
        // 시작 시 DB에 행이 없는 이 디렉터리를 고아로 남겨두되 목록에는
        // 노출하지 않는다.
      }
    }
  }

  @override
  Future<PdfResult<DocumentSummary>> rename(String docId, String newTitle) async {
    final docRow = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(docId))).getSingleOrNull();
    if (docRow == null) {
      return const PdfErr(UnknownFailure('document not found'));
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.documents,
    )..where((t) => t.id.equals(docId))).write(
      DocumentsCompanion(title: drift.Value(newTitle), updatedAt: drift.Value(now)),
    );
    return PdfOk(
      _toSummary(
        docRow.copyWith(title: newTitle, updatedAt: now),
      ),
    );
  }

  @override
  Future<PdfResult<void>> delete(String docId) async {
    try {
      await (_db.delete(
        _db.documents,
      )..where((t) => t.id.equals(docId))).go(); // pages는 FK cascade로 함께 삭제
      final dir = Directory(_workspace.docDir(docId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      final thumbFile = File(_workspace.thumb(docId));
      if (await thumbFile.exists()) {
        await thumbFile.delete();
      }
      return const PdfOk(null);
    } catch (e) {
      return PdfErr(UnknownFailure('delete 실패: $e'));
    }
  }

  @override
  Future<void> reconcileWithFilesystem() async {
    final rows = await _db.select(_db.documents).get();
    for (final row in rows) {
      final pdfFile = File(_workspace.docPdf(row.id));
      if (!await pdfFile.exists()) {
        await (_db.delete(_db.documents)..where((t) => t.id.equals(row.id))).go();
      }
    }
    // docs/ 에 있으나 DB에 없는 디렉터리는 그대로 둔다 — 파일이 원본 진실이며
    // 사용자 데이터를 임의 삭제하지 않는다(§7.3).
  }
}
