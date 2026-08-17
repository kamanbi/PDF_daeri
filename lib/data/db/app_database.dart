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

@DriftDatabase(tables: [Documents, Pages, RecentFiles, SettingsRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// [workspaceRoot]는 `Workspace.root`와 동일한 앱 작업공간 루트.
  /// DB 파일은 `<workspaceRoot>/app.db`에 둔다.
  factory AppDatabase.open(String workspaceRoot) {
    return AppDatabase(_openConnection(p.join(workspaceRoot, 'app.db')));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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
