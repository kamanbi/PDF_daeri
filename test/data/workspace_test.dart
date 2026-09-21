import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';

/// [68 §3.1] `AppWorkspace.create()`의 플랫폼별 경로 계산 로직만 검증하는
/// 페이크. 실제 파일시스템을 만들지 않고 `getApplicationSupportPath()`/
/// `getApplicationDocumentsPath()`에 서로 다른 값을 응답해, 어느 쪽이
/// 선택됐는지 반환된 `root`로 구분한다.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.supportPath,
    required this.documentsPath,
  });

  final String supportPath;
  final String documentsPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

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

  group('AppWorkspace.create (68 §3.1 · Windows 저장 루트 분기)', () {
    late PathProviderPlatform originalPlatform;

    setUp(() {
      originalPlatform = PathProviderPlatform.instance;
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPlatform;
    });

    test(
      '이 테스트 호스트(Platform.isWindows)에서는 '
      'getApplicationSupportPath()를 쓰고 getApplicationDocumentsPath()는 쓰지 않는다',
      () async {
        // Platform.isWindows/isAndroid는 dart:io 실제 OS 값이라 이 테스트 환경(Windows)에서
        // 오버라이드할 수 없다 — 이 케이스가 정확히 이번 라운드의 치명 지점(§3.1)이므로
        // 실제 호스트에서 검증하는 것이 더 강한 증거다. Android 분기는 이 페이크로 경로
        // 계산 자체는 동일 로직이 타므로(단순 삼항 분기) 별도 실기기 검증은 불필요하다.
        PathProviderPlatform.instance = _FakePathProviderPlatform(
          supportPath: p.join(tempRoot.path, 'support-dir'),
          documentsPath: p.join(tempRoot.path, 'my-documents'),
        );

        final ws = await AppWorkspace.create();

        expect(Platform.isWindows, isTrue, reason: 'CI/개발 호스트가 Windows여야 이 분기를 검증한다');
        expect(ws.root, p.join(tempRoot.path, 'support-dir'));
        expect(ws.root, isNot(p.join(tempRoot.path, 'my-documents')));
      },
    );
  });

  group('signature/ (79 §3.2 · 전자서명 재사용 1개)', () {
    test('ensureLayout: signature/ 디렉터리를 생성한다', () async {
      expect(await Directory(p.join(tempRoot.path, 'signature')).exists(), isTrue);
    });

    test('signaturePath: <root>/signature/current.png를 가리킨다', () {
      expect(
        workspace.signaturePath,
        p.join(tempRoot.path, 'signature', 'current.png'),
      );
    });

    test('hasSignature: 저장 전에는 false', () async {
      expect(await workspace.hasSignature(), isFalse);
    });

    test('writeSignature/hasSignature: 저장 후 true, 바이트 그대로 읽힌다', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await workspace.writeSignature(bytes);

      expect(await workspace.hasSignature(), isTrue);
      expect(
        await File(workspace.signaturePath).readAsBytes(),
        bytes,
      );
    });

    test('writeSignature: 두 번째 호출이 첫 번째 서명을 덮어쓴다(1개만 재사용)', () async {
      await workspace.writeSignature(Uint8List.fromList([1, 2, 3]));
      await workspace.writeSignature(Uint8List.fromList([9, 9]));

      final result = await File(workspace.signaturePath).readAsBytes();
      expect(result, Uint8List.fromList([9, 9]));
    });

    test('writeSignature: .tmp 잔재를 남기지 않는다', () async {
      await workspace.writeSignature(Uint8List.fromList([1]));

      expect(await File('${workspace.signaturePath}.tmp').exists(), isFalse);
    });

    test('clearSignature: 저장된 서명을 삭제하고 hasSignature가 false가 된다', () async {
      await workspace.writeSignature(Uint8List.fromList([1, 2]));
      await workspace.clearSignature();

      expect(await workspace.hasSignature(), isFalse);
    });

    test('clearSignature: 서명이 없어도 조용히 성공한다', () async {
      await expectLater(workspace.clearSignature(), completes);
    });

    test('clearCache는 signature/를 지우지 않는다(cache/ 하위가 아니므로)', () async {
      await workspace.writeSignature(Uint8List.fromList([1, 2, 3]));

      await workspace.clearCache();

      expect(await workspace.hasSignature(), isTrue);
    });

    test('ensureLayout 재호출로 기존 서명이 지워지지 않는다(부팅 정리 제외)', () async {
      await workspace.writeSignature(Uint8List.fromList([5, 5, 5]));

      await workspace.ensureLayout();

      expect(await workspace.hasSignature(), isTrue);
    });
  });

  group('usage (4주차 D-2 · 설계 §6.3)', () {
    test('빈 작업공간: 전부 0바이트/0개', () async {
      final usage = await workspace.usage();

      expect(usage.docsBytes, 0);
      expect(usage.recentBytes, 0);
      expect(usage.cacheBytes, 0);
      expect(usage.thumbsBytes, 0);
      expect(usage.recentCount, 0);
      expect(usage.totalBytes, 0);
    });

    test('docs/recent/cache/thumbs 각각의 바이트를 정확히 합산한다', () async {
      // docs/<docId>/document.pdf + sources/ 하위 파일까지 재귀 합산되어야 한다.
      const docId = 'doc-usage';
      await File(workspace.docPdf(docId)).create(recursive: true);
      await File(workspace.docPdf(docId)).writeAsBytes(List.filled(100, 0));
      await File(workspace.sourceImage(docId, 1)).create(recursive: true);
      await File(workspace.sourceImage(docId, 1)).writeAsBytes(List.filled(50, 0));

      await File(workspace.recentFile('r1')).create(recursive: true);
      await File(workspace.recentFile('r1')).writeAsBytes(List.filled(10, 0));
      await File(workspace.recentFile('r2')).create(recursive: true);
      await File(workspace.recentFile('r2')).writeAsBytes(List.filled(20, 0));

      await File(workspace.cacheFile('c1')).create(recursive: true);
      await File(workspace.cacheFile('c1')).writeAsBytes(List.filled(5, 0));

      await File(workspace.thumb(docId)).create(recursive: true);
      await File(workspace.thumb(docId)).writeAsBytes(List.filled(7, 0));

      final usage = await workspace.usage();

      expect(usage.docsBytes, 150); // 100 + 50
      expect(usage.recentBytes, 30); // 10 + 20
      expect(usage.recentCount, 2);
      expect(usage.cacheBytes, 5);
      expect(usage.thumbsBytes, 7);
      expect(usage.totalBytes, 150 + 30 + 5 + 7);
    });

    test('cache/share/ 하위 파일도 cacheBytes에 재귀 합산된다', () async {
      final sharePath = workspace.shareFile('공유용.pdf');
      await File(sharePath).create(recursive: true);
      await File(sharePath).writeAsBytes(List.filled(3, 0));

      final usage = await workspace.usage();

      expect(usage.cacheBytes, 3);
    });
  });
}
