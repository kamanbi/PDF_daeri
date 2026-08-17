/// 문서 저장소. (설계 §2.8, 확정)
///
/// `createDocument`는 여유 공간 확인 → 스테이징 → 소스 복사(§7.3 2단계) →
/// `PdfEngine.save` → 원자적 반영 → DB 기록 순으로 진행하며, 실패·취소 시
/// 스테이징을 폐기하고 DB에 아무것도 남기지 않는다(§7.3).
///
/// **[2026-08-18] Q-D 정리 책임 경계**: `PdfEngine`이 반환하는 모든 `PdfErr`
/// (취소·GuardBlocked·손상·암호·공간부족 포함) 분기에서 예외 없이
/// `Workspace.rollbackStaging(docId)`를 호출한다. 디렉터리 삭제는 `Workspace`의
/// 단독 책임이며 이 파일은 `.tmp` 디렉터리를 직접 지우지 않는다
/// (`_deleteDocDirIfExists`는 커밋 **이후** DB 실패 시에만 쓰는 별개 경로다 — 04-A 참조).
library;

import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/progress.dart';
import '../../core/size_guard.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_engine.dart';
import '../db/app_database.dart';
import '../storage/workspace.dart';

abstract interface class DocumentRepository {
  /// 목록(최신순 고정). 정렬 옵션 없음.
  Stream<List<DocumentSummary>> watchDocuments();

  Future<PdfResult<DocumentDetail>> load(String docId);

