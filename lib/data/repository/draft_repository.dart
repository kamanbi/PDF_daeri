/// 편집 드래프트("작업 중 상태") 저장소. (`_workspace/76_architect_design.md` §4.5·§4.6)
///
/// 화면도 `EditController`도 DB·파일을 직접 만지지 않는다 — 이 파일이 유일한 소유자다.
///
/// 핵심 결정 3가지(§4.5):
/// 1. adopt-at-insert — 임시 캐시 경로 이미지는 [DraftRepository.adoptImages]로
///    `drafts/<draftId>/pages/`에 즉시 복사한다. 저장 시점에 몰아서 복사하지 않는다.
/// 2. DB 쓰기 시점(dirty 판단·디바운스)은 호출자(§4.7 EditController/화면) 책임이다.
///    이 저장소는 "호출되면 저장한다"만 한다.
/// 3. 드래프트는 1개만 유지한다(Q7 승인 완료) — [save]는 다른 draftId의 기존 행·
///    디렉터리를 전부 제거한다.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../features/edit/edit_controller.dart' show EditPageOrigin;
import '../../pdf/page_ref.dart';
import '../../pdf/stamp_builder.dart' show StampMark, StampRect, ImageMark, HighlightMark, TextMark;
import '../db/app_database.dart';
import '../storage/workspace.dart';

/// 편집 대상의 출처. `router.dart`의 `EditSource`와 1:1 대응하지만, `lib/data/**`는
/// `lib/app/**`(라우팅)를 몰라야 하므로(레이어 경계) 이 파일이 자체적으로 선언한다
/// (`CompressSource`가 `document_repository.dart`에서 같은 이유로 자체 선언되는 것과 동일).
///
/// 구체 서브타입([MyDocumentEditSource]/[ExternalPdfEditSource])은 public이다 —
/// 소비자(화면 쪽)가 `switch (snapshot.source) { ... }`로 직접 분기해 자신의 타입
/// (예: `EditSource`)으로 변환할 수 있게 하기 위함이다. 이 파일은 `EditSource`를
/// import하거나 그 존재를 알지 않는다 — 변환은 소비자 책임이다.
sealed class EditSourceDescriptor {
  const EditSourceDescriptor();

  /// 내 문서. `DocumentRepository.load(docId)`로 페이지 목록을 복원할 수 있는 대상.
  const factory EditSourceDescriptor.myDocument(String docId) = MyDocumentEditSource;

  /// 외부에서 연 PDF(`recent/<id>.pdf` 등). `documents` 행이 없다.
  const factory EditSourceDescriptor.externalPdf({
    required String pdfPath,
    required String title,
    String? recentId,
  }) = ExternalPdfEditSource;
}

final class MyDocumentEditSource extends EditSourceDescriptor {
  const MyDocumentEditSource(this.docId);
  final String docId;
}

final class ExternalPdfEditSource extends EditSourceDescriptor {
  const ExternalPdfEditSource({
    required this.pdfPath,
    required this.title,
    this.recentId,
  });
  final String pdfPath;
  final String title;
  final String? recentId;
}

/// 드래프트의 페이지 1장. `origin`이 없으면 복구 후 `SizeGuard.classify`의 `before`를
/// 재구성할 수 없다(§4.7 참조) — 반드시 함께 저장·복원한다.
class DraftPageEntry {
  const DraftPageEntry({required this.ref, required this.origin, this.marks = const []});
  final PageRef ref;
  final EditPageOrigin origin;
  /// 이 페이지 위에 얹힌 주석(형광펜·텍스트 상자·이미지). `StampMark.kind=image`인
  /// 항목의 `ImageMark.pngBytes`는 **복구 시 항상 채워진다** — DB에는 경로만
  /// 저장되고(`asset_path`), 읽어들일 때 그 경로의 파일을 즉시 읽어 되돌린다
  /// (79 §6.3 — 임시 경로를 DB에 넣지 않는다는 결정 1과 일관되게, 스냅샷 소비자는
  /// 경로가 아니라 `StampMark` 값 타입만 본다).
  final List<StampMark> marks;
}

/// [DraftRepository.pending]이 돌려주는 복구용 스냅샷.
class DraftSnapshot {
  const DraftSnapshot({
    required this.draftId,
    required this.source,
    required this.title,
    required this.updatedAt,
    required this.pages,
  });

  final String draftId;
  final EditSourceDescriptor source;
  final String title;
  final DateTime updatedAt;

  /// 복구된 **현재 편집 상태**(order/rotation/crop 반영).
  final List<DraftPageEntry> pages;
}

