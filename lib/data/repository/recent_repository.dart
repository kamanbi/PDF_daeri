/// 최근 연 파일 저장소. (설계 §1.2, 2주차 확정)
///
/// `recent/<id>.pdf`로 외부 PDF를 복사·기록하며, `documents` 행은 만들지 않는다
/// — 최근 목록은 "내 문서"(섹션 2)와 별개다(§1.2). 두 진입점(SAF URI / 앱 내
/// 피커 로컬 경로)이 이 파일 안의 공통 내부 함수([_insertAndEnforce])로 합류한다.
///
/// **용량 상한(사용자 확정, 2026-08-18 · 1주차 Q7 재상신 U1 (a) 채택)**:
/// 총 300MB **또는** 20개 중 먼저 닿는 쪽. `opened_at` 오래된 것부터 정리한다.
/// 중복 임포트 제거는 하지 않는다(§1.2) — 이 상한이 무한 증식을 막는 유일한 방어선이다.
library;

import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/app_error.dart';
import '../../core/file_name.dart';
import '../db/app_database.dart' as db;
import '../storage/saf_import.dart';
import '../storage/workspace.dart';

abstract interface class RecentRepository {
  /// 최근 연 파일(최신순 고정 = opened_at DESC). 정렬 옵션 없음.
  Stream<List<RecentFile>> watchRecent();

  /// 외부 인텐트로 받은 `content://` URI를 `recent/<uuid>.pdf`로 복사하고 행을 만든다.
  Future<PdfResult<RecentFile>> importFromUri(String uri);

  /// 앱 내 파일 선택기(`file_picker`)가 돌려준 로컬 경로를 임포트한다.
  /// [displayName]은 피커가 준 원본 파일명(확장자 포함 가능). 정규화는 이 메서드가 한다.
  Future<PdfResult<RecentFile>> importFromLocalPath({
    required String sourcePath,
    required String displayName,
  });

  /// 이미 목록에 있는 파일을 다시 열었을 때 `opened_at`만 갱신한다. 재복사하지 않는다.
  Future<void> touch(String id);

  /// "목록에서 제거" — 원본을 지우지 않는다. `recent/<id>.pdf` 복사본과 행만 지운다.
  Future<void> removeFromList(String id);

  /// 용량 상한 초과 시 `opened_at` 오래된 복사본부터 정리한다.
  Future<void> enforceQuota();
}

class RecentFile {
  const RecentFile({
    required this.id,
    required this.displayName,
    required this.copiedPath,
    required this.openedAt,
    required this.size,
  });
  final String id; // UUID v4. recent/<id>.pdf 의 파일명이기도 하다
  final String displayName; // 한글 원문(정규화 후). 경로에 쓰지 않는다
  final String copiedPath; // <root>/recent/<id>.pdf
  final DateTime openedAt;
  final int size; // 복사본 바이트
}

class DriftRecentRepository implements RecentRepository {
  DriftRecentRepository({
    required db.AppDatabase database,
    required Workspace workspace,
    required SafImporter importer,
    Uuid? uuid,
  }) : _db = database,
       _workspace = workspace,
       _importer = importer,
       _uuid = uuid ?? const Uuid();

  final db.AppDatabase _db;
  final Workspace _workspace;
  final SafImporter _importer;
  final Uuid _uuid;

  /// 사용자 확정: 총 300MB 또는 20개 중 먼저 닿는 쪽.
  static const int quotaBytes = 300 * 1024 * 1024;
  static const int quotaCount = 20;

  RecentFile _toDomain(db.RecentFile row) => RecentFile(
    id: row.id,
    displayName: row.displayName,
    copiedPath: row.copiedPath,
    openedAt: DateTime.fromMillisecondsSinceEpoch(row.openedAt),
    size: row.size,
  );

