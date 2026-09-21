/// Drift 스키마. (설계 §6, 확정)
///
/// - `documents`/`pages`/`recent_files`/`settings` 4개 테이블.
/// - `pages.kind` 이원화(`image`|`pdf`)와 `source_index` null 제약을
///   SQL CHECK로 강제한다. `PageRef` ↔ DB 행 변환 함수에서도 assert로
///   이중 방어한다(`lib/data/repository/document_repository.dart`).
library;

import 'package:drift/drift.dart';

@TableIndex(
  name: 'idx_documents_updated_at',
  columns: {IndexedColumn(#updatedAt, orderBy: OrderingMode.desc)},
)
class Documents extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get origin => text()(); // scan|photo|imported
  IntColumn get pageCount => integer().named('page_count')();
  IntColumn get fileSize => integer().named('file_size')();
  IntColumn get createdAt => integer().named('created_at')(); // epoch ms
  IntColumn get updatedAt => integer().named('updated_at')();
  TextColumn get thumbPath => text().named('thumb_path').nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (origin IN ('scan','photo','imported'))",
  ];
}

@TableIndex(
  name: 'idx_pages_doc_order',
  unique: true,
  columns: {#docId, #orderIndex},
)
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get docId => text()
      .named('doc_id')
      .references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get orderIndex => integer().named('order_index')(); // 0-base
  TextColumn get kind => text()(); // image|pdf
  TextColumn get sourcePath => text().named('source_path')();
  IntColumn get sourceIndex => integer().named('source_index').nullable()();
  IntColumn get rotation => integer().withDefault(const Constant(0))();
  // schemaVersion 2 신설(`_workspace/36_architect_week3_design.md` §1·§2.3).
  // "l,t,r,b" 형식(CropRect.encode()) 또는 null. kind='image'일 때만 non-null일
  // 수 있다 — PDF 페이지는 크롭을 갖지 않는다(§2.2 판정).
  TextColumn get crop => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('image','pdf'))",
    "CHECK (rotation IN (0,90,180,270))",
    // kind 이원화 제약: pdf면 source_index 필수, image면 반드시 null
    "CHECK ((kind='pdf' AND source_index IS NOT NULL) OR "
        "(kind='image' AND source_index IS NULL))",
    // 신설(schemaVersion 2): PDF 페이지는 크롭을 가질 수 없다.
    "CHECK (kind='image' OR crop IS NULL)",
  ];
}

class RecentFiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().named('display_name')(); // 한글 원문
  TextColumn get copiedPath => text().named('copied_path')();
  IntColumn get openedAt => integer().named('opened_at')();
  IntColumn get size => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SettingsRows extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))(); // 항상 0
  TextColumn get defaultQuality => text()
      .named('default_quality')
      .withDefault(const Constant('standard'))();
  BoolColumn get adsRemoved =>
      boolean().named('ads_removed').withDefault(const Constant(false))();
  IntColumn get interstitialCountToday => integer()
      .named('interstitial_count_today')
      .withDefault(const Constant(0))();
  IntColumn get lastAdDate =>
      integer().named('last_ad_date').withDefault(const Constant(0))();

  // schemaVersion 4 → 5 (`_workspace/79_architect_v1.1_v2_design.md` §5.4,
  // `_workspace/82_spec-guardian_final_review.md` M1): 사용자가 고른 화면 테마.
  // 'system'/'light'/'dark' 3값만 유효. addColumn으로 추가되므로 아래 CHECK는
  // 기존 행에는 소급 적용되지 않는다 — 유효값 검증은 반드시
  // `settings_repository.dart`의 파싱 단계에서도 한다(알 수 없는 값 → 'system' 폴백).
  TextColumn get themeMode => text()
      .named('theme_mode')
      .withDefault(const Constant('system'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (id = 0)',
    "CHECK (theme_mode IN ('system','light','dark'))",
  ];
}

