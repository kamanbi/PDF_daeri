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

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 0)'];
}