/// 편집 드래프트의 단일 소유자.
abstract interface class DraftRepository {
  /// 복구 대상 드래프트. 없으면 null. 앱 시작 시 S1이 한 번 호출한다.
  /// 참조하는 소스 파일(내 문서의 document.pdf / recent/`id`.pdf)이 사라졌으면
  /// **드래프트를 조용히 폐기하고 null을 반환한다**(파일 기준 복구 원칙).
  Future<DraftSnapshot?> pending();

  /// [pages]는 `EditController.toPageRefs()`가 아니라 `EditPage` 목록을 그대로 받는다 —
  /// `origin`이 필요하다(§4.4). 호출은 디바운스된 뒤 한 번만 일어난다(호출자 책임).
  Future<void> save({
    required String draftId,
    required EditSourceDescriptor source,
    required String title,
    required List<DraftPageEntry> pages,
  });

  /// 임시 경로의 이미지들을 `drafts/<draftId>/pages/`로 복사하고 새 경로를 반환한다.
  /// 실패한 항목은 결과에서 제외한다(부분 성공 허용 — 스캔 1장 실패로 편집 전체가
  /// 날아가면 안 된다).
  Future<List<String>> adoptImages(String draftId, List<String> tempImagePaths);

  /// 마크 이미지(형광펜 스트로크가 래스터화되는 경우 등)를 `drafts/<draftId>/marks/`로
  /// 복사하고 새 경로를 반환한다. [adoptImages]와 **같은 규약**(부분 성공 허용) —
  /// 실패한 항목은 결과에서 제외한다. (79 §6.3)
  Future<List<String>> adoptMarkAssets(String draftId, List<Uint8List> pngBytesList);

  Future<void> discard(String draftId);

  /// 부팅 시 1회. DB 행 없는 `drafts/*` 디렉터리 + 소스가 사라진 행을 정리한다.
  Future<void> reconcile();
}

