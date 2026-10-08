/// 1주차 최소 위젯 테스트. 카운터 템플릿을 실제 앱 배선 검증으로 교체한다.
///
/// 최소 검증 3종(작업 지시서 요구):
/// - 초기화 실패(=providers가 null) 시 앱이 죽지 않고 홈 화면 + 경고 배너를 보여준다
/// - 스캔 불가(`EngineUnsupported`) 시 "사진 → PDF"로 유도한다
/// - `GuardBlocked`(용량 게이트 차단)를 삼키지 않고 화면에 노출한다
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_daeri/app/app.dart';
import 'package:pdf_daeri/app/app_locale.dart';
import 'package:pdf_daeri/app/providers.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/platform_features.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/features/edit/save_dialog.dart';
import 'package:pdf_daeri/features/scan/local_document_scan_source.dart';
import 'package:pdf_daeri/features/scan/scan_screen.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_compressor.dart' show TargetAttempt;
import 'package:pdf_daeri/pdf/pdf_engine.dart';

class _FakeUnsupportedScanSource implements ScanSource {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<PdfResult<List<String>>> scan(
    BuildContext context, {
    int pageLimit = 30,
  }) async => const PdfErr(EngineUnsupported('local_document_scanner'));
}

/// 항상 `SizeGuardViolation`으로 실패하는 저장소. 화면이 이 실패를 조용히
/// 삼키지 않고 사용자에게 보여주는지 검증하는 용도다.
class _FakeGuardBlockedRepository implements DocumentRepository {
  @override
  Stream<List<DocumentSummary>> watchDocuments({String? titleQuery}) =>
      const Stream.empty();

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
      SizeGuardViolation(
        GuardBlocked(resultBytes: 200, limitBytes: 100, op: SaveOp.merge),
      ),
    );
  }

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
  }) async => const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

  @override
  Future<PdfResult<CompressToNewDocumentResult>> compressToNewDocument({
    required CompressSource source,
    required ImageQuality preset,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async => const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

  @override
  Future<PdfResult<CompressToTargetResult>> compressToTargetSize({
    required CompressSource source,
    required int targetBytes,
    void Function(PdfProgress)? onProgress,
    void Function(TargetAttempt)? onAttempt,
    CancelToken? cancelToken,
  }) async => const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

  @override
  Future<PdfResult<DocumentSummary>> rename(
    String docId,
    String newTitle,
  ) async => const PdfErr(UnknownFailure('테스트에서 사용하지 않음'));

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
          appLocaleProvider.overrideWithValue(const Locale('ko')),
        ],
        child: const PdfDaeriApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('작업공간 초기화에 실패했습니다.'), findsOneWidget);
    expect(
      find.text('서류를 스캔하고, 받은 PDF를 열고, 사진을 하나의 문서로 정리하세요.'),
      findsNothing,
    );
    await tester.scrollUntilVisible(find.text('PDF 열기'), 300);
    await tester.pump(const Duration(milliseconds: 300));

    // [2026-09-01 · Windows 포팅 W3] "스캔" 진입점은 `AppFeatures.scan`
    // (Android 전용)이 거짓인 플랫폼에서 렌더 트리에서 제외된다(68 §6) — 이
    // 테스트가 실행되는 호스트가 그 대상일 수 있으므로 조건부로 확인한다.
    if (AppFeatures.scan) {
      expect(find.text('스캔'), findsOneWidget);
      // workspaceProvider/documentRepositoryProvider가 기본값(null)이므로
      // 진입점이 비활성 상태여야 한다(죽지 않되, 쓸 수 없음을 알린다).
      final scanButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '스캔'),
      );
      expect(scanButton.onPressed, isNull);
    } else {
      expect(find.text('스캔'), findsNothing);
    }
    expect(find.text('PDF 열기'), findsOneWidget);
    expect(find.text('사진 → PDF'), findsOneWidget);
  });

  testWidgets('스캔이 불가능하면 "사진 → PDF"로 유도한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanSourceProvider.overrideWithValue(_FakeUnsupportedScanSource()),
        ],
        child: const MaterialApp(
          locale: Locale('ko'),
          supportedLocales: [Locale('ko'), Locale('en')],
          home: ScanScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('사진 → PDF로 계속하기'), findsOneWidget);
  });

  testWidgets('GuardBlocked(용량 검증 실패)를 삼키지 않고 화면에 노출한다', (tester) async {
    // 3주차 T4: SaveImagesScreen(전체 화면)이 `showSaveDialog`(save_dialog.dart)로
    // 대체됐다(설계 §5.1). PhotoEditScreen/EditScreen 대신 저장 다이얼로그를 직접
    // 여는 최소 하네스로 검증한다 — `PageGridEditor`의 실제 이미지 파일 I/O
    // (`File.length()`)는 flutter_test의 FakeAsync 존 안에서 완료되지 않아
    // pumpAndSettle이 멎는다(위젯 테스트 환경의 알려진 제약, dart:io 실 I/O를
    // 화면 전체를 통해 exercise하지 않는다). 이 테스트의 목적은 어디까지나
    // `showSaveDialog`가 `GuardBlocked`를 삼키지 않는지 확인하는 것이다.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(
            _FakeGuardBlockedRepository(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko'), Locale('en')],
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showSaveDialog(
                    context: context,
                    ref: ref,
                    spec: const SaveRequestSpec(
                      suggestedTitle: '테스트 문서',
                      origin: DocOrigin.photo,
                      pages: [],
                      guardInput: GuardInput(
                        op: SaveOp.merge,
                        baselineBytes: 0,
                      ),
                      showQualityPicker: false,
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    // 3주차 T1에서 SizeGuardViolation 문구가 op별로 세분화됐다(FailureUi
    // §6.2). 이 테스트의 목적은 GuardBlocked가 삼켜지지 않고 화면에 뜨는지
    // 확인하는 것이므로, op에 무관하게 항상 뜨는 제목('저장 중단')으로
    // 단언한다 — 특정 op 문구 변경에 테스트가 매번 깨지지 않게 한다.
    expect(find.textContaining('저장 중단'), findsOneWidget);
  });
}
