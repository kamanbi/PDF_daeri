import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_daeri/app/providers.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';
import 'package:pdf_daeri/features/edit/signature_screen.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_compressor.dart' show TargetAttempt;
import 'package:pdf_daeri/pdf/pdf_engine.dart' show ImageQuality;
import 'package:pdf_daeri/pdf/pdf_renderer.dart';

// 1x1 투명 PNG (잘 알려진 최소 유효 PNG) -- 렌더러 스텁이 돌려주는 "페이지
// 미리보기" 더미 바이트.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// **왜 순수 인메모리 페이크인가**: `AppWorkspace`(실 `dart:io` 기반)를 쓰면
/// `File.exists()`/`readAsBytes()` 같은 실 I/O가 이 화면의 비동기 부트스트랩
/// 안에서 완료되지 않는다 -- `test/widget_test.dart` L166-172 주석이 이미
/// 문서화한 flutter_test 환경의 알려진 제약(fake async 존과 실 I/O 콜백이
/// 맞물리지 않는다)과 같은 문제다. `hasSignature`/`writeSignature`/
/// `clearSignature`를 메모리 상태로만 흉내 내면 위젯 트리 안에서 일어나는
/// await가 전부 일반 Dart Future(마이크로태스크)가 되어 `pump()`로 정상
/// 진행된다. 서명 화면이 사용하지 않는 나머지 멤버는 `UnimplementedError`로
/// 둔다(이 테스트가 건드리지 않음을 명시).
class _FakeSignatureWorkspace implements Workspace {
  Uint8List? _signature;

  @override
  String get signaturePath => throw UnimplementedError(
    '이 테스트는 hasSignature==true 부트스트랩 분기(실 File.readAsBytes 경로)를'
    ' exercise하지 않는다 -- 실 I/O가 flutter_test에서 멎기 때문',
  );

  @override
  Future<bool> hasSignature() async => _signature != null;

  @override
  Future<void> writeSignature(Uint8List png) async => _signature = png;

  @override
  Future<void> clearSignature() async => _signature = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} — SignatureScreen 테스트에서 쓰이지 않는 Workspace 멤버',
  );
}

class _FakeRenderer implements PdfRenderer {
  @override
  Future<PdfResult<int>> openPageCount(String pdfPath, {String? password}) =>
      throw UnimplementedError();

