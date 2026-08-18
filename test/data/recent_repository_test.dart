import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/data/db/app_database.dart' hide RecentFile;
import 'package:pdf_daeri/data/repository/recent_repository.dart';
import 'package:pdf_daeri/data/storage/saf_import.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';

/// [2주차] `SafImporter`를 흉내내는 페이크. `importToPath`는 [bytes]를
/// [destinationPath]에 실제로 써서 `Workspace.recentFile` 경로에 파일이 생기는지도
/// 함께 검증할 수 있게 한다.
class _FakeSafImporter implements SafImporter {
  _FakeSafImporter({this.displayName, this.bytes = const [1, 2, 3], this.failWith});

  String? displayName;
  List<int> bytes;
  PdfFailure? failWith;

  @override
  Future<String?> takeInitialUri() async => null;

  @override
  Stream<String> onNewIntentUri() => const Stream.empty();

  @override
  Future<PdfResult<SafImportResult>> importToPath({
    required String contentUri,
    required String destinationPath,
  }) async {
    if (failWith != null) {
      return PdfErr(failWith!);
    }
    await Directory(p.dirname(destinationPath)).create(recursive: true);
    await File(destinationPath).writeAsBytes(bytes);
    return PdfOk(SafImportResult(displayName: displayName, bytes: bytes.length));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late AppWorkspace workspace;
  late AppDatabase db;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_recent_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  DriftRecentRepository repoWith({SafImporter? importer}) {
    return DriftRecentRepository(
      database: db,
      workspace: workspace,
      importer: importer ?? _FakeSafImporter(),
    );
  }

  /// quota 테스트용: DB 행 + 실제 recent/<id>.pdf 파일을 함께 만든다(엄격 재현,
  /// enforceQuota가 파일도 지우는지까지 확인하기 위함).
  Future<void> insertRow({required String id, required int openedAt, required int size}) async {
    final path = workspace.recentFile(id);
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsBytes(List.filled(size, 0));
    await db
        .into(db.recentFiles)
        .insert(
          RecentFilesCompanion.insert(
            id: id,
            displayName: 'doc_$id',
            copiedPath: path,
            openedAt: openedAt,
            size: size,
          ),
        );
  }

  group('임포트 왕복', () {
    test('importFromUri: 복사본이 생기고 표시명이 정규화되어 행이 기록된다', () async {
      final repo = repoWith(
        importer: _FakeSafImporter(displayName: '  2026년 8월 보고서 (최종).pdf  '),
      );
      final result = await repo.importFromUri('content://com.example/doc/1');
      expect(result, isA<PdfOk<RecentFile>>());
      final recent = (result as PdfOk<RecentFile>).value;

      expect(recent.displayName, '2026년 8월 보고서 (최종).pdf');
      expect(File(recent.copiedPath).existsSync(), isTrue);
      expect(recent.copiedPath, workspace.recentFile(recent.id));

      final rows = await db.select(db.recentFiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, recent.id);
    });

    test('importFromUri: 표시명 추출 실패 시 FileName.normalize 폴백으로 대체된다', () async {
      final repo = repoWith(importer: _FakeSafImporter(displayName: null));
      final result = await repo.importFromUri('content://com.example/doc/2');
      final recent = (result as PdfOk<RecentFile>).value;
      expect(recent.displayName, startsWith('문서_'));
    });

    test('importFromUri: SafImporter 실패는 그대로 전파된다(무음 실패 아님)', () async {
      final repo = repoWith(importer: _FakeSafImporter(failWith: const PermissionDenied('거부')));
      final result = await repo.importFromUri('content://com.example/doc/3');
      expect(result, isA<PdfErr<RecentFile>>());
      expect((result as PdfErr<RecentFile>).failure, isA<PermissionDenied>());

      final rows = await db.select(db.recentFiles).get();
      expect(rows, isEmpty, reason: '복사가 실패하면 행을 남기지 않는다');
    });

    test('importFromLocalPath: 로컬 경로를 복사하고 행을 기록한다(동일 결과 타입)', () async {
      final localSource = File(p.join(tempRoot.path, 'picked.pdf'));
      await localSource.writeAsBytes(List.filled(10, 0x41));

      final repo = repoWith();
      final result = await repo.importFromLocalPath(
        sourcePath: localSource.path,
        displayName: '피커로 고른 문서.pdf',
      );
      final recent = (result as PdfOk<RecentFile>).value;
      expect(recent.displayName, '피커로 고른 문서.pdf');
      expect(recent.size, 10);
      expect(File(recent.copiedPath).existsSync(), isTrue);
    });

    test('importFromLocalPath: 원본이 없으면 SourceMissing으로 실패한다', () async {
      final repo = repoWith();
      final result = await repo.importFromLocalPath(
        sourcePath: p.join(tempRoot.path, 'does_not_exist.pdf'),
        displayName: '없는 파일.pdf',
      );
      expect(result, isA<PdfErr<RecentFile>>());
      expect((result as PdfErr<RecentFile>).failure, isA<SourceMissing>());
    });
  });

  group('removeFromList — 원본을 지우지 않는다', () {
    test('복사본과 행만 지운다', () async {
      final repo = repoWith();
      final imported =
          ((await repo.importFromUri('content://com.example/doc/4')) as PdfOk<RecentFile>).value;

      await repo.removeFromList(imported.id);

      final rows = await db.select(db.recentFiles).get();
      expect(rows, isEmpty);
      expect(File(imported.copiedPath).existsSync(), isFalse);
    });

    test('원본 소스 파일(임포트 이전의 로컬 경로)은 손대지 않는다', () async {
      final localSource = File(p.join(tempRoot.path, 'original_untouched.pdf'));
      await localSource.writeAsBytes([9, 9, 9]);

      final repo = repoWith();
      final imported =
          ((await repo.importFromLocalPath(
                sourcePath: localSource.path,
                displayName: '원본.pdf',
              ))
              as PdfOk<RecentFile>)
          .value;

      await repo.removeFromList(imported.id);

      // recent/ 복사본은 지워졌지만 원본은 그대로다(절대 규칙 6).
      expect(localSource.existsSync(), isTrue);
    });
  });

  group('touch — 재복사하지 않는다', () {
    test('opened_at만 갱신하고 복사본 경로는 그대로다', () async {
      final repo = repoWith();
      final imported =
          ((await repo.importFromUri('content://com.example/doc/5')) as PdfOk<RecentFile>).value;
      final beforeRows = await db.select(db.recentFiles).get();
      final beforeOpenedAt = beforeRows.single.openedAt;
      final beforeModified = File(imported.copiedPath).statSync().modified;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.touch(imported.id);

      final afterRows = await db.select(db.recentFiles).get();
      expect(afterRows, hasLength(1), reason: 'touch는 새 행을 만들지 않는다');
      expect(afterRows.single.id, imported.id);
      expect(afterRows.single.copiedPath, imported.copiedPath);
      expect(afterRows.single.openedAt, greaterThanOrEqualTo(beforeOpenedAt));
      // 파일이 재작성되지 않았으면 mtime이 그대로다(재복사 안 함의 방증).
      expect(File(imported.copiedPath).statSync().modified, beforeModified);
    });
  });

  group('enforceQuota — 300MB 또는 20개 중 먼저 닿는 쪽, 오래된 것부터 정리', () {
    test('개수 상한(20개) 초과분은 오래된 것부터 제거된다', () async {
      final repo = repoWith();
      // 25개를 만든다. id_00이 가장 오래됨(openedAt 가장 작음), id_24가 가장 최신.
      for (var i = 0; i < 25; i++) {
        await insertRow(id: 'id_${i.toString().padLeft(2, '0')}', openedAt: i, size: 1024);
      }

      await repo.enforceQuota();

      final rows = await db.select(db.recentFiles).get();
      expect(rows, hasLength(20));
      final remainingIds = rows.map((r) => r.id).toSet();
      // 최신 20개(openedAt 5..24)만 남고, 가장 오래된 5개(0..4)는 지워진다.
      for (var i = 0; i < 5; i++) {
        final oldId = 'id_${i.toString().padLeft(2, '0')}';
        expect(remainingIds.contains(oldId), isFalse, reason: '$oldId 는 지워졌어야 한다');
        expect(File(workspace.recentFile(oldId)).existsSync(), isFalse);
      }
      for (var i = 5; i < 25; i++) {
        final keptId = 'id_${i.toString().padLeft(2, '0')}';
        expect(remainingIds.contains(keptId), isTrue, reason: '$keptId 는 남아 있어야 한다');
      }
    });

    test('용량 상한(300MB) 초과분은 오래된 것부터 제거된다(개수는 20 미만)', () async {
      final repo = repoWith();
      const oneHundredMb = 100 * 1024 * 1024;
      // 4개 × 100MB = 400MB > 300MB. 개수는 20 미만이라 용량이 먼저 닿는다.
      await insertRow(id: 'old_1', openedAt: 1, size: oneHundredMb);
      await insertRow(id: 'old_2', openedAt: 2, size: oneHundredMb);
      await insertRow(id: 'keep_1', openedAt: 3, size: oneHundredMb);
      await insertRow(id: 'keep_2', openedAt: 4, size: oneHundredMb);

      await repo.enforceQuota();

      final rows = await db.select(db.recentFiles).get();
      final remainingIds = rows.map((r) => r.id).toSet();
      // 최신순 누적: keep_2(100MB) + keep_1(200MB) + old_2(300MB, 아직 초과 아님) →
      // old_1을 더하는 순간(400MB) 처음 초과하므로 old_1만 제거된다.
      expect(remainingIds.contains('old_1'), isFalse);
      expect(remainingIds.contains('old_2'), isTrue);
      expect(remainingIds.contains('keep_1'), isTrue);
      expect(remainingIds.contains('keep_2'), isTrue);
      expect(File(workspace.recentFile('old_1')).existsSync(), isFalse);
    });

    test('경계값: 정확히 20개면 아무것도 지우지 않는다', () async {
      final repo = repoWith();
      for (var i = 0; i < 20; i++) {
        await insertRow(id: 'id_${i.toString().padLeft(2, '0')}', openedAt: i, size: 1024);
      }
      await repo.enforceQuota();
      final rows = await db.select(db.recentFiles).get();
      expect(rows, hasLength(20));
    });

    test('임포트가 자동으로 enforceQuota를 호출한다', () async {
      final repo = repoWith();
      for (var i = 0; i < 20; i++) {
        await insertRow(id: 'pre_${i.toString().padLeft(2, '0')}', openedAt: i, size: 1024);
      }
      // 21번째 임포트 — importFromUri 내부에서 enforceQuota()가 호출되어
      // 가장 오래된 것(pre_00)이 정리되어야 한다.
      await repo.importFromUri('content://com.example/doc/new');

      final rows = await db.select(db.recentFiles).get();
      expect(rows, hasLength(20));
      expect(rows.any((r) => r.id == 'pre_00'), isFalse);
    });
  });

  group('watchRecent', () {
    test('opened_at DESC로 정렬된 스트림을 낸다', () async {
      final repo = repoWith();
      await insertRow(id: 'a', openedAt: 1, size: 10);
      await insertRow(id: 'b', openedAt: 3, size: 10);
      await insertRow(id: 'c', openedAt: 2, size: 10);

      final first = await repo.watchRecent().first;
      expect(first.map((r) => r.id).toList(), ['b', 'c', 'a']);
    });
  });
}