  /// 신규 문서 생성: 여유 공간 확인 → 스테이징 → 소스 복사 → PdfEngine.save →
  /// 원자적 반영 → DB 기록. 실패·취소 시 스테이징 폐기, DB 미기록(§7.3).
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

/// `_copySourcesToStaging`의 반환값. 같은 인덱스로 나란히 만들어진 두 목록 —
/// [stagingPages]는 `PdfEngine.save` 입력(스테이징 경로, 지금 물리적으로 존재),
/// [finalPages]는 `commitStaging` 이후 DB에 기록할 최종 docDir 경로.
class _CopiedSources {
  const _CopiedSources({required this.stagingPages, required this.finalPages});
  final List<PageRef> stagingPages;
  final List<PageRef> finalPages;
}

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository({
    required this._db,
    required this._workspace,
    required this._engine,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

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
    // §7.3 "저장 전 여유 공간 확인". freeSpaceBytes()가 -1(판단 불가)이면
    // 막지 않는다 — 채널 실패를 저장 실패로 오인시키지 않기 위함(workspace.dart 참조).
    //
    // 산출식 근거(2026-08-18, B6 소스 복사 도입에 따른 재추정, I3 — 상수는
    // Workspace 소유, 식은 SaveOp 의미에 의존하므로 여기 둔다): B6 이후
    // `createDocument`는 스테이징에 (1) 원본 소스 전체 복사본과 (2) 최종
    // 산출물을 동시에 담는다. `SaveOp`별 `guardInput.baselineBytes`는
    // `deletePages`/`reorderOrRotate`/`split` = 원본 PDF 전체 바이트(split도
    // 파일 단위로 전체를 복사하므로 일치), `merge` = 원본들의 합계 바이트다
    // (§4.2). "복사된 소스(약 baselineBytes) + 최종 산출물(SizeGuard 한계상
    // 최대 baselineBytes × 1.20)"의 실측 피크는 baselineBytes × 2 근처이거나
    // 근소하게 초과할 수 있다 — 설계 §7.3에 확정된 계수를 그대로 쓰되, M1~M6
    // 실측 후 재검토 대상으로 노트에 남겨둔다.
    final requiredBytes = guardInput.baselineBytes * 2 + Workspace.spaceSafetyBufferBytes;
    final freeBytes = await _workspace.freeSpaceBytes();
    if (freeBytes >= 0 && freeBytes < requiredBytes) {
      return PdfErr(OutOfSpace(requiredBytes));
    }

    final docId = _uuid.v4();
    try {
      await _workspace.beginStaging(docId);
    } catch (e) {
      return PdfErr(UnknownFailure('스테이징 생성 실패: $e'));
    }

    try {
      // §7.3 2단계: 원본 소스를 .tmp/sources/ 로 복사한다. 경로 조립은 전부
      // Workspace가 소유한다(N2, 2026-08-18) — 이 파일은 p.join으로 경로를
      // 만들지 않는다. _copySourcesToStaging은 스테이징 경로(엔진 입력용)와
      // 최종 docDir 경로(DB 기록용)를 같은 인덱스로 나란히 반환한다. 두 경로가
      // 같은 `Workspace.stagingSourcePdf`/`sourcePdf` 쌍에서 나오므로
      // commitStaging의 rename 이후에도 정확히 대응한다 — 별도의 문자열
      // 치환("rebase") 단계가 필요 없다.
      final copyResult = await _copySourcesToStaging(docId: docId, pages: pages);
      if (copyResult is PdfErr<_CopiedSources>) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(copyResult.failure);
      }
      final copied = (copyResult as PdfOk<_CopiedSources>).value;

      final saveResult = await _engine.save(
        pages: copied.stagingPages,
        outputPath: _workspace.stagingDocPdf(docId),
        quality: quality,
        guardInput: guardInput,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      if (saveResult is PdfErr<SaveOutcome>) {
        // Q-D(2026-08-18): 엔진은 자기 출력 파일만 지운다. 디렉터리 정리는
        // 예외 없이 여기(Repository)가 Workspace에 위임한다.
        await _workspace.rollbackStaging(docId);
        return PdfErr(saveResult.failure);
      }
      final outcome = (saveResult as PdfOk<SaveOutcome>).value;

      try {
        await _workspace.commitStaging(docId);
      } catch (e) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(UnknownFailure('스테이징 반영 실패: $e'));
      }

      // commitStaging이 .tmp를 최종 docDir로 rename한 시점부터 copied.finalPages
      // (처음부터 Workspace.sourcePdf/sourceImage로 만들어진 최종 경로)가
      // 실제 파일 위치와 일치한다.
      final finalPages = copied.finalPages;

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
          for (var i = 0; i < finalPages.length; i++) {
            await _db
                .into(_db.pages)
                .insert(_pageToCompanion(_uuid.v4(), docId, i, finalPages[i]));
          }
        });
      } catch (e) {
        // DB 기록 실패: docId가 이번에 새로 발급되었으므로 기존 docDir이 없었다.
        // 복원할 ".old"가 없으므로(04-A, 3주차까지 확정 보류) 방금 커밋한
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

  /// §7.3 2단계. 각 페이지의 원본 소스 파일을 스테이징(`docId.tmp`)의
  /// `sources/`로 복사한다. 경로는 전부 `Workspace`가 조립한다(N2,
  /// 2026-08-18) — 이 메서드는 `p.join`을 쓰지 않는다.
  ///
  /// 스테이징 경로(`Workspace.stagingSourcePdf`/`stagingSourceImage`, 물리
  /// 복사 대상이자 `PdfEngine.save` 입력)와 최종 경로(`Workspace.sourcePdf`/
  /// `sourceImage`, DB 기록용)를 **같은 인덱스**로 나란히 만든다. 두 경로가
  /// 같은 파일명 규약에서 나오므로 `commitStaging`의 rename 이후에도 정확히
  /// 대응하며, 문자열 치환("rebase") 없이 최종 경로를 그대로 DB에 쓸 수 있다.
  ///
  /// 동일 원본 경로가 여러 페이지에서 참조되면(같은 PDF에서 여러 페이지를 뽑아
  /// 합치는 경우, 동일 스캔 이미지를 두 번 넣는 경우) 한 번만 복사한다.
  Future<PdfResult<_CopiedSources>> _copySourcesToStaging({
    required String docId,
    required List<PageRef> pages,
  }) async {
    final copiedPdfIndex = <String, int>{}; // 원본 경로 -> 배정된 소스 번호
    final copiedImageIndex = <String, int>{};
    var nextPdfIndex = 1;
    var nextImageIndex = 1;
    final stagingPages = <PageRef>[];
    final finalPages = <PageRef>[];

    for (final page in pages) {
      switch (page) {
        case PdfPageRef(:final sourcePath, :final sourceIndex, :final rotation):
          var n = copiedPdfIndex[sourcePath];
          if (n == null) {
            final srcFile = File(sourcePath);
            if (!await srcFile.exists()) {
              return PdfErr(SourceMissing(sourcePath));
            }
            n = nextPdfIndex++;
            try {
              await srcFile.copy(_workspace.stagingSourcePdf(docId, n));
            } catch (e) {
              return PdfErr(UnknownFailure('소스 PDF 복사 실패: $sourcePath ($e)'));
            }
            copiedPdfIndex[sourcePath] = n;
          }
          stagingPages.add(
            PdfPageRef(
              sourcePath: _workspace.stagingSourcePdf(docId, n),
              sourceIndex: sourceIndex,
              rotation: rotation,
            ),
          );
          finalPages.add(
            PdfPageRef(
              sourcePath: _workspace.sourcePdf(docId, n),
              sourceIndex: sourceIndex,
              rotation: rotation,
            ),
          );
        case ImagePageRef(:final imagePath, :final rotation):
          var n = copiedImageIndex[imagePath];
          if (n == null) {
            final srcFile = File(imagePath);
            if (!await srcFile.exists()) {
              return PdfErr(SourceMissing(imagePath));
            }
            n = nextImageIndex++;
            try {
              await srcFile.copy(_workspace.stagingSourceImage(docId, n));
            } catch (e) {
              return PdfErr(UnknownFailure('소스 이미지 복사 실패: $imagePath ($e)'));
            }
            copiedImageIndex[imagePath] = n;
          }
          stagingPages.add(
            ImagePageRef(imagePath: _workspace.stagingSourceImage(docId, n), rotation: rotation),
          );
          finalPages.add(
            ImagePageRef(imagePath: _workspace.sourceImage(docId, n), rotation: rotation),
          );
      }
    }

    return PdfOk(_CopiedSources(stagingPages: stagingPages, finalPages: finalPages));
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
