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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/file_name.dart';
import '../../core/progress.dart';
import '../../core/size_guard.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_compressor.dart';
import '../../pdf/pdf_engine.dart';
import '../../pdf/pdf_renderer.dart';
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

  /// **M-E7** — 압축 결과를 **새 문서**로 만든다(`_workspace/31_architect_external_compress_l2.md`
  /// §2/§3.2/§4.5). 원본(`docs/<docId>/` 또는 `recent/<id>.pdf`)은 절대 수정하지 않는다 —
  /// 항상 새 `docId`(UUID v4)의 문서를 만든다.
  ///
  /// 절차: ① `Workspace.freeSpaceBytes()`로 여유 공간 확인(원본의 약 1.2배, §31 R3) —
  /// 부족하면 스테이징 시작 전에 `OutOfSpace`로 즉시 실패 ② 스테이징 생성 ③
  /// `PdfCompressor.compress` 호출 — [source]가 [CompressSource.myDocument]이고 그
  /// 문서의 페이지 전량이 `ImagePageRef`면 L2-app(`imagePagePaths`), 그 외(혼합 내
  /// 문서·[CompressSource.externalPdf])는 L2-ext(`embeddedImageStagingDir`)로 실행한다
  /// ④ 결과 파일 커밋(원자적 rename), DB 행 생성 — 제목은 `FileName.compressedTitle`
  /// (`<원본 제목> (압축)`, `(압축본)` 아님, Q21) ⑤ 실패·취소 시 스테이징을 남기지 않는다
  /// (`Workspace.rollbackStaging` 재사용).
  ///
  /// `outcome.keptOriginal`(압축 효과 없음)이면 **새 문서를 만들지 않는다** — 스테이징을
  /// 버리고 [CompressToNewDocumentResult.summary]가 `null`인 결과를 돌려준다(§4.3 상태3).
  Future<PdfResult<CompressToNewDocumentResult>> compressToNewDocument({
    required CompressSource source,
    required ImageQuality preset,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });

  Future<PdfResult<DocumentSummary>> rename(String docId, String newTitle);
  Future<PdfResult<void>> delete(String docId);

  /// 앱 시작 시 1회. DB에 있으나 파일이 없는 문서를 목록에서 제거하고,
  /// docs/ 에 있으나 DB에 없는 디렉터리는 그대로 둔다(파일이 원본 진실이며
  /// 사용자 데이터를 임의 삭제하지 않는다).
  Future<void> reconcileWithFilesystem();

  /// [2주차 신설 · §1.1] 목록용 대표 썸네일을 **필요할 때 만들어** 파일로 남기고
  /// 경로를 돌려준다.
  ///
  /// - 이미 `thumbs/<docId>.png`가 존재하면 렌더하지 않고 그 경로만 반환한다.
  /// - 없으면 `PdfRenderer.renderThumbnail(pageIndex: 0, targetWidthPx: thumbWidthPx)`로
  ///   바이트를 받아 파일로 쓰고, `documents.thumb_path`를 갱신한 뒤 경로를 반환한다.
  ///   파일을 쓰는 주체는 Repository이고 Renderer는 바이트만 준다(설계 §7.1 불변).
  /// - 문서를 열 수 없으면(손상·암호) 파일을 만들지 않고 `PdfOk(null)`을 반환한다.
  ///   썸네일 부재는 실패가 아니라 정상 상태다 — 목록에 자리표시자 아이콘이 나온다.
  ///   같은 세션에서는 재시도하지 않는다(§1.4 — 손상 파일을 스크롤할 때마다
  ///   렌더를 반복하지 않게).
  /// - 동일 `docId`에 대한 동시 호출은 내부에서 1개로 합친다(그리드 스크롤 중
  ///   중복 렌더 방지). 동시 렌더 상한은 3이며 초과 요청은 큐잉한다(§1.4).
  Future<PdfResult<String?>> ensureThumbnail(String docId);

  /// 목록 썸네일의 렌더 폭. 상수는 여기 1곳에만 존재한다(§1.1).
  /// 2열 그리드 · 3x DPI 기준 카드 폭 ≈ 200dp → 320px로 고정한다(목록 썸네일은
  /// 확대되지 않는다). 구현체에서 리터럴 `320`을 다시 쓰면 안 된다.
  static const int thumbWidthPx = 320;
}

/// `ensureThumbnail`의 동시 렌더 상한(§1.4) — 빠른 스크롤 시 수십 개가 동시에
/// 붙는 것을 막는다.
const int _thumbnailConcurrencyLimit = 3;

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