  @override
  Stream<List<RecentFile>> watchRecent() {
    final query = _db.select(_db.recentFiles)
      ..orderBy([
        (t) => drift.OrderingTerm(expression: t.openedAt, mode: drift.OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<PdfResult<RecentFile>> importFromUri(String uri) async {
    final id = _uuid.v4();
    final destinationPath = _workspace.recentFile(id);
    final copyResult = await _importer.importToPath(
      contentUri: uri,
      destinationPath: destinationPath,
    );
    if (copyResult is PdfErr<SafImportResult>) {
      return PdfErr(copyResult.failure);
    }
    final result = (copyResult as PdfOk<SafImportResult>).value;
    // 표시명 추출 실패 시 FileName.normalize('') 폴백(= 문서_yyyyMMdd_HHmm), §1.2.
    final displayName = FileName.normalize(result.displayName ?? '');
    return _insertAndEnforce(
      id: id,
      displayName: displayName,
      copiedPath: destinationPath,
      size: result.bytes,
    );
  }

  @override
  Future<PdfResult<RecentFile>> importFromLocalPath({
    required String sourcePath,
    required String displayName,
  }) async {
    final id = _uuid.v4();
    final destinationPath = _workspace.recentFile(id);
    final srcFile = File(sourcePath);
    if (!await srcFile.exists()) {
      return PdfErr(SourceMissing(sourcePath));
    }

    int size;
    try {
      await Directory(p.dirname(destinationPath)).create(recursive: true);
      final copied = await srcFile.copy(destinationPath);
      size = await copied.length();
    } catch (e) {
      return PdfErr(UnknownFailure('로컬 파일 복사 실패: $e'));
    }

    final normalized = FileName.normalize(displayName);
    return _insertAndEnforce(
      id: id,
      displayName: normalized,
      copiedPath: destinationPath,
      size: size,
    );
  }

  /// 두 진입점([importFromUri]/[importFromLocalPath])이 합류하는 공통 경로.
  /// 복사 성공 후 행을 기록하고 [enforceQuota]를 호출한다(§1.2).
  Future<PdfResult<RecentFile>> _insertAndEnforce({
    required String id,
    required String displayName,
    required String copiedPath,
    required int size,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _db
          .into(_db.recentFiles)
          .insert(
            db.RecentFilesCompanion.insert(
              id: id,
              displayName: displayName,
              copiedPath: copiedPath,
              openedAt: now,
              size: size,
            ),
          );
    } catch (e) {
      // 행 기록 실패 시 이미 만든 복사본을 목록 없는 고아로 남기지 않는다
      // (반쪽 상태 금지 정신, §7.3과 동일한 원칙을 recent/에도 적용).
      try {
        final f = File(copiedPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      return PdfErr(UnknownFailure('최근 파일 기록 실패: $e'));
    }

    await enforceQuota();

    return PdfOk(
      RecentFile(
        id: id,
        displayName: displayName,
        copiedPath: copiedPath,
        openedAt: DateTime.fromMillisecondsSinceEpoch(now),
        size: size,
      ),
    );
  }

  @override
  Future<void> touch(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(
      _db.recentFiles,
    )..where((t) => t.id.equals(id))).write(
      db.RecentFilesCompanion(openedAt: drift.Value(now)),
    );
  }

  @override
  Future<void> removeFromList(String id) async {
    final row = await (_db.select(
      _db.recentFiles,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await (_db.delete(_db.recentFiles)..where((t) => t.id.equals(id))).go();
    if (row != null) {
      await _deleteCopyIfExists(row.copiedPath);
    }
  }

  @override
  Future<void> enforceQuota() async {
    // 최신순(opened_at DESC)으로 훑으며 누적 바이트/개수 중 먼저 상한에 닿는
    // 지점 이후는 전부 정리한다 — 300MB 또는 20개, 먼저 닿는 쪽(사용자 확정).
    final rows =
        await (_db.select(_db.recentFiles)..orderBy([
              (t) => drift.OrderingTerm(expression: t.openedAt, mode: drift.OrderingMode.desc),
            ]))
            .get();

    var totalBytes = 0;
    final toRemove = <db.RecentFile>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      totalBytes += row.size;
      final overCount = i >= quotaCount; // 21번째부터(0-base) 개수 상한 초과
      final overBytes = totalBytes > quotaBytes;
      if (overCount || overBytes) {
        toRemove.add(row);
      }
    }

    for (final row in toRemove) {
      await (_db.delete(_db.recentFiles)..where((t) => t.id.equals(row.id))).go();
      await _deleteCopyIfExists(row.copiedPath);
    }
  }

  Future<void> _deleteCopyIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 삭제 실패는 무음 처리하되(파일시스템 경합 등) DB 행은 이미 지워진
      // 상태다 — 목록에는 더 이상 나타나지 않으며, 고아 파일은 S5 저장공간
      // 정리 화면에서 다룰 문제로 남긴다(이 라운드에서 그 화면은 만들지 않는다).
    }
  }
}