class DriftDraftRepository implements DraftRepository {
  DriftDraftRepository({required this._db, required this._workspace, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Workspace _workspace;
  final Uuid _uuid;

  @override
  Future<DraftSnapshot?> pending() async {
    final row = await (_db.select(_db.editDrafts)
          ..orderBy([
            (t) => drift.OrderingTerm(expression: t.updatedAt, mode: drift.OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;

    final source = _sourceFromRow(row);
    if (!await _sourceFileExists(source)) {
      // 파일 기준 복구 원칙: 참조 대상이 사라졌으면 드래프트 자체가 의미 없다.
      await discard(row.id);
      return null;
    }

    final pageRows =
        await (_db.select(_db.editDraftPages)
              ..where((t) => t.draftId.equals(row.id))
              ..orderBy([(t) => drift.OrderingTerm(expression: t.orderIndex)]))
            .get();

    final pages = <DraftPageEntry>[];
    for (final pageRow in pageRows) {
      final markRows = await (_db.select(_db.editDraftMarks)
            ..where((t) => t.draftPageId.equals(pageRow.id)))
          .get();
      final marks = <StampMark>[];
      for (final markRow in markRows) {
        marks.add(await _markRowToStampMark(markRow));
      }
      pages.add(_draftPageRowToEntry(pageRow, marks));
    }

    return DraftSnapshot(
      draftId: row.id,
      source: source,
      title: row.title,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      pages: pages,
    );
  }

  @override
  Future<void> save({
    required String draftId,
    required EditSourceDescriptor source,
    required String title,
    required List<DraftPageEntry> pages,
  }) async {
    await _db.transaction(() async {
      // 결정 3(Q7): 드래프트는 1개만 유지한다. 이번 draftId와 다른 기존 드래프트가
      // 있으면 행·디렉터리를 전부 제거한다.
      final existing = await _db.select(_db.editDrafts).get();
      for (final row in existing) {
        if (row.id == draftId) continue;
        await (_db.delete(_db.editDrafts)..where((t) => t.id.equals(row.id))).go();
        await _workspace.discardDraft(row.id);
      }

      final columns = _sourceToColumns(source);
      await _db
          .into(_db.editDrafts)
          .insertOnConflictUpdate(
            EditDraftsCompanion.insert(
              id: draftId,
              sourceKind: columns.kind,
              sourceDocId: drift.Value(columns.docId),
              sourcePdfPath: drift.Value(columns.pdfPath),
              sourceRecentId: drift.Value(columns.recentId),
              title: title,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      // cascade(`EditDraftMarks.draftPageId → EditDraftPages.id`)가 마크 행도 함께 지운다.
      await (_db.delete(_db.editDraftPages)..where((t) => t.draftId.equals(draftId))).go();
      for (var i = 0; i < pages.length; i++) {
        final pageId = _uuid.v4();
        await _db
            .into(_db.editDraftPages)
            .insert(_draftPageToCompanion(pageId, draftId, i, pages[i]));
        for (final mark in pages[i].marks) {
          final companion = await _markToCompanion(_uuid.v4(), pageId, draftId, mark);
          if (companion == null) continue; // ImageMark 내구 사본 쓰기 실패 — 부분 성공 허용.
          await _db.into(_db.editDraftMarks).insert(companion);
        }
      }
    });
  }

  @override
  Future<List<String>> adoptImages(String draftId, List<String> tempImagePaths) async {
    if (tempImagePaths.isEmpty) return const [];
    await _workspace.beginDraft(draftId);

    var next = await _nextImageIndex(draftId);
    final adopted = <String>[];
    for (final tempPath in tempImagePaths) {
      final destPath = _workspace.draftImage(draftId, next);
      try {
        await File(tempPath).copy(destPath);
        adopted.add(destPath);
        next++;
      } catch (_) {
        // 부분 성공 허용(§4.6) — 실패한 항목은 결과에서 제외한다.
      }
    }
    return adopted;
  }

  Future<int> _nextImageIndex(String draftId) async {
    final dir = Directory(p.join(_workspace.draftDir(draftId), 'pages'));
    if (!await dir.exists()) return 0;
    var maxIndex = -1;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final n = int.tryParse(p.basenameWithoutExtension(entity.path));
      if (n != null && n > maxIndex) maxIndex = n;
    }
    return maxIndex + 1;
  }

  @override
  Future<List<String>> adoptMarkAssets(String draftId, List<Uint8List> pngBytesList) async {
    // adopt-at-insert(76 §4.5 결정 1) 재사용 — 마크 생성 즉시 내구 경로로 복사한다.
    // 임시 경로를 DB에 넣지 않는다.
    if (pngBytesList.isEmpty) return const [];
    await _workspace.beginDraftMarks(draftId);

    var next = await _nextMarkIndex(draftId);
    final adopted = <String>[];
    for (final bytes in pngBytesList) {
      final destPath = _workspace.draftMarkImage(draftId, next);
      try {
        await File(destPath).writeAsBytes(bytes, flush: true);
        adopted.add(destPath);
        next++;
      } catch (_) {
        // 부분 성공 허용(adoptImages와 같은 규약) — 실패한 항목은 결과에서 제외한다.
      }
    }
    return adopted;
  }

  Future<int> _nextMarkIndex(String draftId) async {
    final dir = Directory(p.join(_workspace.draftDir(draftId), 'marks'));
    if (!await dir.exists()) return 0;
    var maxIndex = -1;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final n = int.tryParse(p.basenameWithoutExtension(entity.path));
      if (n != null && n > maxIndex) maxIndex = n;
    }
    return maxIndex + 1;
  }

  @override
  Future<void> discard(String draftId) async {
    await (_db.delete(_db.editDraftPages)..where((t) => t.draftId.equals(draftId))).go();
    await (_db.delete(_db.editDrafts)..where((t) => t.id.equals(draftId))).go();
    await _workspace.discardDraft(draftId);
  }

  @override
  Future<void> reconcile() async {
    final rows = await _db.select(_db.editDrafts).get();
    final liveIds = <String>{};
    for (final row in rows) {
      final source = _sourceFromRow(row);
      if (await _sourceFileExists(source)) {
        liveIds.add(row.id);
      } else {
        await discard(row.id);
      }
    }
    await _workspace.purgeOrphanDrafts(liveIds);
  }

  // --- 변환 헬퍼 ---

  EditSourceDescriptor _sourceFromRow(EditDraft row) {
    if (row.sourceKind == 'my_document') {
      return EditSourceDescriptor.myDocument(row.sourceDocId!);
    }
    return EditSourceDescriptor.externalPdf(
      pdfPath: row.sourcePdfPath!,
      title: row.title,
      recentId: row.sourceRecentId,
    );
  }

  Future<bool> _sourceFileExists(EditSourceDescriptor source) => switch (source) {
    MyDocumentEditSource(:final docId) => File(_workspace.docPdf(docId)).exists(),
    ExternalPdfEditSource(:final pdfPath) => File(pdfPath).exists(),
  };

  ({String kind, String? docId, String? pdfPath, String? recentId}) _sourceToColumns(
    EditSourceDescriptor source,
  ) => switch (source) {
    MyDocumentEditSource(:final docId) => (
      kind: 'my_document',
      docId: docId,
      pdfPath: null,
      recentId: null,
    ),
    ExternalPdfEditSource(:final pdfPath, :final recentId) => (
      kind: 'external_pdf',
      docId: null,
      pdfPath: pdfPath,
      recentId: recentId,
    ),
  };

  EditDraftPagesCompanion _draftPageToCompanion(
    String id,
    String draftId,
    int orderIndex,
    DraftPageEntry entry,
  ) {
    final origin = entry.origin == EditPageOrigin.existing ? 'existing' : 'added';
    return switch (entry.ref) {
      ImagePageRef(:final imagePath, :final rotation, :final crop) => EditDraftPagesCompanion.insert(
        id: id,
        draftId: draftId,
        orderIndex: orderIndex,
        kind: 'image',
        sourcePath: imagePath,
        rotation: drift.Value(rotation),
        crop: drift.Value(crop?.encode()),
        origin: origin,
      ),
      PdfPageRef(:final sourcePath, :final sourceIndex, :final rotation) =>
        EditDraftPagesCompanion.insert(
          id: id,
          draftId: draftId,
          orderIndex: orderIndex,
          kind: 'pdf',
          sourcePath: sourcePath,
          sourceIndex: drift.Value(sourceIndex),
          rotation: drift.Value(rotation),
          // PdfPageRef는 크롭을 갖지 않는다(§2.2 판정, document_repository.dart와 동일 규약).
          crop: const drift.Value(null),
          origin: origin,
        ),
    };
  }

  DraftPageEntry _draftPageRowToEntry(EditDraftPage row, List<StampMark> marks) {
    assert(
      (row.kind == 'pdf' && row.sourceIndex != null) ||
          (row.kind == 'image' && row.sourceIndex == null),
      'kind/source_index 조합 위반: ${row.kind}/${row.sourceIndex} (draft=${row.draftId})',
    );
    final ref = switch (row.kind) {
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
      _ => throw StateError('unknown draft page kind: ${row.kind} (draft=${row.draftId})'),
    };
    final origin = row.origin == 'existing' ? EditPageOrigin.existing : EditPageOrigin.added;
    return DraftPageEntry(ref: ref, origin: origin, marks: marks);
  }

  /// `null`을 반환하면 호출자가 그 마크를 건너뛴다(부분 성공 허용 — `adoptImages`/
  /// `adoptMarkAssets`와 같은 규약). `ImageMark`는 [pngBytes]를 그대로 컬럼에 넣지
  /// 않는다 — DB에는 `asset_path`만 저장하므로(§6.3), 저장 시점에 [adoptMarkAssets]로
  /// `drafts/<draftId>/marks/`에 내구 사본을 만들고 그 경로를 넣는다(결정 1 재사용).
  Future<EditDraftMarksCompanion?> _markToCompanion(
    String id,
    String draftPageId,
    String draftId,
    StampMark mark,
  ) async {
    switch (mark) {
      case ImageMark(:final rect, :final pngBytes):
        final adopted = await adoptMarkAssets(draftId, [pngBytes]);
        if (adopted.isEmpty) return null;
        return EditDraftMarksCompanion.insert(
          id: id,
          draftPageId: draftPageId,
          kind: 'image',
          rect: rect.encode(),
          assetPath: drift.Value(adopted.single),
        );
      case HighlightMark(:final rect, :final colorArgb, :final opacity):
        return EditDraftMarksCompanion.insert(
          id: id,
          draftPageId: draftPageId,
          kind: 'highlight',
          rect: rect.encode(),
          colorArgb: drift.Value(colorArgb),
          param: drift.Value(opacity),
        );
      case TextMark(:final rect, :final text, :final fontSizePt, :final colorArgb):
        return EditDraftMarksCompanion.insert(
          id: id,
          draftPageId: draftPageId,
          kind: 'text',
          rect: rect.encode(),
          markText: drift.Value(text),
          colorArgb: drift.Value(colorArgb),
          param: drift.Value(fontSizePt),
        );
    }
  }

  Future<StampMark> _markRowToStampMark(EditDraftMark row) async {
    final rect = StampRect.decode(row.rect);
    switch (row.kind) {
      case 'image':
        final bytes = await File(row.assetPath!).readAsBytes();
        return ImageMark(rect: rect, pngBytes: bytes);
      case 'highlight':
        return HighlightMark(rect: rect, colorArgb: row.colorArgb!, opacity: row.param!);
      case 'text':
        return TextMark(
          rect: rect,
          text: row.markText!,
          fontSizePt: row.param!,
          colorArgb: row.colorArgb!,
        );
      default:
        throw StateError('unknown draft mark kind: ${row.kind} (id=${row.id})');
    }
  }
}
