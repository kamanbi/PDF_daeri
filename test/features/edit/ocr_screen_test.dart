import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_daeri/app/providers.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/features/edit/ocr_screen.dart';
import 'package:pdf_daeri/pdf/ocr_source.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart' show PdfPageGeometry, PdfPageSize, PdfRenderer;
import 'package:pdf_daeri/pdf/stamp_builder.dart' show StampRect;

/// `_FakeRenderer` — `pageGeometry`만 필요하다(`ocr_screen.dart`가 실제로 쓰는
/// `PdfRenderer` API는 이것뿐이다). 나머지는 이 화면이 부르지 않는다.
class _FakeRenderer implements PdfRenderer {
  _FakeRenderer(this.pageCount);
  final int pageCount;

  @override
  Future<PdfResult<PdfPageGeometry>> pageGeometry(String pdfPath, {String? password}) async => PdfOk(
    PdfPageGeometry(
      pageCount: pageCount,
      sizes: List.generate(pageCount, (_) => const PdfPageSize(widthPt: 600, heightPt: 800)),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} — OcrScreen 테스트에서 쓰이지 않는 PdfRenderer 멤버',
  );
}

/// 문서 로드(`load`)와 저장(`stampToNewDocument`) 호출만 기록한다. 나머지는
/// 이 화면이 부르지 않는다.
class _FakeOcrRepository implements DocumentRepository {
  _FakeOcrRepository(this.pages);
  final List<PageRef> pages;
  int stampCallCount = 0;
  String Function(String)? capturedTitleFor;

  @override
  Future<PdfResult<DocumentDetail>> load(String docId) async => PdfOk(
    DocumentDetail(
      summary: DocumentSummary(
        id: docId,
        title: '테스트 문서',
        origin: DocOrigin.imported,
        pageCount: pages.length,
        fileSize: 1000,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        thumbPath: null,
      ),
      pages: pages,
    ),
  );

  @override
  Future<PdfResult<DocumentSummary>> stampToNewDocument({
    required String sourcePdfPath,
    required String originalTitle,
    required stampPdfBytes,
    required int pageCount,
    required int baselineBytes,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
    String Function(String originalTitle)? titleFor,
  }) async {
    stampCallCount++;
    capturedTitleFor = titleFor;
    return PdfOk(
      DocumentSummary(
        id: 'doc-ocr',
        title: titleFor != null ? titleFor(originalTitle) : originalTitle,
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} — OcrScreen 테스트에서 쓰이지 않는 DocumentRepository 멤버',
  );
}

/// [imagePath] → [OcrPageResult] 매핑을 그대로 돌려준다. 호출 순서를 기록해
/// "순차 호출" 계약을 검증한다.
class _FakeOcrSource implements OcrSource {
  _FakeOcrSource(this.results);
  final Map<String, OcrPageResult> results;
  final List<String> calledPaths = [];
  bool disposed = false;

