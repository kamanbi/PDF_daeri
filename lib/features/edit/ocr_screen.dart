/// 텍스트 인식(OCR) 화면. (`_workspace/79_architect_v1.1_v2_design.md` §7,
/// §13 배치 5 항목 16)
///
/// 스캔·사진 페이지와 텍스트가 없는 외부 PDF 페이지만 인식한다. 외부 PDF는
/// 인식용 임시 이미지만 렌더하며 저장 결과의 원본 페이지는 래스터화하지 않는다.
///
/// 흐름:
/// ```
/// 문서 페이지 조회(docId) → ImagePageRef 인덱스만 추출
///   → 순차 recognize(§7.5 — 메인 isolate, 페이지 경계마다 진행률·취소 확인)
///   → 전부 빈 결과면 "인식된 텍스트 없음" 안내, 저장하지 않음
///   → ocrResultToStampSpec(페이지별) → buildStampInIsolate → PdfEngine.stamp
///   → stampToNewDocument(<원본 제목> (텍스트 인식)) → "새 파일로 저장됨"
/// ```
///
/// **클립보드 복사 없음** — §10 Q8 미승인, 이번 라운드 범위 밖(§7.1).
///
/// **배너를 넣지 않는다** — `ads.md` 노출 지점표에 없는 화면(규칙 7), 서명·주석
/// 화면과 같은 정책.
///
/// 이 화면은 `AppRoutes`/`router.dart`에 새 라우트로 등록하지 않는다 —
/// `signature_screen.dart`/`annotate_screen.dart`와 같은 방식으로(모달 전체화면
/// 라우트를 직접 push) 호출부(S4 뷰어)에서 [showOcrScreen]을 통해서만 연다.
library;

import '../../app/app_locale.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../billing/entitlement.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/file_name.dart';
import '../../core/korean_font.dart';
import '../../core/save_screen_helpers.dart';
import '../../core/progress.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/ocr_source.dart';
import '../../pdf/ocr_text_layer.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_renderer.dart';
import '../../pdf/stamp_builder.dart';
import '../common/failure_ui.dart';

/// OCR 화면이 필요로 하는 대상 문서 정보. `ViewerArgs`에서 그대로 옮겨 담는다 —
/// 이 화면이 독자적으로 문서 요약을 다시 조회하지 않는다. [docId]는 페이지
/// 구성(`ImagePageRef`/`PdfPageRef`)을 조회하는 데 필수라 non-null이다(§7.1 —
/// 대상 판정 자체가 "내 문서"에서만 가능하다).
class OcrArgs {
  const OcrArgs({
    required this.pdfPath,
    required this.title,
    required this.docId,
    required this.pageCount,
    this.password,
  });

  final String pdfPath;
  final String title;
  final String? docId;
  final int pageCount;
  final String? password;
}

/// OCR 화면을 전체화면으로 연다. 성공하면 새로 만들어진 문서의
/// `DocumentSummary`를, 취소·실패·빈 결과면 `null`을 반환한다.
Future<DocumentSummary?> showOcrScreen({
  required BuildContext context,
  required OcrArgs args,
}) {
  return Navigator.of(context).push<DocumentSummary?>(
    MaterialPageRoute(builder: (_) => OcrScreen(args: args)),
  );
}

enum _Stage { loading, recognizing, empty, saving }

const double _pdfOcrRenderScale = 2;

