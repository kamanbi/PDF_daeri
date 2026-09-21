/// Drift 데이터베이스 진입점. (설계 §6, 확정)
///
/// DB는 메타데이터 인덱스일 뿐이며 **원본 진실은 파일**이다. 앱 시작 시
/// `DocumentRepository.reconcileWithFilesystem()`으로 불일치를 파일 기준 복구한다.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Documents,
    Pages,
    RecentFiles,
    SettingsRows,
    EditDrafts,
    EditDraftPages,
    EditDraftMarks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// [workspaceRoot]는 `Workspace.root`와 동일한 앱 작업공간 루트.
  /// DB 파일은 `<workspaceRoot>/app.db`에 둔다.
  factory AppDatabase.open(String workspaceRoot) {
    return AppDatabase(_openConnection(p.join(workspaceRoot, 'app.db')));
  }

  @override
  int get schemaVersion => 5;

  // schemaVersion 1 → 2 (`_workspace/36_architect_week3_design.md` §1·§2.3·Q-W10):
  // pages.crop 컬럼 신설("l,t,r,b" 형식 또는 null, kind='image' 전용). `addColumn`
  // 마이그레이션이 걸리는 것은 이 컬럼 하나뿐이며, 기존 행은 전부 crop=null로
  // 남는다(원래 크롭이 없던 페이지와 동일 의미이므로 별도 백필이 필요 없다).
  //
  // 주의: `customConstraints`의 `CHECK (kind='image' OR crop IS NULL)`은 스키마
  // **생성 시점**에만 적용되며, 이미 만들어진 pages 테이블에 `addColumn`으로 컬럼을
  // 추가해도 새 CHECK가 기존 테이블에 걸리지 않는다(SQLite `ALTER TABLE ADD COLUMN`의
  // 제약). 실질 방어선은 `_pageToCompanion`의 코드 레벨 assert다
  // (`document_repository.dart`) — 이 사실을 놓치면 "제약이 걸린 줄 알고" 코드 방어를
  // 생략하는 사고가 난다.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(pages, pages.crop);
      }
      // schemaVersion 2 → 3 (`_workspace/76_architect_design.md` §4.4): 편집 드래프트
      // 복구용 테이블 2개 신설. 신규 생성이므로 CHECK 제약이 정상 적용된다
      // (기존 테이블에 `addColumn`으로 컬럼을 더하는 경우와 달리 제약 누락 문제가 없다).
      if (from < 3) {
        await m.createTable(editDrafts);
        await m.createTable(editDraftPages);
      }
      // schemaVersion 3 → 4 (`_workspace/79_architect_v1.1_v2_design.md` §6.3):
      // 드래프트 페이지 위 마크(형광펜·텍스트 상자·이미지) 저장용 테이블 신설.
      // 신규 생성이므로 CHECK 제약이 정상 적용된다(2→3과 동일한 이유로
      // addColumn 케이스의 제약 누락 문제가 없다).
      if (from < 4) {
        await m.createTable(editDraftMarks);
      }
      // schemaVersion 4 → 5 (`_workspace/82_spec-guardian_final_review.md` M1):
      // settings.theme_mode 컬럼 신설. addColumn이므로 CHECK 제약이 기존 행에
      // 소급 적용되지 않는다(2→3의 pages.crop과 동일한 SQLite 제약) — 코드
      // 레벨 검증은 `settings_repository.dart`가 담당한다.
      if (from < 5) {
        await m.addColumn(settingsRows, settingsRows.themeMode);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection(String dbFilePath) {
  return LazyDatabase(() async {
    final file = File(dbFilePath);
    return NativeDatabase.createInBackground(file);
  });
}