/// `compressToNewDocument`의 압축 대상 지정. `lib/pdf/**`가 `lib/data/**`를 모르는
/// 레이어 경계(`pdf_compressor.dart` 상단 문서)를 지키기 위해, "내 문서인가 외부
/// PDF인가"의 판별은 이 타입으로 Repository 밖(호출자)이 명시적으로 알려준다.
sealed class CompressSource {
  const CompressSource();

  /// 내 문서(`docs/<docId>/`). 페이지 전량이 `ImagePageRef`면 L2-app으로,
  /// 그 외(혼합 문서)는 L2-ext로 압축한다 — 판별 근거인 `pages.kind`는
  /// `compressToNewDocument`가 DB에서 직접 조회한다(§31 "호출자가 kind 목록을
  /// 넘긴다"는 이 경계 — `PdfCompressor`의 실제 호출자는 Repository다).
  const factory CompressSource.myDocument(String docId) = _MyDocumentSource;

  /// 외부에서 연 PDF(`recent/<id>.pdf` 등). 앱이 소유하지 않는 원본이므로 항상
  /// L2-ext로 압축한다. [title]은 결과 문서 제목의 원본 제목으로 쓰인다
  /// (Repository는 `recent_files` 테이블을 모르므로 호출자가 표시명을 전달한다).
  const factory CompressSource.externalPdf({required String pdfPath, required String title}) =
      _ExternalPdfSource;
}

final class _MyDocumentSource extends CompressSource {
  const _MyDocumentSource(this.docId);
  final String docId;
}

final class _ExternalPdfSource extends CompressSource {
  const _ExternalPdfSource({required this.pdfPath, required this.title});
  final String pdfPath;
  final String title;
}

/// `compressToNewDocument`의 결과. [summary]가 `null`이면 [keptOriginal]이 true라는
/// 뜻이다 — 압축 효과가 없어 새 문서를 만들지 않았다(§4.3 상태3 "이미 최적화된 문서").
class CompressToNewDocumentResult {
  const CompressToNewDocumentResult({
    required this.summary,
    required this.originalBytes,
    required this.resultBytes,
    required this.keptOriginal,
  });