/// 편집 중이던 미저장 상태. **원본 진실은 여전히 파일이다** — 이 테이블은
/// "아직 파일이 되지 못한 작업"을 담는 유일한 예외이며, 저장이 성공하는 순간
/// 행과 `drafts/<id>/` 디렉터리가 함께 사라진다. (`_workspace/76_architect_design.md` §4.4)
@TableIndex(
  name: 'idx_edit_drafts_updated_at',
  columns: {IndexedColumn(#updatedAt, orderBy: OrderingMode.desc)},
)
class EditDrafts extends Table {
  TextColumn get id => text()(); // UUID v4 = draftId
  /// 편집 대상 출처. `router.dart`의 `EditSource`와 1:1 대응한다.
  TextColumn get sourceKind => text().named('source_kind')(); // my_document | external_pdf
  TextColumn get sourceDocId => text().named('source_doc_id').nullable()();
  TextColumn get sourcePdfPath => text().named('source_pdf_path').nullable()();
  TextColumn get sourceRecentId => text().named('source_recent_id').nullable()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get updatedAt => integer().named('updated_at')(); // epoch ms

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (source_kind IN ('my_document','external_pdf'))",
    "CHECK ((source_kind='my_document' AND source_doc_id IS NOT NULL "
        "AND source_pdf_path IS NULL) OR "
        "(source_kind='external_pdf' AND source_pdf_path IS NOT NULL "
        "AND source_doc_id IS NULL))",
  ];
}

/// 드래프트의 페이지 목록. `Pages`와 **같은 컬럼 구성 + 같은 CHECK**를 쓴다.
/// 다른 점은 `origin` 하나뿐이다. (§4.4)
@TableIndex(
  name: 'idx_draft_pages_draft_order',
  unique: true,
  columns: {#draftId, #orderIndex},
)
class EditDraftPages extends Table {
  TextColumn get id => text()();
  TextColumn get draftId => text()
      .named('draft_id')
      .references(EditDrafts, #id, onDelete: KeyAction.cascade)();
  IntColumn get orderIndex => integer().named('order_index')();
  TextColumn get kind => text()(); // image|pdf
  TextColumn get sourcePath => text().named('source_path')();
  IntColumn get sourceIndex => integer().named('source_index').nullable()();
  IntColumn get rotation => integer().withDefault(const Constant(0))();
  TextColumn get crop => text().nullable()();
  /// `EditPageOrigin`. 복구 후에도 `SizeGuard.classify`의 `before`를 재구성해야
  /// 하므로 반드시 보존한다 — 이 값이 없으면 저장 시 `SaveOp` 판정이 틀어진다.
  TextColumn get origin => text()(); // existing|added

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('image','pdf'))",
    "CHECK (rotation IN (0,90,180,270))",
    "CHECK ((kind='pdf' AND source_index IS NOT NULL) OR "
        "(kind='image' AND source_index IS NULL))",
    "CHECK (kind='image' OR crop IS NULL)",
    "CHECK (origin IN ('existing','added'))",
  ];
}

/// 드래프트 페이지에 얹힌 마크(형광펜·텍스트 상자·이미지). schemaVersion 4 신설
/// (`_workspace/79_architect_v1.1_v2_design.md` §6.3). 저장(굽기)이 성공하면
/// `EditDraftPages` cascade로 함께 사라진다 — 굽힌 결과는 PDF 안에만 남고
/// 이 테이블에는 남지 않는다(§6.2 "저장 후 재편집 불가").
@TableIndex(name: 'idx_draft_marks_page', columns: {#draftPageId})
class EditDraftMarks extends Table {
  TextColumn get id => text()();
  TextColumn get draftPageId => text()
      .named('draft_page_id')
      .references(EditDraftPages, #id, onDelete: KeyAction.cascade)();
  /// `StampMark`의 kind. `page_ref.dart`의 `kind` 규약과 같은 형식이다.
  TextColumn get kind => text()(); // image | highlight | text
  /// `StampRect.encode()` — "l,t,r,b" (`CropRect`와 **같은 직렬화 형식**. 두 번째 형식 금지)
  TextColumn get rect => text()();
  /// kind=image: `drafts/<draftId>/marks/NNN.png` 상대 경로. 그 외 null
  TextColumn get assetPath => text().named('asset_path').nullable()();
  /// kind=text: 본문. 그 외 null
  TextColumn get markText => text().named('text').nullable()();
  /// kind=highlight|text: ARGB. kind=image면 null
  IntColumn get colorArgb => integer().named('color_argb').nullable()();
  /// kind=highlight: 0.0~1.0(opacity). kind=text: fontSizePt. kind=image: null
  RealColumn get param => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('image','highlight','text'))",
    "CHECK ((kind='image' AND asset_path IS NOT NULL AND text IS NULL) OR "
        "(kind='text' AND text IS NOT NULL AND asset_path IS NULL) OR "
        "(kind='highlight' AND text IS NULL AND asset_path IS NULL))",
  ];
}
