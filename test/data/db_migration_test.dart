/// schemaVersion 1 → 2 마이그레이션 테스트. (Q-W10 · `_workspace/36_architect_week3_design.md` §2.3)
///
/// 실기기에 이전 버전(schemaVersion 1, `pages.crop` 컬럼 없음) 데이터가 남아
/// 있는 상황을 재현한다: 원시 SQL로 v1 스키마의 DB 파일을 직접 만들고 행을
/// 심은 뒤, 앱이 실제로 여는 것과 동일한 `AppDatabase.open()`으로 다시 열어
/// `onUpgrade`가 `pages.crop` 컬럼을 추가하고 기존 데이터를 보존하는지 확인한다.
library;

import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/data/db/app_database.dart';
import 'package:pdf_daeri/data/repository/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late String dbPath;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_migration_test_');
    dbPath = p.join(tempRoot.path, 'app.db');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// v1 스키마(현행 `pages.crop` 컬럼 신설 이전)로 DB 파일을 만들고 문서 1건 +
  /// 페이지 2건(이미지 1 · pdf 1)을 심는다. `PRAGMA user_version = 1`을 명시해
  /// drift가 "이미 schemaVersion 1로 열렸던 적 있는 DB"로 인식하게 한다.
  void seedV1Database() {
    final raw = sqlite3.sqlite3.open(dbPath);
    try {
      raw.execute('''
        CREATE TABLE documents (
          id TEXT NOT NULL PRIMARY KEY,
          title TEXT NOT NULL,
          origin TEXT NOT NULL,
          page_count INTEGER NOT NULL,
          file_size INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          thumb_path TEXT NULL,
          CHECK (origin IN ('scan','photo','imported'))
        );
      ''');
      raw.execute('''
        CREATE TABLE pages (
          id TEXT NOT NULL PRIMARY KEY,
          doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
          order_index INTEGER NOT NULL,
          kind TEXT NOT NULL,
          source_path TEXT NOT NULL,
          source_index INTEGER NULL,
          rotation INTEGER NOT NULL DEFAULT 0,
          CHECK (kind IN ('image','pdf')),
          CHECK (rotation IN (0,90,180,270)),
          CHECK ((kind='pdf' AND source_index IS NOT NULL) OR (kind='image' AND source_index IS NULL))
        );
      ''');
      raw.execute('''
        CREATE TABLE recent_files (
          id TEXT NOT NULL PRIMARY KEY,
          display_name TEXT NOT NULL,
          copied_path TEXT NOT NULL,
          opened_at INTEGER NOT NULL,
          size INTEGER NOT NULL
        );
      ''');
      raw.execute('''
        CREATE TABLE settings_rows (
          id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
          default_quality TEXT NOT NULL DEFAULT 'standard',
          ads_removed INTEGER NOT NULL DEFAULT 0,
          interstitial_count_today INTEGER NOT NULL DEFAULT 0,
          last_ad_date INTEGER NOT NULL DEFAULT 0,
          CHECK (id = 0)
        );
      ''');

      raw.execute('''
        INSERT INTO documents (id, title, origin, page_count, file_size, created_at, updated_at, thumb_path)
        VALUES ('doc-1', '2026년 8월 보고서 (최종)', 'imported', 2, 1000, 111, 111, NULL);
      ''');
      raw.execute('''
        INSERT INTO pages (id, doc_id, order_index, kind, source_path, source_index, rotation)
        VALUES ('page-1', 'doc-1', 0, 'image', '/sources/pages/001.jpg', NULL, 0);
      ''');
      raw.execute('''
        INSERT INTO pages (id, doc_id, order_index, kind, source_path, source_index, rotation)
        VALUES ('page-2', 'doc-1', 1, 'pdf', '/sources/src_1.pdf', 3, 90);
      ''');

      raw.execute('PRAGMA user_version = 1;');
    } finally {
      raw.dispose();
    }
  }

  test('v1 DB를 열면 onUpgrade가 pages.crop 컬럼을 추가한다', () async {
    seedV1Database();

    final db = AppDatabase.open(tempRoot.path);
    try {
      // 마이그레이션이 실제로 실행되도록 쿼리 1개를 던진다(LazyDatabase는 지연 연결).
      final rows = await db.select(db.pages).get();
      expect(rows, hasLength(2), reason: '기존 페이지 2건이 보존되어야 한다');

      // PRAGMA table_info로 crop 컬럼이 물리적으로 추가됐는지 직접 확인한다.
      final columns = await db
          .customSelect('PRAGMA table_info(pages)')
          .get();
      final columnNames = columns.map((r) => r.data['name'] as String).toSet();
      expect(columnNames, contains('crop'));
    } finally {
      await db.close();
    }
  });

  test('마이그레이션 후 기존 행의 crop은 NULL(크롭 없음과 동일 의미)이다', () async {
    seedV1Database();

    final db = AppDatabase.open(tempRoot.path);
    try {
      final rows = await db.select(db.pages).get();
      for (final row in rows) {
        expect(row.crop, isNull, reason: '기존 페이지는 크롭이 없었으므로 null로 남아야 한다(백필 불필요)');
      }

      // 원본 데이터(한글 제목 포함)가 훼손되지 않았는지도 함께 확인.
      final doc = await db.select(db.documents).getSingle();
      expect(doc.title, '2026년 8월 보고서 (최종)');
    } finally {
      await db.close();
    }
  });

  test('마이그레이션 후 새 이미지 페이지에는 crop 값을 저장·조회할 수 있다', () async {
    seedV1Database();

    final db = AppDatabase.open(tempRoot.path);
    try {
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              id: 'page-3',
              docId: 'doc-1',
              orderIndex: 2,
              kind: 'image',
              sourcePath: '/sources/pages/003.jpg',
              rotation: const drift.Value(0),
              crop: const drift.Value('0.1,0.1,0.9,0.9'),
            ),
          );

      final row = await (db.select(db.pages)..where((t) => t.id.equals('page-3'))).getSingle();
      expect(row.crop, '0.1,0.1,0.9,0.9');
    } finally {
      await db.close();
    }
  });

  test('schemaVersion은 5이다', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 5);
    await db.close();
  });

  group('schemaVersion 2 → 3 (§76 §4.4, 편집 드래프트 테이블 신설)', () {
    /// v2 스키마(pages.crop은 있으나 editDrafts/editDraftPages는 없음)로 DB 파일을
    /// 만들고 문서 1건을 심는다. `PRAGMA user_version = 2`로 "schemaVersion 2로
    /// 열렸던 적 있는 DB"임을 명시한다.
    void seedV2Database() {
      final raw = sqlite3.sqlite3.open(dbPath);
      try {
        raw.execute('''
          CREATE TABLE documents (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            origin TEXT NOT NULL,
            page_count INTEGER NOT NULL,
            file_size INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            thumb_path TEXT NULL,
            CHECK (origin IN ('scan','photo','imported'))
          );
        ''');
        raw.execute('''
          CREATE TABLE pages (
            id TEXT NOT NULL PRIMARY KEY,
            doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            order_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            source_path TEXT NOT NULL,
            source_index INTEGER NULL,
            rotation INTEGER NOT NULL DEFAULT 0,
            crop TEXT NULL,
            CHECK (kind IN ('image','pdf')),
            CHECK (rotation IN (0,90,180,270)),
            CHECK ((kind='pdf' AND source_index IS NOT NULL) OR (kind='image' AND source_index IS NULL))
          );
        ''');
        raw.execute('''
          CREATE TABLE recent_files (
            id TEXT NOT NULL PRIMARY KEY,
            display_name TEXT NOT NULL,
            copied_path TEXT NOT NULL,
            opened_at INTEGER NOT NULL,
            size INTEGER NOT NULL
          );
        ''');
        raw.execute('''
          CREATE TABLE settings_rows (
            id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
            default_quality TEXT NOT NULL DEFAULT 'standard',
            ads_removed INTEGER NOT NULL DEFAULT 0,
            interstitial_count_today INTEGER NOT NULL DEFAULT 0,
            last_ad_date INTEGER NOT NULL DEFAULT 0,
            CHECK (id = 0)
          );
        ''');

        raw.execute('''
          INSERT INTO documents (id, title, origin, page_count, file_size, created_at, updated_at, thumb_path)
          VALUES ('doc-1', '2026년 8월 보고서 (최종)', 'imported', 1, 1000, 111, 111, NULL);
        ''');
        raw.execute('''
          INSERT INTO pages (id, doc_id, order_index, kind, source_path, source_index, rotation, crop)
          VALUES ('page-1', 'doc-1', 0, 'image', '/sources/pages/001.jpg', NULL, 0, NULL);
        ''');

        raw.execute('PRAGMA user_version = 2;');
      } finally {
        raw.dispose();
      }
    }

    test('v2 DB를 열면 onUpgrade가 editDrafts/editDraftPages 테이블을 만든다', () async {
      seedV2Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        // 마이그레이션이 실제로 실행되도록 쿼리 1개를 던진다(LazyDatabase는 지연 연결).
        final docs = await db.select(db.documents).get();
        expect(docs, hasLength(1), reason: '기존 문서 1건이 보존되어야 한다');

        final tableNames = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table'",
            )
            .get();
        final names = tableNames.map((r) => r.data['name'] as String).toSet();
        expect(names, containsAll(['edit_drafts', 'edit_draft_pages']));
      } finally {
        await db.close();
      }
    });

    test('마이그레이션 후 새 드래프트 행을 저장·조회할 수 있다', () async {
      seedV2Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        await db
            .into(db.editDrafts)
            .insert(
              EditDraftsCompanion.insert(
                id: 'draft-1',
                sourceKind: 'my_document',
                sourceDocId: const drift.Value('doc-1'),
                title: '드래프트 제목',
                updatedAt: 222,
              ),
            );

        final row = await (db.select(
          db.editDrafts,
        )..where((t) => t.id.equals('draft-1'))).getSingle();
        expect(row.sourceDocId, 'doc-1');
        expect(row.title, '드래프트 제목');
      } finally {
        await db.close();
      }
    });
  });

  group('schemaVersion 3 → 4 (T12 — 79 §6.3, 드래프트 마크 테이블 신설)', () {
    /// v3 스키마(editDrafts/editDraftPages는 있으나 editDraftMarks는 없음)로 DB 파일을
    /// 만들고 드래프트 1건 + 페이지 1건을 심는다. `PRAGMA user_version = 3`으로
    /// "schemaVersion 3으로 열렸던 적 있는 DB"임을 명시한다.
    void seedV3Database() {
      final raw = sqlite3.sqlite3.open(dbPath);
      try {
        raw.execute('''
          CREATE TABLE documents (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            origin TEXT NOT NULL,
            page_count INTEGER NOT NULL,
            file_size INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            thumb_path TEXT NULL,
            CHECK (origin IN ('scan','photo','imported'))
          );
        ''');
        raw.execute('''
          CREATE TABLE pages (
            id TEXT NOT NULL PRIMARY KEY,
            doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            order_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            source_path TEXT NOT NULL,
            source_index INTEGER NULL,
            rotation INTEGER NOT NULL DEFAULT 0,
            crop TEXT NULL,
            CHECK (kind IN ('image','pdf')),
            CHECK (rotation IN (0,90,180,270)),
            CHECK ((kind='pdf' AND source_index IS NOT NULL) OR (kind='image' AND source_index IS NULL))
          );
        ''');
        raw.execute('''
          CREATE TABLE recent_files (
            id TEXT NOT NULL PRIMARY KEY,
            display_name TEXT NOT NULL,
            copied_path TEXT NOT NULL,
            opened_at INTEGER NOT NULL,
            size INTEGER NOT NULL
          );
        ''');
        raw.execute('''
          CREATE TABLE settings_rows (
            id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
            default_quality TEXT NOT NULL DEFAULT 'standard',
            ads_removed INTEGER NOT NULL DEFAULT 0,
            interstitial_count_today INTEGER NOT NULL DEFAULT 0,
            last_ad_date INTEGER NOT NULL DEFAULT 0,
            CHECK (id = 0)
          );
        ''');
        raw.execute('''
          CREATE TABLE edit_drafts (
            id TEXT NOT NULL PRIMARY KEY,
            source_kind TEXT NOT NULL,
            source_doc_id TEXT NULL,
            source_pdf_path TEXT NULL,
            source_recent_id TEXT NULL,
            title TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            CHECK (source_kind IN ('my_document','external_pdf')),
            CHECK ((source_kind='my_document' AND source_doc_id IS NOT NULL AND source_pdf_path IS NULL) OR
                   (source_kind='external_pdf' AND source_pdf_path IS NOT NULL AND source_doc_id IS NULL))
          );
        ''');
        raw.execute('''
          CREATE TABLE edit_draft_pages (
            id TEXT NOT NULL PRIMARY KEY,
            draft_id TEXT NOT NULL REFERENCES edit_drafts(id) ON DELETE CASCADE,
            order_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            source_path TEXT NOT NULL,
            source_index INTEGER NULL,
            rotation INTEGER NOT NULL DEFAULT 0,
            crop TEXT NULL,
            origin TEXT NOT NULL,
            CHECK (kind IN ('image','pdf')),
            CHECK (rotation IN (0,90,180,270)),
            CHECK ((kind='pdf' AND source_index IS NOT NULL) OR (kind='image' AND source_index IS NULL)),
            CHECK (origin IN ('existing','added'))
          );
        ''');

        raw.execute('''
          INSERT INTO documents (id, title, origin, page_count, file_size, created_at, updated_at, thumb_path)
          VALUES ('doc-1', '2026년 8월 보고서 (최종)', 'imported', 1, 1000, 111, 111, NULL);
        ''');
        raw.execute('''
          INSERT INTO edit_drafts (id, source_kind, source_doc_id, title, updated_at)
          VALUES ('draft-1', 'my_document', 'doc-1', '드래프트 제목', 222);
        ''');
        raw.execute('''
          INSERT INTO edit_draft_pages
            (id, draft_id, order_index, kind, source_path, source_index, rotation, crop, origin)
          VALUES
            ('dp-1', 'draft-1', 0, 'image', '/drafts/draft-1/pages/000.jpg', NULL, 0, NULL, 'existing');
        ''');

        raw.execute('PRAGMA user_version = 3;');
      } finally {
        raw.dispose();
      }
    }

    test('v3 DB를 열면 onUpgrade가 edit_draft_marks 테이블을 만든다', () async {
      seedV3Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        // 마이그레이션이 실제로 실행되도록 쿼리 1개를 던진다(LazyDatabase는 지연 연결).
        final drafts = await db.select(db.editDrafts).get();
        expect(drafts, hasLength(1), reason: '기존 드래프트 1건이 보존되어야 한다');

        final tableNames = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get();
        final names = tableNames.map((r) => r.data['name'] as String).toSet();
        expect(names, contains('edit_draft_marks'));
      } finally {
        await db.close();
      }
    });

    test('마이그레이션 후 기존 드래프트 페이지가 보존된다', () async {
      seedV3Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        final pages = await db.select(db.editDraftPages).get();
        expect(pages, hasLength(1));
        expect(pages.single.sourcePath, '/drafts/draft-1/pages/000.jpg');
      } finally {
        await db.close();
      }
    });

    test('마이그레이션 후 새 마크 행(highlight/text/image)을 저장·조회할 수 있다', () async {
      seedV3Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        await db
            .into(db.editDraftMarks)
            .insert(
              EditDraftMarksCompanion.insert(
                id: 'mark-1',
                draftPageId: 'dp-1',
                kind: 'highlight',
                rect: '0.1,0.1,0.5,0.2',
                colorArgb: const drift.Value(0xFFFFFF00),
                param: const drift.Value(0.35),
              ),
            );
        await db
            .into(db.editDraftMarks)
            .insert(
              EditDraftMarksCompanion.insert(
                id: 'mark-2',
                draftPageId: 'dp-1',
                kind: 'text',
                rect: '0.1,0.3,0.9,0.4',
                markText: const drift.Value('2026년 8월 보고서 (최종)'),
                colorArgb: const drift.Value(0xFF000000),
                param: const drift.Value(14.0),
              ),
            );

        final rows =
            await (db.select(db.editDraftMarks)
                  ..where((t) => t.draftPageId.equals('dp-1')))
                .get();
        expect(rows, hasLength(2));
        final highlight = rows.firstWhere((r) => r.kind == 'highlight');
        expect(highlight.rect, '0.1,0.1,0.5,0.2');
        expect(highlight.colorArgb, 0xFFFFFF00);
        expect(highlight.param, 0.35);
        final text = rows.firstWhere((r) => r.kind == 'text');
        expect(text.markText, '2026년 8월 보고서 (최종)');
      } finally {
        await db.close();
      }
    });

    test('드래프트 페이지 삭제 시 마크가 cascade로 함께 삭제된다', () async {
      seedV3Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        await db
            .into(db.editDraftMarks)
            .insert(
              EditDraftMarksCompanion.insert(
                id: 'mark-1',
                draftPageId: 'dp-1',
                kind: 'highlight',
                rect: '0.1,0.1,0.5,0.2',
                colorArgb: const drift.Value(0xFFFFFF00),
                param: const drift.Value(0.35),
              ),
            );

        await (db.delete(db.editDraftPages)..where((t) => t.id.equals('dp-1'))).go();

        final rows = await db.select(db.editDraftMarks).get();
        expect(rows, isEmpty, reason: 'EditDraftMarks.draftPageId → EditDraftPages.id cascade');
      } finally {
        await db.close();
      }
    });
  });

  group('schemaVersion 4 → 5 (T12/T13 — 82 최종검증 M1, theme_mode 컬럼 신설)', () {
    /// v4 스키마(edit_draft_marks까지는 있으나 settings_rows.theme_mode는 없음)로
    /// DB 파일을 만들고 문서 1건을 심는다. `PRAGMA user_version = 4`로 "schemaVersion 4로
    /// 열렸던 적 있는 DB"임을 명시한다.
    void seedV4Database() {
      final raw = sqlite3.sqlite3.open(dbPath);
      try {
        raw.execute('''
          CREATE TABLE documents (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            origin TEXT NOT NULL,
            page_count INTEGER NOT NULL,
            file_size INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            thumb_path TEXT NULL,
            CHECK (origin IN ('scan','photo','imported'))
          );
        ''');
        raw.execute('''
          CREATE TABLE pages (
            id TEXT NOT NULL PRIMARY KEY,
            doc_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            order_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            source_path TEXT NOT NULL,
            source_index INTEGER NULL,
            rotation INTEGER NOT NULL DEFAULT 0,
            crop TEXT NULL,
            CHECK (kind IN ('image','pdf')),
            CHECK (rotation IN (0,90,180,270)),
            CHECK ((kind='pdf' AND source_index IS NOT NULL) OR (kind='image' AND source_index IS NULL))
          );
        ''');
        raw.execute('''
          CREATE TABLE recent_files (
            id TEXT NOT NULL PRIMARY KEY,
            display_name TEXT NOT NULL,
            copied_path TEXT NOT NULL,
            opened_at INTEGER NOT NULL,
            size INTEGER NOT NULL
          );
        ''');
        raw.execute('''
          CREATE TABLE settings_rows (
            id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
            default_quality TEXT NOT NULL DEFAULT 'standard',
            ads_removed INTEGER NOT NULL DEFAULT 0,
            interstitial_count_today INTEGER NOT NULL DEFAULT 0,
            last_ad_date INTEGER NOT NULL DEFAULT 0,
            CHECK (id = 0)
          );
        ''');
        raw.execute('''
          CREATE TABLE edit_drafts (
            id TEXT NOT NULL PRIMARY KEY,
            source_kind TEXT NOT NULL,
            source_doc_id TEXT NULL,
            source_pdf_path TEXT NULL,
            source_recent_id TEXT NULL,
            title TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            CHECK (source_kind IN ('my_document','external_pdf')),
            CHECK ((source_kind='my_document' AND source_doc_id IS NOT NULL AND source_pdf_path IS NULL) OR
                   (source_kind='external_pdf' AND source_pdf_path IS NOT NULL AND source_doc_id IS NULL))
          );
        ''');
        raw.execute('''
          CREATE TABLE edit_draft_pages (
            id TEXT NOT NULL PRIMARY KEY,
            draft_id TEXT NOT NULL REFERENCES edit_drafts(id) ON DELETE CASCADE,
            order_index INTEGER NOT NULL,
            kind TEXT NOT NULL,
            source_path TEXT NOT NULL,
            source_index INTEGER NULL,
            rotation INTEGER NOT NULL DEFAULT 0,
            crop TEXT NULL,
            origin TEXT NOT NULL,
            CHECK (kind IN ('image','pdf')),
            CHECK (rotation IN (0,90,180,270)),
            CHECK ((kind='pdf' AND source_index IS NOT NULL) OR (kind='image' AND source_index IS NULL)),
            CHECK (origin IN ('existing','added'))
          );
        ''');
        raw.execute('''
          CREATE TABLE edit_draft_marks (
            id TEXT NOT NULL PRIMARY KEY,
            draft_page_id TEXT NOT NULL REFERENCES edit_draft_pages(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            rect TEXT NOT NULL,
            asset_path TEXT NULL,
            text TEXT NULL,
            color_argb INTEGER NULL,
            param REAL NULL,
            CHECK (kind IN ('image','highlight','text')),
            CHECK ((kind='image' AND asset_path IS NOT NULL AND text IS NULL) OR
                   (kind='text' AND text IS NOT NULL AND asset_path IS NULL) OR
                   (kind='highlight' AND text IS NULL AND asset_path IS NULL))
          );
        ''');

        raw.execute('''
          INSERT INTO documents (id, title, origin, page_count, file_size, created_at, updated_at, thumb_path)
          VALUES ('doc-1', '2026년 8월 보고서 (최종)', 'imported', 1, 1000, 111, 111, NULL);
        ''');
        raw.execute('''
          INSERT INTO settings_rows (id, default_quality, ads_removed, interstitial_count_today, last_ad_date)
          VALUES (0, 'high', 0, 0, 0);
        ''');

        raw.execute('PRAGMA user_version = 4;');
      } finally {
        raw.dispose();
      }
    }

    test('v4 DB를 열면 onUpgrade가 settings_rows.theme_mode 컬럼을 추가한다', () async {
      seedV4Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        // 마이그레이션이 실제로 실행되도록 쿼리 1개를 던진다(LazyDatabase는 지연 연결).
        final docs = await db.select(db.documents).get();
        expect(docs, hasLength(1), reason: '기존 문서 1건이 보존되어야 한다');

        final columns = await db
            .customSelect('PRAGMA table_info(settings_rows)')
            .get();
        final columnNames = columns.map((r) => r.data['name'] as String).toSet();
        expect(columnNames, contains('theme_mode'));
      } finally {
        await db.close();
      }
    });

    test('마이그레이션 후 기존 settings 행의 theme_mode는 기본값 system이다', () async {
      seedV4Database();

      final db = AppDatabase.open(tempRoot.path);
      try {
        final row = await (db.select(
          db.settingsRows,
        )..where((t) => t.id.equals(0))).getSingle();
        expect(row.themeMode, 'system', reason: 'addColumn 기본값은 §5.4대로 system');
        // 마이그레이션 이전 값(default_quality 등)도 훼손되지 않았는지 함께 확인.
        expect(row.defaultQuality, 'high');
      } finally {
        await db.close();
      }
    });

    test(
      'T13: DB에 미지값이 들어 있어도 SettingsRepository가 system으로 폴백하고 크래시하지 않는다',
      () async {
        seedV4Database();

        // 마이그레이션이 실제로 실행되도록 한 번 열었다 닫는다.
        final upgradeDb = AppDatabase.open(tempRoot.path);
        await upgradeDb.select(upgradeDb.documents).get();
        await upgradeDb.close();

        // SQLite는 CHECK 제약이 있는 컬럼에 정상 연결로는 유효하지 않은 값을 쓸 수
        // 없다(§5.4 각주가 말하는 "ALTER TABLE CHECK 미소급"은 컬럼 신설 시점의 기존
        // 행 이야기다). 여기서는 §5.4의 실제 우려 — 수동 DB 편집 등으로 CHECK를 우회해
        // 미지값이 들어가는 상황 — 을 `PRAGMA ignore_check_constraints`로 재현한다.
        final raw = sqlite3.sqlite3.open(dbPath);
        try {
          raw.execute('PRAGMA ignore_check_constraints = 1;');
          raw.execute("UPDATE settings_rows SET theme_mode = 'neon' WHERE id = 0;");
        } finally {
          raw.dispose();
        }

        final db = AppDatabase.open(tempRoot.path);
        try {
          final repo = DriftSettingsRepository(database: db);
          final mode = await repo.watchThemeMode().first;
          expect(mode, AppThemeMode.system, reason: '미지값은 크래시 없이 system으로 폴백해야 한다');
        } finally {
          await db.close();
        }
      },
    );
  });
}
