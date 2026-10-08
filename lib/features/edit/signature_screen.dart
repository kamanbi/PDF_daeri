/// 전자서명 화면. (`_workspace/79_architect_v1.1_v2_design.md` §3.3·§3.4, §13 배치 2 항목 6)
///
/// **법적 전자서명이 아니다.** 손으로 그린 서명 이미지를 페이지 위에 얹는
/// 시각적 표시일 뿐이다(§3.1 범위 확정, Q4 승인 문구).
///
/// 흐름:
/// ```
/// 저장된 서명 있음(hasSignature()) → 바로 배치 화면
/// 저장된 서명 없음 → 그리기 캔버스 → [완료] → writeSignature 저장 → 배치 화면
/// 배치 화면 → [저장] → buildStampInIsolate(ImageMark) → PdfEngine.stamp
///   → 새 문서로 저장(<원본 제목> (서명)) → "새 파일로 저장됨"
/// ```
///
/// **`third_party/doclens`와 무관하다** — 카메라·문서 보정이 아니라 빈 캔버스
/// 드로잉이므로 절대 규칙 5(스캔 UI 산발 신설 금지)의 대상이 아니다.
///
/// **배너를 넣지 않는다.** 드로잉·드래그 제스처와 배너가 만나는 화면을 만들지
/// 않는다(`ads.md` 노출 지점표에 없는 화면 = 배너 없음, 규칙 7).
///
/// 이 화면은 `AppRoutes`/`router.dart`에 새 라우트로 등록하지 않는다 —
/// `router.dart` 헤더 주석의 "screens.md의 5개 화면 외 라우트를 정의하지
/// 않는다" 불변식을 지키기 위해, `compress_sheet.dart`/`save_dialog.dart`와
/// 같은 방식으로(모달 전체화면 라우트를 직접 push) 호출부(S4 뷰어)에서
/// [showSignatureScreen]을 통해서만 연다.
library;

import '../../app/app_locale.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/progress.dart';
import '../../core/save_screen_helpers.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/pdf_renderer.dart';
import '../../pdf/stamp_builder.dart';
import '../common/failure_ui.dart';
import 'stamp_placement.dart';

/// 서명 화면이 필요로 하는 대상 문서 정보. `ViewerArgs`에서 그대로 옮겨 담는다 —
/// 이 화면이 독자적으로 문서를 다시 조회하지 않는다.
class SignatureArgs {
  const SignatureArgs({
    required this.pdfPath,
    required this.title,
    required this.pageCount,
    required this.initialPageIndex,
    this.password,
  });

  final String pdfPath;
  final String title;
  final int pageCount;
  final int initialPageIndex;
  final String? password;
}

/// 서명 화면을 전체화면으로 연다. 성공하면 새로 만들어진 문서의
/// `DocumentSummary`를, 취소·실패면 `null`을 반환한다.
Future<DocumentSummary?> showSignatureScreen({
  required BuildContext context,
  required SignatureArgs args,
}) {
  return Navigator.of(context).push<DocumentSummary?>(
    MaterialPageRoute(builder: (_) => SignatureScreen(args: args)),
  );
}

enum _Stage { loading, drawing, placing, saving }

class SignatureScreen extends ConsumerStatefulWidget {
  const SignatureScreen({super.key, required this.args});
  final SignatureArgs args;

  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  _Stage _stage = _Stage.loading;
  Uint8List? _signaturePng;
  Uint8List? _pageBytes;
  PdfPageGeometry? _geometry;
  StampRect _rect = defaultStampRect();
  PdfProgress? _progress;
  CancelToken? _cancelToken;
  bool _cancelling = false;
  // build마다 다시 재는 대신 initState에서 한 번만 판정한다(§4 재감사 L-2).
  late final bool _showCancelButton;

