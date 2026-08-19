/// 1주차 최소 위젯 테스트. 카운터 템플릿을 실제 앱 배선 검증으로 교체한다.
///
/// 최소 검증 3종(작업 지시서 요구):
/// - 초기화 실패(=providers가 null) 시 앱이 죽지 않고 홈 화면 + 경고 배너를 보여준다
/// - 스캔 불가(`EngineUnsupported`) 시 "사진 → PDF"로 유도한다
/// - `GuardBlocked`(용량 게이트 차단)를 삼키지 않고 화면에 노출한다
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_daeri/app/app.dart';
import 'package:pdf_daeri/app/providers.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/features/scan/save_images_flow.dart';
import 'package:pdf_daeri/features/scan/scan_screen.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/scan_source.dart';

class _FakeUnsupportedScanSource implements ScanSource {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<PdfResult<List<String>>> scan({int pageLimit = 30}) async =>
      const PdfErr(EngineUnsupported('mlkit_document_scanner'));
}

/// 항상 `SizeGuardViolation`으로 실패하는 저장소. 화면이 이 실패를 조용히
/// 삼키지 않고 사용자에게 보여주는지 검증하는 용도다.
class _FakeGuardBlockedRepository implements DocumentRepository {
  @override
  Stream<List<DocumentSummary>> watchDocuments() => const Stream.empty();

  @override
  Future<PdfResult<DocumentDetail>> load(String docId) async =>
      const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

  @override
  Future<PdfResult<DocumentSummary>> createDocument({
    required String title,
    required DocOrigin origin,
    required List<PageRef> pages,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    return const PdfErr(
      SizeGuardViolation(GuardBlocked(resultBytes: 200, limitBytes: 100, op: SaveOp.merge)),
    );
  }

  @override
  Future<PdfResult<CompressToNewDocumentResult>> compressToNewDocument({
    required CompressSource source,
    required ImageQuality preset,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async => const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

  @override
  Future<PdfResult<DocumentSummary>> rename(String docId, String newTitle) async =>
      const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

  @override
  Future<PdfResult<void>> delete(String docId) async => const PdfOk(null);

  @override
  Future<void> reconcileWithFilesystem() async {}

  @override
  Future<PdfResult<String?>> ensureThumbnail(String docId) async =>
      const PdfOk(null);
}

void main() {
  testWidgets('초기화 실패 시에도 앱이 죽지 않고 홈 화면 + 경고 배너를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootIssuesProvider.overrideWithValue(const ['작업공간 초기화에 실패했습니다.']),
        ],
        child: const PdfDaeriApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스캔'), findsOneWidget);
    expect(find.text('PDF 열기'), findsOneWidget);
    expect(find.text('사진 → PDF'), findsOneWidget);
    expect(find.textContaining('작업공간 초기화에 실패했습니다.'), findsOneWidget);

    // workspaceProvider/documentRepositoryProvider가 기본값(null)이므로
    // 3개 진입점 모두 비활성 상태여야 한다(죽지 않되, 쓸 수 없음을 알린다).
    final scanButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '스캔'));
    expect(scanButton.onPressed, isNull);
  });

  testWidgets('스캔이 불가능하면 "사진 → PDF"로 유도한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scanSourceProvider.overrideWithValue(_FakeUnsupportedScanSource())],
        child: const MaterialApp(home: ScanScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('사진 → PDF로 계속하기'), findsOneWidget);
  });

  testWidgets('GuardBlocked(용량 검증 실패)를 삼키지 않고 화면에 노출한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentRepositoryProvider.overrideWithValue(_FakeGuardBlockedRepository())],
        child: const MaterialApp(
          home: SaveImagesScreen(
            imagePaths: [],
            origin: DocOrigin.photo,
            suggestedTitle: '테스트 문서',
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(find.textContaining('용량 검증 게이트'), findsOneWidget);
  });
}