  @override
  Future<PdfResult<PdfPageTextData>> pageText({
    required String pdfPath,
    required int pageIndex,
    String? password,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<Uint8List>> renderPage({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
    CancelToken? cancelToken,
  }) async => PdfOk(_tinyPng);

  @override
  Future<PdfResult<Uint8List>> renderThumbnail({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<Uint8List>> renderPageThumbnail({
    required PageRef page,
    required int targetWidthPx,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  void evictCache() {}

  @override
  Future<PdfResult<PdfPageGeometry>> pageGeometry(
    String pdfPath, {
    String? password,
  }) async => const PdfOk(
    PdfPageGeometry(
      pageCount: 1,
      sizes: [PdfPageSize(widthPt: 600, heightPt: 800)],
    ),
  );

  @override
  void evictDocument(String pdfPath, {String? password}) {}
}

/// `stampToNewDocument` 호출 여부·인자만 기록하고 즉시 성공을 반환한다.
/// 나머지 메서드는 이 테스트에서 쓰이지 않는다.
class _FakeStampRepository implements DocumentRepository {
  Uint8List? capturedStampBytes;
  int callCount = 0;

  @override
  Future<PdfResult<DocumentSummary>> stampToNewDocument({
    required String sourcePdfPath,
    required String originalTitle,
    required Uint8List stampPdfBytes,
    required int pageCount,
    required int baselineBytes,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
    String Function(String originalTitle)? titleFor,
  }) async {
    callCount++;
    capturedStampBytes = stampPdfBytes;
    return PdfOk(
      DocumentSummary(
        id: 'doc-1',
        title: '$originalTitle (서명)',
        origin: DocOrigin.imported,
        pageCount: pageCount,
        fileSize: 1000,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        thumbPath: null,
      ),
    );
  }

  @override
  Stream<List<DocumentSummary>> watchDocuments({String? titleQuery}) =>
      const Stream.empty();

  @override
  Future<PdfResult<DocumentDetail>> load(String docId) =>
      throw UnimplementedError();

  @override
  Future<PdfResult<DocumentSummary>> createDocument({
    required String title,
    required DocOrigin origin,
    required List<PageRef> pages,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<CompressToNewDocumentResult>> compressToNewDocument({
    required CompressSource source,
    required ImageQuality preset,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<CompressToTargetResult>> compressToTargetSize({
    required CompressSource source,
    required int targetBytes,
    void Function(PdfProgress)? onProgress,
    void Function(TargetAttempt)? onAttempt,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PdfResult<DocumentSummary>> rename(String docId, String newTitle) =>
      throw UnimplementedError();

  @override
  Future<PdfResult<void>> delete(String docId) => throw UnimplementedError();

  @override
  Future<void> reconcileWithFilesystem() => throw UnimplementedError();

  @override
  Future<PdfResult<String?>> ensureThumbnail(String docId) =>
      throw UnimplementedError();
}

void main() {
  late Directory tempRoot;

  // 비동기(Future 기반) `Directory.systemTemp.createTemp`/`File.writeAsBytes`는
  // `testWidgets` 본문(fake async 존) 안에서 완료되지 않는다(이 환경에서 실측
  // 확인 -- `test/widget_test.dart` L166-172의 같은 제약). **동기** 버전
  // (`createTempSync`/`writeAsBytesSync`)은 이벤트 루프 콜백을 거치지 않고
  // 호출 스레드에서 바로 끝나므로 이 제약의 대상이 아니다 -- 여기서는 동기
  // 버전만 쓴다.
  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('signature_screen_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required _FakeStampRepository repo,
  }) async {
    final pdfFile = File('${tempRoot.path}/source.pdf');
    pdfFile.writeAsBytesSync([1, 2, 3, 4]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWithValue(_FakeSignatureWorkspace()),
          documentRepositoryProvider.overrideWithValue(repo),
          pdfRendererProvider.overrideWithValue(_FakeRenderer()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showSignatureScreen(
                    context: context,
                    args: SignatureArgs(
                      pdfPath: pdfFile.path,
                      title: '테스트 문서',
                      pageCount: 1,
                      initialPageIndex: 0,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // `_bootstrap()`의 await 전부가 이제 실 dart:io가 아니라 일반 Future이므로
    // (위 `_FakeSignatureWorkspace`/`_FakeRenderer`) 몇 차례 pump로 충분하다.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> drawAndFinishSignature(WidgetTester tester) async {
    final canvas = find.byType(GestureDetector).first;
    final start = tester.getCenter(canvas);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(40, 10));
    await gesture.up();
    await tester.pump();

    // `_done()`이 부르는 `RenderRepaintBoundary.toImage()`/`toByteData()`는
    // 실 dart:ui 네이티브 비동기 호출이라 `File` I/O와 같은 부류의 제약을
    // 받는다 -- 탭 자체를 `runAsync`로 감싸야 그 안에서 시작된 비동기 작업이
    // 진짜로 끝난다(탭 이후에만 `runAsync`를 걸면 이미 fake 존에서 시작된
    // Future라 소용없다는 것을 실측으로 확인했다).
    await tester.runAsync(() async {
      await tester.tap(find.text('완료'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets('저장된 서명이 없으면 그리기 화면으로 시작하고 법적 효력 문구가 보인다', (
    tester,
  ) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    expect(find.text('이 서명은 법적 효력이 없으며 단순 표시용입니다.'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    // 배치 화면 요소는 아직 없다.
    expect(find.text('저장'), findsNothing);
  });

  testWidgets('그림 없이는 완료를 누를 수 없다(strokes 비어있으면 비활성)', (tester) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    final doneButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('완료'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(doneButton.onPressed, isNull);
  });

  testWidgets('그리기 → 완료 → 배치 화면 전환: 서명이 저장되고 배치 화면이 뜬다', (
    tester,
  ) async {
    await pumpScreen(tester, repo: _FakeStampRepository());
    await drawAndFinishSignature(tester);

    expect(find.text('저장'), findsOneWidget);
    expect(find.text('다시 그리기'), findsOneWidget);
    expect(find.text('완료'), findsNothing);
  });

  testWidgets('배치 화면에서 저장을 누르면 저장 진행 화면을 거쳐 stampToNewDocument가 호출된다', (
    tester,
  ) async {
    final repo = _FakeStampRepository();
    await pumpScreen(tester, repo: repo);
    await drawAndFinishSignature(tester);

    // `_save()`는 `StampBuilder.build`를 워커 isolate(`Isolate.run`)에서
    // 돌린다 -- 실 isolate 스폰도 `File` I/O와 같은 부류라 탭 자체를
    // `runAsync`로 감싸야 완료까지 관찰할 수 있다(위 `drawAndFinishSignature`와
    // 같은 이유).
    await tester.pump();
    expect(find.text('저장'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('저장'));
      // 고정 딜레이 대신 실제 완료(repo.callCount 증가)를 폴링한다 — 시스템
      // 부하가 커지면(다른 테스트와 동시 실행 등) 고정 300ms 안에 실 isolate
      // (`Isolate.run`)가 못 끝나 테스트 종료 후 늦게 콜백이 와서
      // "테스트 완료 후 예외"로 잡히는 경쟁 조건이 있었다.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (repo.callCount == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(repo.callCount, 1);
    expect(repo.capturedStampBytes, isNotNull);
  });

  testWidgets('다시 그리기를 누르면 서명이 지워지고 그리기 화면으로 되돌아간다', (
    tester,
  ) async {
    await pumpScreen(tester, repo: _FakeStampRepository());
    await drawAndFinishSignature(tester);
    expect(find.text('저장'), findsOneWidget);

    await tester.tap(find.text('다시 그리기'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('완료'), findsOneWidget);
    expect(find.text('저장'), findsNothing);
  });
}
