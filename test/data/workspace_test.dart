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

  test('스테이징 경로 헬퍼(N2): 최종 경로와 동일 파일명 규약, .tmp 하위를 가리킨다', () {
    const docId = 'a1b2c3d4-uuid';
    expect(
      workspace.stagingDocPdf(docId),
      p.join(tempRoot.path, 'docs', '$docId.tmp', 'document.pdf'),
    );
    expect(
      workspace.stagingSourcePdf(docId, 3),
      p.join(tempRoot.path, 'docs', '$docId.tmp', 'sources', 'src_3.pdf'),
    );
    expect(
      workspace.stagingSourceImage(docId, 12),
      p.join(tempRoot.path, 'docs', '$docId.tmp', 'sources', 'pages', '012.jpg'),
    );

    // 최종 경로와 파일명 규약이 정확히 대응해야 한다(N2 목적) — 접두사만
    // ".tmp"인지 아닌지로 갈리고 나머지 세그먼트는 동일해야 commitStaging의
    // rename 이후 두 경로가 같은 물리적 위치를 가리킨다.
    expect(
      p.relative(workspace.stagingSourcePdf(docId, 3), from: p.join(tempRoot.path, 'docs', '$docId.tmp')),
      p.relative(workspace.sourcePdf(docId, 3), from: p.join(tempRoot.path, 'docs', docId)),
    );
    expect(
      p.relative(workspace.stagingSourceImage(docId, 12), from: p.join(tempRoot.path, 'docs', '$docId.tmp')),
      p.relative(workspace.sourceImage(docId, 12), from: p.join(tempRoot.path, 'docs', docId)),
    );
  });

  test('spaceSafetyBufferBytes(I3): 20MB 고정값이 Workspace에 공개되어 있다', () {
    expect(Workspace.spaceSafetyBufferBytes, 20 * 1024 * 1024);
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

  group('shareFile/clearShareStaging (3주차 T5 · 설계 §5.2)', () {
    test('shareFile: cache/share/<fileName> 경로를 반환한다', () {
      expect(
        workspace.shareFile('2026년 8월 보고서 (최종).pdf'),
        p.join(tempRoot.path, 'cache', 'share', '2026년 8월 보고서 (최종).pdf'),
      );
    });

    test('shareFile로 만든 사본은 clearShareStaging으로 지워진다', () async {
      final sharePath = workspace.shareFile('공유용.pdf');
      await File(sharePath).create(recursive: true);
      await File(sharePath).writeAsBytes([1, 2, 3]);
      expect(await File(sharePath).exists(), isTrue);

      await workspace.clearShareStaging();

      expect(await File(sharePath).exists(), isFalse);
    });

    test('clearShareStaging: cache/share/가 없어도 조용히 성공한다', () async {
      // ensureLayout() 직후에는 아직 cache/share/에 아무것도 쓰지 않았다.
      await expectLater(workspace.clearShareStaging(), completes);
    });

    test('ensureLayout: 이전 세션의 공유 스테이징 잔재를 정리한다', () async {
      final sharePath = workspace.shareFile('이전세션.pdf');
      await File(sharePath).create(recursive: true);
      await File(sharePath).writeAsBytes([1]);

      await workspace.ensureLayout();

      expect(await File(sharePath).exists(), isFalse);
    });

    test('clearCache는 cache/share/도 함께 지운다(cache/ 하위이므로)', () async {
      final sharePath = workspace.shareFile('지워질파일.pdf');
      await File(sharePath).create(recursive: true);
      await File(sharePath).writeAsBytes([9]);

      await workspace.clearCache();

      expect(await File(sharePath).exists(), isFalse);
    });
  });
}