class OcrScreen extends ConsumerStatefulWidget {
  const OcrScreen({super.key, required this.args});
  final OcrArgs args;

  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> {
  _Stage _stage = _Stage.loading;
  int _pagesDone = 0;
  int _pagesTotal = 0;
  PdfProgress? _saveProgress;
  CancelToken? _cancelToken;
  bool _cancelling = false;
  // initState에서 한 번 얻어 필드로 붙잡아 둔다 — `ref`(WidgetRef)는 위젯이
  // dispose된 뒤 접근하면 예외를 던지지만(`viewer_screen.dart`의 `_busyNotifier`와
  // 같은 이유), 이 참조 자체는 dispose 이후에도 계속 유효하다.
  late final OcrSource _ocrSource;
  // build마다 다시 재는 대신 initState에서 한 번만 판정한다(§4 재감사 L-2).
  late final bool _showCancelButton;

  @override
  void initState() {
    super.initState();
    _ocrSource = ref.read(ocrSourceProvider)();
    _showCancelButton = shouldShowCancelButton(
      pageCount: widget.args.pageCount,
      pdfPath: widget.args.pdfPath,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    // §7.3(providers.dart) 계약 — 플러그인 리소스 해제는 호출부(이 화면) 책임.
    _ocrSource.dispose();
    super.dispose();
  }

  Future<void> _fail(PdfFailure failure) async {
    if (!mounted) return;
    await FailureUi.showDialog(context, failure);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _failMessage(String message) => _fail(UnknownFailure(message));

  Future<void> _failSubscriptionCheck() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(dialogContext, '구독 확인 실패')),
        content: Text(
          appText(dialogContext, '구독 상태를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(appText(dialogContext, '확인')),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _run() async {
    final entitlement = ref.read(ocrEntitlementProvider);
    bool canCreateOcrPdf;
    try {
      canCreateOcrPdf = entitlement.isLoading
          ? await ref.read(ocrEntitlementFutureProvider.future)
          : entitlement.valueOrNull == true;
      if (entitlement.hasError) {
        await _failSubscriptionCheck();
        return;
      }
    } catch (_) {
      await _failSubscriptionCheck();
      return;
    }
    if (!mounted) return;
    if (!canCreateOcrPdf) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(appText(dialogContext, '구독이 필요합니다')),
          content: Text(appText(dialogContext, '텍스트 인식은 활성 구독이 필요합니다.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(appText(dialogContext, '확인')),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final repo = ref.read(documentRepositoryProvider);
    final renderer = ref.read(pdfRendererProvider);
    if (repo == null) {
      await _failMessage('저장소를 사용할 수 없습니다.');
      return;
    }

    final docId = widget.args.docId;
    List<PageRef> pages = [];
    if (docId != null) {
      final detailResult = await repo.load(docId);
      if (!mounted) return;
      if (detailResult is PdfErr<DocumentDetail>) {
        await _fail(detailResult.failure);
        return;
      }
      pages = (detailResult as PdfOk<DocumentDetail>).value.pages;
    }

    final geometryResult = await renderer.pageGeometry(
      widget.args.pdfPath,
      password: widget.args.password,
    );
    if (!mounted) return;
    if (geometryResult is PdfErr<PdfPageGeometry>) {
      await _fail(geometryResult.failure);
      return;
    }
    final geometry = (geometryResult as PdfOk<PdfPageGeometry>).value;
    if (docId == null) {
      pages = List.generate(
        geometry.pageCount,
        (index) => PdfPageRef(
          sourcePath: widget.args.pdfPath,
          sourceIndex: index,
          rotation: 0,
        ),
      );
    }

    // 스캔·사진 페이지와 텍스트가 없는 PDF 페이지가 인식 대상이다.
    final imageIndices = <int>[];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i] is ImagePageRef) {
        imageIndices.add(i);
        continue;
      }
      final textResult = await renderer.pageText(
        pdfPath: widget.args.pdfPath,
        pageIndex: i,
        password: widget.args.password,
      );
      if (!mounted) return;
      if (textResult is PdfErr<PdfPageTextData>) {
        await _fail(textResult.failure);
        return;
      }
      if ((textResult as PdfOk<PdfPageTextData>).value.text.trim().isEmpty) {
        imageIndices.add(i);
      }
    }

    if (imageIndices.isEmpty) {
      if (!mounted) return;
      setState(() => _stage = _Stage.empty);
      return;
    }

    setState(() {
      _stage = _Stage.recognizing;
      _pagesDone = 0;
      _pagesTotal = imageIndices.length;
    });

    final ocrSource = _ocrSource;
    final token = CancelToken();
    _cancelToken = token;

    // 페이지 수만큼 순차 recognize(§7.5). 중간 취소는 불가 — 페이지 경계에서만
    // `token.isCancelled`를 확인한다.
    final results = <int, OcrPageResult>{};
    Directory? tempDir;
    try {
      for (final index in imageIndices) {
        if (token.isCancelled) break;
        final page = pages[index];
        String imagePath;
        if (page is ImagePageRef) {
          imagePath = page.imagePath;
        } else {
          final widthPt = geometry.sizes[index].widthPt;
          final rendered = await renderer.renderPage(
            pdfPath: widget.args.pdfPath,
            pageIndex: index,
            targetWidthPx: (widthPt * _pdfOcrRenderScale).round(),
            password: widget.args.password,
            cancelToken: token,
          );
          if (!mounted) return;
          if (rendered is PdfErr<Uint8List>) {
            await _fail(rendered.failure);
            return;
          }
          tempDir ??= await Directory.systemTemp.createTemp('pdf_daeri_ocr_');
          imagePath = '${tempDir.path}/page_$index.png';
          await File(
            imagePath,
          ).writeAsBytes((rendered as PdfOk<Uint8List>).value);
        }
        final recognizeResult = await ocrSource.recognize(imagePath);
        if (!mounted) return;
        if (token.isCancelled) break;
        if (recognizeResult is PdfErr<OcrPageResult>) {
          await _fail(recognizeResult.failure);
          return;
        }
        results[index] = (recognizeResult as PdfOk<OcrPageResult>).value;
        setState(() => _pagesDone++);
      }
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }

    if (!mounted) return;
    if (token.isCancelled) {
      Navigator.of(context).pop();
      return;
    }

    final hasAnyWord = results.values.any((r) => r.words.isNotEmpty);
    if (!hasAnyWord) {
      setState(() => _stage = _Stage.empty);
      return;
    }

    Uint8List? koreanFontBytes;
    try {
      koreanFontBytes = await KoreanFont.bytes();
    } on KoreanFontMissing {
      await _failMessage('한글 폰트를 불러오지 못해 텍스트 인식 결과를 저장할 수 없습니다.');
      return;
    }
    if (!mounted) return;

    // 대상 페이지에는 인식 결과를, 그 외 페이지는 빈 스펙으로 채운다 — 페이지
    // 정렬이 어긋나지 않게 페이지 수만큼 반드시 채운다(§2.2 원칙, 서명·주석과 동일).
    final pageSpecs = <StampPageSpec>[];
    for (var i = 0; i < geometry.pageCount; i++) {
      final ocrResult = results[i];
      if (ocrResult == null) {
        pageSpecs.add(
          StampPageSpec(
            widthPt: geometry.sizes[i].widthPt,
            heightPt: geometry.sizes[i].heightPt,
            marks: const [],
          ),
        );
        continue;
      }
      final layer = ocrResultToStampSpec(
        ocrResult: ocrResult,
        widthPt: geometry.sizes[i].widthPt,
        heightPt: geometry.sizes[i].heightPt,
        koreanFontBytes: koreanFontBytes,
      );
      if (layer.error != null || layer.spec == null) {
        await _failMessage('텍스트 인식 결과를 적용하지 못했습니다.');
        return;
      }
      pageSpecs.add(layer.spec!);
    }

    if (!mounted) return;
    setState(() {
      _stage = _Stage.saving;
      _saveProgress = null;
      _cancelling = false;
    });

    final buildResult = await buildStampInIsolate(
      pages: pageSpecs,
      koreanFontBytes: koreanFontBytes,
    );
    if (!mounted) return;
    if (buildResult.error != null || buildResult.pdfBytes == null) {
      await _failMessage('텍스트 인식 레이어를 적용하지 못했습니다.');
      return;
    }

    final baselineBytes = File(widget.args.pdfPath).lengthSync();
    final saveToken = CancelToken();
    _cancelToken = saveToken;
    final result = await repo.stampToNewDocument(
      sourcePdfPath: widget.args.pdfPath,
      originalTitle: widget.args.title,
      stampPdfBytes: buildResult.pdfBytes!,
      pageCount: geometry.pageCount,
      baselineBytes: baselineBytes,
      titleFor: FileName.ocrTitle,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _saveProgress = p);
      },
      cancelToken: saveToken,
    );

    if (!mounted) return;
    switch (result) {
      case PdfOk<DocumentSummary>(:final value):
        Navigator.of(context).pop(value);
      case PdfErr<DocumentSummary>(:final failure):
        if (failure is! Cancelled) {
          await FailureUi.showDialog(context, failure);
        }
        if (!mounted) return;
        Navigator.of(context).pop();
    }
  }

  void _cancel() {
    setState(() => _cancelling = true);
    _cancelToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context, '텍스트 인식'))),
      body: switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator()),
        _Stage.recognizing => _buildRecognizing(context),
        _Stage.empty => _buildEmpty(context),
        _Stage.saving => _buildSaving(context),
      },
    );
  }

  Widget _buildRecognizing(BuildContext context) {
    final fraction = _pagesTotal == 0 ? 0.0 : _pagesDone / _pagesTotal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appText(context, '{done}/{total} 페이지 인식 중')
                  .replaceAll('{done}', '$_pagesDone')
                  .replaceAll('{total}', '$_pagesTotal'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: fraction == 0 ? null : fraction),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancelling ? null : _cancel,
              child: Text(appText(context, _cancelling ? '취소 중…' : '취소')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(appText(context, '인식된 텍스트가 없습니다.')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(appText(context, '확인')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaving(BuildContext context) {
    final fraction = _saveProgress?.fraction ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appText(context, '저장 중…'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: fraction == 0 ? null : fraction),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${(fraction * 100).round()}%'),
                if (_showCancelButton) ...[
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: _cancelling ? null : _cancel,
                    child: Text(appText(context, _cancelling ? '취소 중…' : '취소')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
