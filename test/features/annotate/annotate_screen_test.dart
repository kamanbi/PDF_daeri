import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_daeri/app/app_locale.dart';
import 'package:pdf_daeri/app/providers.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/features/annotate/annotate_screen.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_compressor.dart' show TargetAttempt;
import 'package:pdf_daeri/pdf/pdf_engine.dart' show ImageQuality;
import 'package:pdf_daeri/pdf/pdf_renderer.dart';

// 1x1 투명 PNG (잘 알려진 최소 유효 PNG) -- 렌더러 스텁이 돌려주는 "페이지
// 미리보기" 더미 바이트. `signature_screen_test.dart`와 같은 바이트다.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// `signature_screen_test.dart`와 같은 이유(fake async 존과 실 I/O가 맞물리지
/// 않음)로 순수 인메모리 페이크 렌더러를 쓴다.
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
class _FakeStampRepository implements DocumentRepository {
  Uint8List? capturedStampBytes;
  String Function(String)? capturedTitleFor;
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
    capturedTitleFor = titleFor;
    final title = titleFor?.call(originalTitle) ?? originalTitle;
    return PdfOk(
      DocumentSummary(
        id: 'doc-1',
        title: title,
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

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('annotate_screen_test');
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
          documentRepositoryProvider.overrideWithValue(repo),
          pdfRendererProvider.overrideWithValue(_FakeRenderer()),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: const [Locale('ko'), Locale('en')],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAnnotateScreen(
                    context: context,
                    args: AnnotateArgs(
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('진입 직후: 3개 도구·되돌리기·저장(비활성)·재편집 불가 경고가 보인다', (
    tester,
  ) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    expect(find.text('형광펜'), findsOneWidget);
    expect(find.text('텍스트'), findsOneWidget);
    expect(find.text('선택·삭제'), findsOneWidget);
    expect(find.text('되돌리기'), findsOneWidget);
    expect(find.text('저장하면 주석이 문서에 합쳐져 수정할 수 없습니다.'), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('저장'), matching: find.byType(FilledButton)),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('형광펜 → 색 선택하면 마크가 추가되고 저장이 활성화되며 삭제 버튼이 보인다', (
    tester,
  ) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    await tester.tap(find.text('형광펜'));
    await tester.pumpAndSettle();

    // 4색(Q9) 바텀시트가 뜬다.
    expect(find.byType(GestureDetector), findsWidgets);
    final colorSwatch = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(GestureDetector),
        )
        .first;
    await tester.tap(colorSwatch);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('저장'), matching: find.byType(FilledButton)),
    );
    expect(saveButton.onPressed, isNotNull);
    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('텍스트 도구 → 문자열 입력하면 마크가 추가된다', (tester) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    await tester.tap(find.text('텍스트'));
    await tester.pumpAndSettle();

    expect(find.text('텍스트 추가'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '메모');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('저장'), matching: find.byType(FilledButton)),
    );
    expect(saveButton.onPressed, isNotNull);
  });

  testWidgets('빈 문자열로 확인하면 마크가 추가되지 않는다(저장 비활성 유지)', (tester) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    await tester.tap(find.text('텍스트'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('저장'), matching: find.byType(FilledButton)),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('마크 추가 후 되돌리기를 누르면 저장이 다시 비활성화된다', (tester) async {
    await pumpScreen(tester, repo: _FakeStampRepository());

    await tester.tap(find.text('텍스트'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '메모');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('저장'), matching: find.byType(FilledButton)),
    );
    expect(saveButton.onPressed, isNull);
    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('텍스트 마크 저장: stampToNewDocument가 annotatedTitle로 호출된다', (
    tester,
  ) async {
    final repo = _FakeStampRepository();
    await pumpScreen(tester, repo: repo);

    await tester.tap(find.text('텍스트'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '메모');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

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
    expect(repo.capturedTitleFor?.call('원본'), '원본 (주석)');
  });
}
