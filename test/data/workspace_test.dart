import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/data/storage/workspace.dart';

void main() {
  late Directory tempRoot;
  late AppWorkspace workspace;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_ws_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('ensureLayout: docs/thumbs/recent/cache 생성', () async {
    for (final dir in ['docs', 'thumbs', 'recent', 'cache']) {
      expect(await Directory(p.join(tempRoot.path, dir)).exists(), isTrue);
    }
  });

  test('beginStaging: .tmp 디렉터리와 sources/pages/ 생성', () async {
    const docId = 'doc-a';
    final stagingPath = await workspace.beginStaging(docId);

    expect(stagingPath, p.join(tempRoot.path, 'docs', '$docId.tmp'));
    expect(await Directory(stagingPath).exists(), isTrue);
    expect(
      await Directory(p.join(stagingPath, 'sources', 'pages')).exists(),
      isTrue,
    );
  });

  test('commitStaging 성공: 스테이징이 최종 docDir로 원자적 반영된다', () async {
    const docId = 'doc-b';
    final stagingPath = await workspace.beginStaging(docId);
    final pdfInStaging = File(p.join(stagingPath, 'document.pdf'));
    await pdfInStaging.writeAsString('fake-pdf-bytes');

    await workspace.commitStaging(docId);

    expect(await Directory(stagingPath).exists(), isFalse); // .tmp 사라짐
    expect(await File(workspace.docPdf(docId)).exists(), isTrue);
    expect(
      await File(workspace.docPdf(docId)).readAsString(),
      'fake-pdf-bytes',
    );
    expect(
      await Directory(p.join(tempRoot.path, 'docs', '$docId.old')).exists(),
      isFalse,
    );
  });

  test('commitStaging: 기존 docDir이 있으면 교체하고 .old를 남기지 않는다', () async {
    const docId = 'doc-c';

    // 1차 저장
    final staging1 = await workspace.beginStaging(docId);
    await File(
      p.join(staging1, 'document.pdf'),
    ).writeAsString('version-1');
    await workspace.commitStaging(docId);
    expect(await File(workspace.docPdf(docId)).readAsString(), 'version-1');

    // 재저장(같은 docId로 재편집 저장 시나리오)
    final staging2 = await workspace.beginStaging(docId);
    await File(
      p.join(staging2, 'document.pdf'),
    ).writeAsString('version-2');
    await workspace.commitStaging(docId);

    expect(await File(workspace.docPdf(docId)).readAsString(), 'version-2');
    expect(
      await Directory(p.join(tempRoot.path, 'docs', '$docId.old')).exists(),
      isFalse,
      reason: '커밋 성공 시 .old는 정리되어야 한다',
    );
  });

  test('rollbackStaging: 스테이징을 삭제하고 기존 docDir은 건드리지 않는다', () async {
    const docId = 'doc-d';

    // 기존 문서가 있는 상태를 재현
    final staging1 = await workspace.beginStaging(docId);
    await File(
      p.join(staging1, 'document.pdf'),
    ).writeAsString('kept-version');
    await workspace.commitStaging(docId);

    // 재저장 시도 후 실패(예: SizeGuard 위반) → rollback
    final staging2 = await workspace.beginStaging(docId);
    await File(
      p.join(staging2, 'document.pdf'),
    ).writeAsString('rejected-version');
    await workspace.rollbackStaging(docId);

    expect(await Directory(staging2).exists(), isFalse);
    expect(
      await File(workspace.docPdf(docId)).readAsString(),
      'kept-version',
      reason: '롤백 시 기존 문서는 반쪽 상태로 훼손되지 않아야 한다',
    );
  });

  test('rollbackStaging: 신규 문서(기존 docDir 없음) 실패 시 아무 흔적도 남지 않는다', () async {
    const docId = 'doc-e';
    await workspace.beginStaging(docId);
    await workspace.rollbackStaging(docId);

    expect(await Directory(workspace.docDir(docId)).exists(), isFalse);
    expect(
      await Directory(p.join(tempRoot.path, 'docs', '$docId.tmp')).exists(),
      isFalse,
    );
  });

  test('ensureLayout: 이전 세션의 .tmp/.old 잔재를 정리한다', () async {
    final staleTmp = Directory(p.join(tempRoot.path, 'docs', 'stale.tmp'));
    final staleOld = Directory(p.join(tempRoot.path, 'docs', 'stale.old'));
    await staleTmp.create(recursive: true);
    await staleOld.create(recursive: true);

    await workspace.ensureLayout();

    expect(await staleTmp.exists(), isFalse);
    expect(await staleOld.exists(), isFalse);
  });

  test('경로 헬퍼: docId가 경로에 그대로 쓰이고 제목은 쓰이지 않는다', () {
    const docId = 'a1b2c3d4-uuid';
    expect(workspace.docDir(docId), p.join(tempRoot.path, 'docs', docId));
    expect(
      workspace.docPdf(docId),
      p.join(tempRoot.path, 'docs', docId, 'document.pdf'),
    );
    expect(
      workspace.sourceImage(docId, 7),
      p.join(tempRoot.path, 'docs', docId, 'sources', 'pages', '007.jpg'),
    );
  });

  test('clearCache: cache/ 디렉터리를 비우되 다시 생성한다', () async {
    final cacheFile = File(workspace.cacheFile('key1'));
    await cacheFile.create(recursive: true);
    expect(await cacheFile.exists(), isTrue);

    await workspace.clearCache();

    expect(await cacheFile.exists(), isFalse);
    expect(
      await Directory(p.join(tempRoot.path, 'cache')).exists(),
      isTrue,
    );
  });
}