  final DocumentSummary? summary;
  final int originalBytes;
  final int resultBytes;
  final bool keptOriginal;
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
///
/// [2026-08-20 · 3주차 schemaVersion 2] `pages.crop` 컬럼 신설에 맞춰 assert를
/// 확장한다 — `addColumn` 마이그레이션은 기존 설치의 `pages` 테이블에 새 CHECK
/// (`kind='image' OR crop IS NULL`)를 걸지 않으므로(SQLite 제약, `app_database.dart`
/// 주석 참조), 이 코드 레벨 방어가 실질적인 유일한 방어선이다.
PagesCompanion _pageToCompanion(String id, String docId, int orderIndex, PageRef page) {
  return switch (page) {
    ImagePageRef(:final imagePath, :final rotation, :final crop) => PagesCompanion.insert(
      id: id,
      docId: docId,
      orderIndex: orderIndex,
      kind: 'image',
      sourcePath: imagePath,
      rotation: drift.Value(rotation),
      crop: drift.Value(crop?.encode()),
    ),
    PdfPageRef(:final sourcePath, :final sourceIndex, :final rotation) => PagesCompanion.insert(
      id: id,
      docId: docId,
      orderIndex: orderIndex,
      kind: 'pdf',
      sourcePath: sourcePath,
      sourceIndex: drift.Value(sourceIndex),
      rotation: drift.Value(rotation),
      // PdfPageRef는 크롭을 갖지 않는다(§2.2 판정) — 여기서 명시적으로 null을 못박아
      // 호출부가 실수로 값을 흘려 넣는 경로 자체를 차단한다.
      crop: const drift.Value(null),
    ),
  };
}

PageRef _pageRowToRef(Page row) {
  assert(
    (row.kind == 'pdf' && row.sourceIndex != null) ||
        (row.kind == 'image' && row.sourceIndex == null),
    'kind/source_index 조합 위반: ${row.kind}/${row.sourceIndex} (doc=${row.docId})',
  );
  assert(
    row.kind == 'image' || row.crop == null,
    'kind/crop 조합 위반: PDF 페이지는 crop을 가질 수 없다 (doc=${row.docId})',
  );
  return switch (row.kind) {
    'image' => ImagePageRef(
      imagePath: row.sourcePath,
      rotation: row.rotation,
      crop: CropRect.decode(row.crop),
    ),
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

/// `_resolveCompressSource`의 반환값 — `compressToNewDocument`가 `PdfCompressor.compress`를
/// 호출하기 위해 필요한 것만 담는다.
class _ResolvedCompressSource {
  const _ResolvedCompressSource({
    required this.pdfPath,
    required this.originalTitle,
    required this.imagePagePaths,
  });

  /// 압축할 원본 PDF 경로(읽기 전용으로만 연다).
  final String pdfPath;
  final String originalTitle;

  /// non-null이면 L2-app(문서 페이지 전량이 `ImagePageRef`), null이면 L2-ext.
  final List<String>? imagePagePaths;
}

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository({
    required this._db,
    required this._workspace,
    required this._engine,
    required this._renderer,
    PdfCompressor? compressor,
    Uuid? uuid,
  }) : _compressor = compressor ?? const QpdfCompressor(),
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Workspace _workspace;
  final PdfEngine _engine;
  final PdfRenderer _renderer;
  final PdfCompressor _compressor;
  final Uuid _uuid;

  // ensureThumbnail(§1.1·§1.4): 동일 docId 동시 호출 병합 + 동시 렌더 3개 제한 큐
  // + 같은 세션 내 실패 재시도 억제. 인스턴스 소유 상태이며 DB에 반영되지 않는다.
  final Map<String, Future<PdfResult<String?>>> _thumbnailInFlight = {};
  final Set<String> _thumbnailFailedOnce = {};
  int _thumbnailActiveCount = 0;
  final List<Completer<void>> _thumbnailWaitQueue = [];

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

      // §1.5 "동일 제목 회피" — FileName.dedupe는 구현돼 있었으나 호출 지점이
      // 없었다(설계 §1.5·§3.5 갭). createDocument 삽입 직전이 유일한 호출 지점이다
      // — 화면은 dedupe를 하지 않는다. 정규화까지 여기서 함께 적용해, 화면이
      // 이미 정규화를 거쳤든 아니든(합치기/나누기/편집 파생 제목 포함) 최종
      // 삽입 제목은 항상 이 함수를 통과한 값이다.
      final existingTitles = (await _db.select(_db.documents).get())
          .map((row) => row.title)
          .toSet();
      final dedupedTitle = FileName.dedupe(FileName.normalize(title), existingTitles);

      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        await _db.transaction(() async {
          await _db
              .into(_db.documents)
              .insert(
                DocumentsCompanion.insert(
                  id: docId,
                  title: dedupedTitle,
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
          title: dedupedTitle,
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

  /// **M-E7** — 인터페이스 문서 참조. 원본(`docs/<docId>/` 또는 외부 PDF)은 읽기만
  /// 한다 — 새 `docId`를 발급하고 그 스테이징에만 쓴다(절대 규칙: 원본 미수정).
  @override
  Future<PdfResult<CompressToNewDocumentResult>> compressToNewDocument({
    required CompressSource source,
    required ImageQuality preset,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final resolveResult = await _resolveCompressSource(source);
    if (resolveResult is PdfErr<_ResolvedCompressSource>) {
      return PdfErr(resolveResult.failure);
    }
    final resolved = (resolveResult as PdfOk<_ResolvedCompressSource>).value;

    final srcFile = File(resolved.pdfPath);
    if (!srcFile.existsSync()) {
      return PdfErr(SourceMissing(resolved.pdfPath));
    }
    final originalBytes = srcFile.lengthSync();

    // §31 R3: "대형 스캔 PDF에서 디스크·메모리 압박" — 원본의 약 1.2배 여유 공간이
    // 필요하다. createDocument의 §7.3과 같은 원칙(스테이징 시작 전에 확인, freeBytes
    // -1이면 판단 불가로 취급해 막지 않는다)을 그대로 따른다.
    final requiredBytes = (originalBytes * 1.2).ceil() + Workspace.spaceSafetyBufferBytes;
    final freeBytes = await _workspace.freeSpaceBytes();
    if (freeBytes >= 0 && freeBytes < requiredBytes) {
      return PdfErr(OutOfSpace(requiredBytes));
    }

    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    final docId = _uuid.v4();
    try {
      await _workspace.beginStaging(docId);
    } catch (e) {
      return PdfErr(UnknownFailure('스테이징 생성 실패: $e'));
    }

    try {
      final stagingPdfPath = _workspace.stagingDocPdf(docId);
      // L2-app(모든 페이지가 ImagePageRef)이면 imagePagePaths를, 그 외(외부 PDF·혼합
      // 내 문서)는 embeddedImageStagingDir를 넘긴다 — 둘은 상호 배타이며 이 분기가
      // 유일한 선택 지점이다(`PdfCompressor.compress` §31 §2.6).
      final embeddedStagingDir = resolved.imagePagePaths == null
          ? _workspace.stagingCompressImagesDir(docId)
          : null;

      final compressResult = await _compressor.compress(
        pdfPath: resolved.pdfPath,
        outputPath: stagingPdfPath,
        preset: preset,
        imagePagePaths: resolved.imagePagePaths,
        embeddedImageStagingDir: embeddedStagingDir,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      if (compressResult is PdfErr<CompressOutcome>) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(compressResult.failure);
      }
      final outcome = (compressResult as PdfOk<CompressOutcome>).value;

      // L2-ext가 남긴 임시 추출 폴더는 최종 docDir에 들어가면 안 된다(sources/도
      // cache/도 아닌 순수 작업 폴더) — keptOriginal이든 아니든 여기서 지운다.
      // 실패 경로는 위에서 이미 rollbackStaging으로 `.tmp` 전체가 지워지므로 별도
      // 처리가 필요 없다.
      if (embeddedStagingDir != null) {
        final dir = Directory(embeddedStagingDir);
        if (await dir.exists()) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {
            // 최선 노력 — rollbackStaging/commitStaging 어느 쪽이든 `.tmp`를
            // 통째로 정리하거나 옮기므로 여기 잔재가 최종 결과에 남지 않는다.
          }
        }
      }

      if (outcome.keptOriginal) {
        // §4.3 상태3 "이미 최적화된 문서" — 새 문서를 만들지 않는다. 스테이징을
        // 버린다(성공이지만 커밋할 산출물이 없다).
        await _workspace.rollbackStaging(docId);
        return PdfOk(
          CompressToNewDocumentResult(
            summary: null,
            originalBytes: outcome.originalBytes,
            resultBytes: outcome.resultBytes,
            keptOriginal: true,
          ),
        );
      }

      if (cancelToken?.isCancelled ?? false) {
        await _workspace.rollbackStaging(docId);
        return const PdfErr(Cancelled());
      }

      // 재편집 가능성 보장(B6과 같은 원칙, §7.3): 압축 산출물 자체를 sources/src_1.pdf로도
      // 남겨 pages 행이 PdfPageRef(sourcePath: sources/src_1.pdf, sourceIndex: i)로
      // 재구성 가능하게 한다. document.pdf와 내용이 같으므로 재렌더가 아니라 파일 복사다.
      final pageCountResult = await _renderer.openPageCount(stagingPdfPath);
      if (pageCountResult is PdfErr<int>) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(pageCountResult.failure);
      }
      final pageCount = (pageCountResult as PdfOk<int>).value;

      try {
        await File(stagingPdfPath).copy(_workspace.stagingSourcePdf(docId, 1));
      } catch (e) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(UnknownFailure('압축 결과 소스 복사 실패: $e'));
      }

      try {
        await _workspace.commitStaging(docId);
      } catch (e) {
        await _workspace.rollbackStaging(docId);
        return PdfErr(UnknownFailure('스테이징 반영 실패: $e'));
      }

      final finalSourcePath = _workspace.sourcePdf(docId, 1);
      final title = FileName.compressedTitle(resolved.originalTitle);
      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        await _db.transaction(() async {
          await _db
              .into(_db.documents)
              .insert(
                DocumentsCompanion.insert(
                  id: docId,
                  title: title,
                  origin: _originToDb(DocOrigin.imported),
                  pageCount: pageCount,
                  fileSize: outcome.resultBytes,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          for (var i = 0; i < pageCount; i++) {
            await _db
                .into(_db.pages)
                .insert(
                  _pageToCompanion(
                    _uuid.v4(),
                    docId,
                    i,
                    PdfPageRef(sourcePath: finalSourcePath, sourceIndex: i, rotation: 0),
                  ),
                );
          }
        });
      } catch (e) {
        // DB 기록 실패: docId가 새로 발급되었으므로 복원할 ".old"가 없다(04-A와 동일
        // 사유) — 방금 커밋한 docs/<docId>를 통째로 지워 반쪽 문서를 남기지 않는다.
        await _deleteDocDirIfExists(docId);
        return PdfErr(UnknownFailure('DB 기록 실패: $e'));
      }

      return PdfOk(
        CompressToNewDocumentResult(
          summary: DocumentSummary(
            id: docId,
            title: title,
            origin: DocOrigin.imported,
            pageCount: pageCount,
            fileSize: outcome.resultBytes,
            createdAt: DateTime.fromMillisecondsSinceEpoch(now),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
            thumbPath: null,
          ),
          originalBytes: outcome.originalBytes,
          resultBytes: outcome.resultBytes,
          keptOriginal: false,
        ),
      );
    } catch (e) {
      await _workspace.rollbackStaging(docId);
      return PdfErr(UnknownFailure('compressToNewDocument 실패: $e'));
    }
  }

  /// [source]를 실제 압축 입력(원본 PDF 경로·원본 제목·L2-app용 이미지 경로 목록)으로
  /// 해석한다. [CompressSource.myDocument]는 DB에서 제목·페이지 종류를 조회해
  /// "전량 이미지"일 때만 [imagePagePaths]를 채운다 — 그 외에는 `null`을 돌려줘
  /// `compressToNewDocument`가 L2-ext(embeddedImageStagingDir)로 넘어가게 한다.
  Future<PdfResult<_ResolvedCompressSource>> _resolveCompressSource(CompressSource source) async {
    switch (source) {
      case _MyDocumentSource(:final docId):
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
        final allImage = pageRows.isNotEmpty && pageRows.every((r) => r.kind == 'image');
        final imagePagePaths = allImage
            ? [for (final row in pageRows) (_pageRowToRef(row) as ImagePageRef).imagePath]
            : null;
        return PdfOk(
          _ResolvedCompressSource(
            pdfPath: _workspace.docPdf(docId),
            originalTitle: docRow.title,
            imagePagePaths: imagePagePaths,
          ),
        );
      case _ExternalPdfSource(:final pdfPath, :final title):
        return PdfOk(_ResolvedCompressSource(pdfPath: pdfPath, originalTitle: title, imagePagePaths: null));
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

  @override
  Future<PdfResult<String?>> ensureThumbnail(String docId) {
    // 동일 docId 동시 호출은 1개로 합친다(그리드 스크롤 중 중복 렌더 방지).
    final inFlight = _thumbnailInFlight[docId];
    if (inFlight != null) return inFlight;

    final future = _ensureThumbnailUnshared(docId);
    _thumbnailInFlight[docId] = future;
    // 완료되면 다음 호출이 다시 캐시(파일 존재)나 재시도 억제 상태를 보게 한다.
    unawaited(future.whenComplete(() => _thumbnailInFlight.remove(docId)));
    return future;
  }

  Future<PdfResult<String?>> _ensureThumbnailUnshared(String docId) async {
    final thumbPath = _workspace.thumb(docId);
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      return PdfOk(thumbPath);
    }

    // 같은 세션에서 이미 실패(손상·암호 등)한 문서는 스크롤할 때마다 다시
    // 렌더를 시도하지 않는다(§1.4).
    if (_thumbnailFailedOnce.contains(docId)) {
      return const PdfOk(null);
    }

    await _acquireThumbnailSlot();
    try {
      // 다른 대기 중 호출이 슬롯을 기다리는 동안 이미 만들어졌을 수 있다.
      if (await thumbFile.exists()) {
        return PdfOk(thumbPath);
      }

      final docRow = await (_db.select(
        _db.documents,
      )..where((t) => t.id.equals(docId))).getSingleOrNull();
      if (docRow == null) {
        return const PdfOk(null);
      }

      final renderResult = await _renderer.renderThumbnail(
        pdfPath: _workspace.docPdf(docId),
        pageIndex: 0,
        targetWidthPx: DocumentRepository.thumbWidthPx,
      );

      switch (renderResult) {
        case PdfErr<Uint8List>():
          // 손상·암호 등으로 렌더 불가 — 실패가 아니라 정상 상태(자리표시자 유지).
          _thumbnailFailedOnce.add(docId);
          return const PdfOk(null);
        case PdfOk<Uint8List>(:final value):
          try {
            await thumbFile.parent.create(recursive: true);
            await thumbFile.writeAsBytes(value);
          } catch (e) {
            _thumbnailFailedOnce.add(docId);
            return const PdfOk(null);
          }
          await (_db.update(
            _db.documents,
          )..where((t) => t.id.equals(docId))).write(
            DocumentsCompanion(thumbPath: drift.Value(thumbPath)),
          );
          return PdfOk(thumbPath);
      }
    } finally {
      _releaseThumbnailSlot();
    }
  }

  Future<void> _acquireThumbnailSlot() async {
    if (_thumbnailActiveCount < _thumbnailConcurrencyLimit) {
      _thumbnailActiveCount++;
      return;
    }
    final completer = Completer<void>();
    _thumbnailWaitQueue.add(completer);
    await completer.future;
    _thumbnailActiveCount++;
  }

  void _releaseThumbnailSlot() {
    _thumbnailActiveCount--;
    if (_thumbnailWaitQueue.isNotEmpty) {
      _thumbnailWaitQueue.removeAt(0).complete();
    }
  }
}