  @override
  void initState() {
    super.initState();
    _showCancelButton = shouldShowCancelButton(
      pageCount: widget.args.pageCount,
      pdfPath: widget.args.pdfPath,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final workspace = ref.read(workspaceProvider);
    final renderer = ref.read(pdfRendererProvider);

    final geometryResult = await renderer.pageGeometry(
      widget.args.pdfPath,
      password: widget.args.password,
    );
    if (!mounted) return;
    if (geometryResult is PdfErr<PdfPageGeometry>) {
      await FailureUi.showDialog(context, geometryResult.failure);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _geometry = (geometryResult as PdfOk<PdfPageGeometry>).value;

    final hasSaved = workspace != null && await workspace.hasSignature();
    if (hasSaved) {
      final bytes = await File(workspace.signaturePath).readAsBytes();
      if (!mounted) return;
      _signaturePng = bytes;
      await _loadPagePreview();
      if (!mounted) return;
      setState(() => _stage = _Stage.placing);
    } else {
      if (!mounted) return;
      setState(() => _stage = _Stage.drawing);
    }
  }

  Future<void> _loadPagePreview() async {
    final renderer = ref.read(pdfRendererProvider);
    final result = await renderer.renderPage(
      pdfPath: widget.args.pdfPath,
      pageIndex: widget.args.initialPageIndex,
      targetWidthPx: 900,
      password: widget.args.password,
    );
    if (!mounted) return;
    if (result is PdfOk<Uint8List>) {
      setState(() => _pageBytes = result.value);
    }
  }

  Future<void> _onDrawingDone(Uint8List pngBytes) async {
    final workspace = ref.read(workspaceProvider);
    if (workspace != null) {
      await workspace.writeSignature(pngBytes);
    }
    if (!mounted) return;
    setState(() => _signaturePng = pngBytes);
    await _loadPagePreview();
    if (!mounted) return;
    setState(() => _stage = _Stage.placing);
  }

  Future<void> _redraw() async {
    final workspace = ref.read(workspaceProvider);
    if (workspace != null) {
      await workspace.clearSignature();
    }
    if (!mounted) return;
    setState(() {
      _signaturePng = null;
      _stage = _Stage.drawing;
      _rect = defaultStampRect();
    });
  }


  Future<void> _save() async {
    final geometry = _geometry;
    final signature = _signaturePng;
    if (geometry == null || signature == null) return;

    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) {
      await FailureUi.showDialog(
        context,
        const UnknownFailure('저장소를 사용할 수 없습니다.'),
      );
      return;
    }

    final token = CancelToken();
    setState(() {
      _stage = _Stage.saving;
      _progress = null;
      _cancelToken = token;
      _cancelling = false;
    });

    // 대상 페이지에만 ImageMark를, 그 외 페이지는 빈 스펙으로 만든다 — 페이지
    // 정렬이 어긋나지 않게 페이지 수만큼 반드시 채운다(§2.2).
    final pageSpecs = [
      for (var i = 0; i < geometry.pageCount; i++)
        StampPageSpec(
          widthPt: geometry.sizes[i].widthPt,
          heightPt: geometry.sizes[i].heightPt,
          marks: i == widget.args.initialPageIndex
              ? [ImageMark(rect: _rect, pngBytes: signature)]
              : const [],
        ),
    ];

    // 워커 isolate 실행은 `stamp_builder.dart`가 소유한다(검사35 — 화면이
    // StampBuilder.build를 직접 부르지 않는다). `buildStampInIsolate`는 그
    // 경계를 지키는 유일한 진입점이다.
    final buildResult = await buildStampInIsolate(pages: pageSpecs);

    if (!mounted) return;
    if (buildResult.error != null) {
      setState(() => _stage = _Stage.placing);
      await FailureUi.showDialog(
        context,
        const UnknownFailure('서명을 적용하지 못했습니다.'),
      );
      return;
    }

    final baselineBytes = File(widget.args.pdfPath).lengthSync();
    final result = await repo.stampToNewDocument(
      sourcePdfPath: widget.args.pdfPath,
      originalTitle: widget.args.title,
      stampPdfBytes: buildResult.pdfBytes!,
      pageCount: geometry.pageCount,
      baselineBytes: baselineBytes,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      cancelToken: token,
    );

    if (!mounted) return;
    switch (result) {
      case PdfOk<DocumentSummary>(:final value):
        Navigator.of(context).pop(value);
      case PdfErr<DocumentSummary>(:final failure):
        setState(() => _stage = _Stage.placing);
        if (failure is! Cancelled) {
          await FailureUi.showDialog(context, failure);
        }
    }
  }

  void _cancel() {
    setState(() => _cancelling = true);
    _cancelToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context, '서명 추가'))),
      body: switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator()),
        _Stage.drawing => _DrawingView(onDone: _onDrawingDone),
        _Stage.placing => _buildPlacing(context),
        _Stage.saving => _buildSaving(context),
      },
    );
  }

  Widget _buildPlacing(BuildContext context) {
    final signature = _signaturePng;
    final pageBytes = _pageBytes;
    final geometry = _geometry;
    if (signature == null || geometry == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = geometry.sizes[widget.args.initialPageIndex];
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: pageBytes == null
                ? Center(child: CircularProgressIndicator())
                : StampPlacement(
                    pageAspectRatio: size.aspectRatio,
                    pageChild: Image.memory(pageBytes, fit: BoxFit.contain),
                    overlayChild: Image.memory(signature, fit: BoxFit.fill),
                    rect: _rect,
                    onRectChanged: (rect) => setState(() => _rect = rect),
                  ),
          ),
        ),
        const _LegalNotice(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              TextButton(onPressed: _redraw, child: Text(appText(context, '다시 그리기'))),
              const Spacer(),
              FilledButton(onPressed: _save, child: Text(appText(context, '저장'))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaving(BuildContext context) {
    final fraction = _progress?.fraction ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(appText(context, '저장 중…'), style: Theme.of(context).textTheme.titleLarge),
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

/// 법적 효력 없음 명시 문구(Q4 승인). 간결하게 한 줄로만 표시한다.
class _LegalNotice extends StatelessWidget {
  const _LegalNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        appText(context, '이 서명은 법적 효력이 없으며 단순 표시용입니다.'),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

/// 서명 그리기 캔버스. 굵기·색 고정, 되돌리기 1개 + 전체 지우기 1개만
/// (`screens.md` UX 원칙 "메뉴는 꼭 필요한 항목만").
class _DrawingView extends StatefulWidget {
  const _DrawingView({required this.onDone});
  final ValueChanged<Uint8List> onDone;

  @override
  State<_DrawingView> createState() => _DrawingViewState();
}

class _DrawingViewState extends State<_DrawingView> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  bool _capturing = false;

  void _onPanStart(DragStartDetails details) {
    setState(() => _strokes.add([details.localPosition]));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(details.localPosition));
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    setState(() => _strokes.clear());
  }

  Future<void> _done() async {
    if (_strokes.isEmpty || _capturing) return;
    setState(() => _capturing = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      widget.onDone(byteData.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: _boundaryKey,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                child: Container(
                  color: Colors.transparent,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _SignaturePainter(_strokes),
                  ),
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: const _LegalNotice(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              TextButton(
                onPressed: _strokes.isEmpty ? null : _undo,
                child: Text(appText(context, '되돌리기')),
              ),
              TextButton(
                onPressed: _strokes.isEmpty ? null : _clear,
                child: Text(appText(context, '전체 지우기')),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _strokes.isEmpty || _capturing ? null : _done,
                child: Text(appText(context, '완료')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

