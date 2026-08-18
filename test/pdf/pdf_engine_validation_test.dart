// V2(이미지 경로 화이트리스트 root/docId 바인딩), B1(PdfPageRef 검증 분기 누락),
// C4(outputPath 자체를 앱 루트에 바인딩) 회귀 테스트.
// 06/07_spec-guardian_report 실측 사례를 그대로 재현한다.
//
// 이 검증들은 `pdf_engine.dart`의 입력 검증 단계(isolate 스폰 이전)에서 실패로 끝나므로
// 실제 PDF 픽스처나 isolate 스폰 없이도 결정적으로 테스트할 수 있다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';

void main() {
  late Directory root;
  late String docId;
  late String outputPath;
  late QpdfPdfEngine engine;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_engine_validation_');
    docId = 'doc-under-test';
    final stagingDir = Directory('${root.path}/docs/$docId.tmp');
    stagingDir.createSync(recursive: true);
    Directory('${stagingDir.path}/sources/pages').createSync(recursive: true);
    outputPath = '${stagingDir.path}/document.pdf';
    engine = QpdfPdfEngine(appRoot: root.path);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const dummyGuard = GuardInput(op: SaveOp.deletePages, baselineBytes: 100);

  group('V2: ImagePageRef 화이트리스트는 root+docId에 바인딩된다', () {
    test('완전히 다른 위치의 sources/pages/는 거부된다 (예전 정규식이면 통과했을 사례)', () async {
      final outsideDir = Directory('${root.path}/elsewhere/sources/pages')..createSync(recursive: true);
      final outsideImage = File('${outsideDir.path}/x.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);

      final result = await engine.save(
        pages: [ImagePageRef(imagePath: outsideImage.path, rotation: 0)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: dummyGuard,
      );

      expect(result, isA<PdfErr<SaveOutcome>>());
      final failure = (result as PdfErr<SaveOutcome>).failure;
      expect(failure, isA<UnknownFailure>(), reason: '화이트리스트 밖 경로는 UnknownFailure(outside sources)로 거부되어야 한다');
      expect((failure as UnknownFailure).message, contains('outside sources'));
    });

    test('다른 docId 소유의 sources/pages/는 거부된다', () async {
      final otherDocDir = Directory('${root.path}/docs/other-doc/sources/pages')..createSync(recursive: true);
      final otherImage = File('${otherDocDir.path}/x.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);

      final result = await engine.save(
        pages: [ImagePageRef(imagePath: otherImage.path, rotation: 0)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: dummyGuard,
      );

      expect(result, isA<PdfErr<SaveOutcome>>());
      expect(
        (result as PdfErr<SaveOutcome>).failure,
        isA<UnknownFailure>(),
        reason: '다른 docId의 sources/pages/는 이 저장 요청의 화이트리스트 밖이어야 한다',
      );
    });

    test('같은 docId의 스테이징 sources/pages/ 안은 화이트리스트를 통과한다(파일 부재로만 실패)', () async {
      final imagePath = '${root.path}/docs/$docId.tmp/sources/pages/001.jpg';
      // 화이트리스트는 통과하되 파일이 없다 -- SourceMissing이면 화이트리스트 통과 증거,
      // UnknownFailure(outside sources)면 화이트리스트가 정당한 경로까지 막았다는 뜻(회귀).
      final result = await engine.save(
        pages: [ImagePageRef(imagePath: imagePath, rotation: 0)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: dummyGuard,
      );
      expect(result, isA<PdfErr<SaveOutcome>>());
      expect((result as PdfErr<SaveOutcome>).failure, isA<SourceMissing>());
    });

    test('같은 docId의 커밋된 sources/pages/ 안(=.tmp 아님)도 화이트리스트를 통과한다', () async {
      final committedDir = Directory('${root.path}/docs/$docId/sources/pages')..createSync(recursive: true);
      final imagePath = '${committedDir.path}/002.jpg';
      final result = await engine.save(
        pages: [ImagePageRef(imagePath: imagePath, rotation: 0)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: dummyGuard,
      );
      expect(result, isA<PdfErr<SaveOutcome>>());
      expect((result as PdfErr<SaveOutcome>).failure, isA<SourceMissing>());
    });

    test('sources/pages/ 아래 하위 디렉터리로의 탈출은 거부된다', () async {
      final nestedPath = '${root.path}/docs/$docId.tmp/sources/pages/nested/x.jpg';
      final result = await engine.save(
        pages: [ImagePageRef(imagePath: nestedPath, rotation: 0)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: dummyGuard,
      );
      expect(result, isA<PdfErr<SaveOutcome>>());
      expect((result as PdfErr<SaveOutcome>).failure, isA<UnknownFailure>());
    });
  });

  group('B1: PdfPageRef도 sealed switch로 검증 분기를 탄다', () {
    test('존재하지 않는 sourcePath는 SourceMissing으로 거부된다(isolate 스폰 전)', () async {
      final result = await engine.save(
        pages: [PdfPageRef(sourcePath: '${root.path}/nope.pdf', sourceIndex: 0, rotation: 0)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: dummyGuard,
      );
      expect(result, isA<PdfErr<SaveOutcome>>());
      expect((result as PdfErr<SaveOutcome>).failure, isA<SourceMissing>());
    });
  });

  group('C4: outputPath도 앱 루트+docId+파일명에 바인딩된다', () {
    // 07_spec-guardian_report_r2.md 실측: 이 두 케이스가 루트 미바인딩 상태에서 통과했다.
    Future<PdfResult<SaveOutcome>> saveWithOutputPath(String path) => engine.save(
      pages: const [],
      outputPath: path,
      quality: ImageQuality.standard,
      guardInput: dummyGuard,
    );

    test('앱 루트 밖의 .tmp 경로는 거부된다(예: /sdcard/Download/docs/<id>.tmp/document.pdf)', () async {
      final outsideRoot = Directory.systemTemp.createTempSync('pdf_daeri_other_root_');
      addTearDown(() {
        if (outsideRoot.existsSync()) outsideRoot.deleteSync(recursive: true);
      });
      final fakeOutputPath = '${outsideRoot.path}/docs/$docId.tmp/document.pdf';

      final result = await saveWithOutputPath(fakeOutputPath);

      expect(result, isA<PdfErr<SaveOutcome>>());
      final failure = (result as PdfErr<SaveOutcome>).failure;
      expect(failure, isA<UnknownFailure>());
      expect((failure as UnknownFailure).message, contains('appRoot'));
    });

    test('루트 안이라도 파일명이 document.pdf가 아니면 거부된다(예: anything.exe)', () async {
      final maliciousPath = '${root.path}/docs/$docId.tmp/anything.exe';

      final result = await saveWithOutputPath(maliciousPath);

      expect(result, isA<PdfErr<SaveOutcome>>());
      expect((result as PdfErr<SaveOutcome>).failure, isA<UnknownFailure>());
    });

    test('루트+docId+파일명이 전부 정확하면 통과한다(빈 페이지 목록이라 이후 단계에서 진행)', () async {
      final result = await saveWithOutputPath(outputPath);
      // 빈 pages 목록은 검증 루프를 통과해 isolate까지 간다 -- 여기서 실패하더라도
      // UnknownFailure('outputPath must be...')가 아니어야 화이트리스트/경로 검증은 통과했다는 뜻이다.
      if (result case PdfErr<SaveOutcome>(:final failure)) {
        expect(
          failure is UnknownFailure && failure.message.contains('appRoot'),
          isFalse,
          reason: '올바른 경로인데 경로 검증에서 걸리면 안 된다',
        );
      }
    });
  });
}
