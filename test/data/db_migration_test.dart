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

  test('schemaVersion은 2이다', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 2);
    await db.close();
  });
}