  @override
  Future<PdfResult<OcrPageResult>> recognize(String imagePath) async {
    calledPaths.add(imagePath);
    return PdfOk(results[imagePath] ?? const OcrPageResult(words: [], fullText: ''));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('ocr_screen_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<PageRef> pages,
    required Map<String, OcrPageResult> ocrResults,
    required _FakeOcrRepository repo,
  }) async {
    final pdfFile = File('${tempRoot.path}/source.pdf');
    pdfFile.writeAsBytesSync([1, 2, 3, 4]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(repo),
          pdfRendererProvider.overrideWithValue(_FakeRenderer(pages.length)),
          ocrSourceProvider.overrideWithValue(() => _FakeOcrSource(ocrResults)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showOcrScreen(
                    context: context,
                    args: OcrArgs(
                      pdfPath: pdfFile.path,
                      title: '테스트 문서',
                      docId: 'doc-1',
                      pageCount: pages.length,
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
    // `annotate_screen_test.dart`/`signature_screen_test.dart`와 같은 이유로
    // 여러 차례 짧게 나눠 펌프한다 — `addPostFrameCallback`으로 시작하는 첫
    // 비동기 체인이 한 프레임 안에서 다 처리되지 않는다.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  const rect = StampRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2);

  testWidgets('진입 직후: 인식 대상 페이지 수만큼 recognize가 순차 호출되고 저장까지 이어진다', (
    tester,
  ) async {
    final pages = [
      const ImagePageRef(imagePath: 'a.jpg', rotation: 0),
      const PdfPageRef(sourcePath: 'ext.pdf', sourceIndex: 0, rotation: 0),
      const ImagePageRef(imagePath: 'b.jpg', rotation: 0),
    ];
    final repo = _FakeOcrRepository(pages);
    final ocrSource = _FakeOcrSource({
      'a.jpg': const OcrPageResult(words: [OcrWord(text: '가', rect: rect)], fullText: '가'),
      'b.jpg': const OcrPageResult(words: [OcrWord(text: '나', rect: rect)], fullText: '나'),
    });

    final pdfFile = File('${tempRoot.path}/source.pdf');
    pdfFile.writeAsBytesSync([1, 2, 3, 4]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(repo),
          pdfRendererProvider.overrideWithValue(_FakeRenderer(pages.length)),
          ocrSourceProvider.overrideWithValue(() => ocrSource),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showOcrScreen(
                    context: context,
                    args: OcrArgs(
                      pdfPath: pdfFile.path,
                      title: '원본',
                      docId: 'doc-1',
                      pageCount: pages.length,
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

    // 첫 tap은 runAsync 밖에서 한다 — `initState`의 `addPostFrameCallback(_run)`이
    // 실제로 실행되려면 `pump()`로 프레임을 그려야 하는데, `runAsync` 블록 안에서는
    // 프레임이 그려지지 않아 콜백이 걸리지 않는다(annotate 테스트의 "저장" 버튼
    // 탭과 달리, 이 tap은 화면 진입 자체를 트리거한다).
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // `KoreanFont.bytes()`가 실제 asset I/O를 거치므로(annotate 테스트와 동일
    // 이유) 실제 딜레이로 나머지 체인(폰트 로딩 → 스탬프 빌드 → 저장)이 끝날
    // 때까지 기다린다.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // ImagePageRef 페이지(a.jpg, b.jpg)만 인식 대상이다 — PdfPageRef는
    // 건너뛴다(§7.1). 순서도 페이지 인덱스 순서를 지킨다(§7.5 순차 호출).
    expect(ocrSource.calledPaths, ['a.jpg', 'b.jpg']);

    expect(repo.stampCallCount, 1);
    expect(repo.capturedTitleFor, isNotNull);
    expect(repo.capturedTitleFor!('원본'), '원본 (텍스트 인식)');

    // 저장 성공 시 화면이 pop된다 — 라우트 전환 애니메이션이 끝나야 dispose가
    // 실행된다.
    await tester.pumpAndSettle();
    expect(ocrSource.disposed, isTrue);
  });

  testWidgets('재진입: 두 번째 화면 진입이 첫 번째에서 닫힌 OcrSource를 재사용하지 않는다 (82번 최종검증 M2 회귀)', (
    tester,
  ) async {
    final pages = [const ImagePageRef(imagePath: 'a.jpg', rotation: 0)];
    final repo = _FakeOcrRepository(pages);
    final createdSources = <_FakeOcrSource>[];

    final pdfFile = File('${tempRoot.path}/source.pdf');
    pdfFile.writeAsBytesSync([1, 2, 3, 4]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(repo),
          pdfRendererProvider.overrideWithValue(_FakeRenderer(pages.length)),
          // 진입마다 새 인스턴스를 반환하는 팩토리 — providers.dart의
          // `ocrSourceProvider`(Provider<OcrSource Function()>) 계약과 동일하다.
          ocrSourceProvider.overrideWithValue(() {
            final source = _FakeOcrSource({
              'a.jpg': const OcrPageResult(words: [OcrWord(text: '가', rect: rect)], fullText: '가'),
            });
            createdSources.add(source);
            return source;
          }),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showOcrScreen(
                    context: context,
                    args: OcrArgs(
                      pdfPath: pdfFile.path,
                      title: '원본',
                      docId: 'doc-1',
                      pageCount: pages.length,
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

    for (var round = 0; round < 2; round++) {
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
    }

    // 진입마다 새 인스턴스가 만들어졌고(캐시 재사용 아님), 각각 독립적으로
    // 저장까지 마친 뒤 자기 자신만 dispose됐다 — 두 번째 진입이 첫 번째에서
    // 이미 닫힌 인스턴스를 물려받지 않았다는 뜻이다.
    expect(createdSources, hasLength(2));
    expect(createdSources[0], isNot(same(createdSources[1])));
    expect(createdSources[0].disposed, isTrue);
    expect(createdSources[1].disposed, isTrue);
    expect(createdSources[0].calledPaths, ['a.jpg']);
    expect(createdSources[1].calledPaths, ['a.jpg']);
    expect(repo.stampCallCount, 2);
  });

  testWidgets('빈 결과 처리: 모든 페이지의 인식 텍스트가 비어 있으면 안내만 하고 저장하지 않는다', (
    tester,
  ) async {
    final pages = [const ImagePageRef(imagePath: 'a.jpg', rotation: 0)];
    final repo = _FakeOcrRepository(pages);

    await pumpScreen(
      tester,
      pages: pages,
      ocrResults: {'a.jpg': const OcrPageResult(words: [], fullText: '')},
      repo: repo,
    );

    expect(find.text('인식된 텍스트가 없습니다.'), findsOneWidget);
    expect(repo.stampCallCount, 0);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
  });

  testWidgets('외부 PDF 페이지뿐인 문서: ImagePageRef가 하나도 없으면 인식을 호출하지 않고 바로 빈 결과로 처리한다', (
    tester,
  ) async {
    final pages = [const PdfPageRef(sourcePath: 'ext.pdf', sourceIndex: 0, rotation: 0)];
    final repo = _FakeOcrRepository(pages);

    await pumpScreen(tester, pages: pages, ocrResults: const {}, repo: repo);

    expect(find.text('인식된 텍스트가 없습니다.'), findsOneWidget);
    expect(find.textContaining('페이지 인식 중'), findsNothing);
    expect(repo.stampCallCount, 0);
  });
}
