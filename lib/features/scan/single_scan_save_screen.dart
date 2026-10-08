library;

import '../../app/app_locale.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/file_name.dart';
import '../../core/size_guard.dart';
import '../../data/repository/document_repository.dart';
import '../../data/storage/public_image_exporter.dart';
import '../../data/storage/public_pdf_exporter.dart';
import '../../pdf/image_quality.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/scan_quality_advisor.dart';
import '../common/failure_ui.dart';
import '../edit/edit_controller.dart';
import '../edit/save_dialog.dart' show assembleGuardInput;
import 'scan_advice_loader.dart';
import 'scan_advice_widgets.dart';
import 'scan_image_quality.dart';
import 'scan_screen.dart';

class SingleScanSaveScreen extends ConsumerStatefulWidget {
  const SingleScanSaveScreen({
    super.key,
    required this.imagePath,
    required this.suggestedTitle,
  });

  final String imagePath;
  final String suggestedTitle;

  @override
  ConsumerState<SingleScanSaveScreen> createState() =>
      _SingleScanSaveScreenState();
}

class _SingleScanSaveScreenState extends ConsumerState<SingleScanSaveScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.suggestedTitle,
  );
  late final EditController _pages = EditController(initial: const [])
    ..insertImages([widget.imagePath]);
  var _saving = false;
  var _format = _SaveFormat.pdf;
  var _quality = ImageQuality.high;
  late final Future<ScanAdvice?> _advice = loadScanAdvice([widget.imagePath]);

  @override
  void dispose() {
    _title.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _rotate() {
    final page = _pages.current.pages.single;
    _pages.enterSelectMode(page.id);
    _pages.rotateSelected();
    _pages.clearSelection();
    setState(() {});
  }

  void _retake() {
    if (_saving) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final repository = ref.read(documentRepositoryProvider);
    if (repository == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await File(widget.imagePath).length();
      final result = await repository.createDocument(
        title: _title.text.trim().isEmpty
            ? widget.suggestedTitle
            : _title.text.trim(),
        origin: DocOrigin.scan,
        pages: _pages.toPageRefs(),
        quality: _quality,
        guardInput: assembleGuardInput(op: SaveOp.merge, baselineBytes: bytes),
        cancelToken: CancelToken(),
      );
      if (!mounted) return;
      switch (result) {
        case PdfOk<DocumentSummary>(:final value):
          final exportResult = await _exportOutputs(value);
          if (!mounted) return;
          await _showExportResult(exportResult);
          if (mounted) {
            Navigator.of(context).pop(value);
            unawaited(
              ref
                  .read(reviewPromptServiceProvider)
                  .recordSuccessfulPdfCreation(),
            );
          }
        case PdfErr<DocumentSummary>(:final failure):
          debugPrint('scan save failed: $failure');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                appText(context, '저장하지 못했습니다: {error}').replaceAll(
                  '{error}',
                  appText(context, FailureUi.message(failure)),
                ),
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_ScanExportResult> _exportOutputs(DocumentSummary summary) async {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return _ScanExportResult(
        image: _format.includesImage
            ? const PdfErr(UnknownFailure('작업 저장소를 찾을 수 없습니다.'))
            : null,
        pdf: _format.includesPdf
            ? const PdfErr(UnknownFailure('작업 저장소를 찾을 수 없습니다.'))
            : null,
      );
    }
    final page = _pages.current.pages.single.ref as ImagePageRef;
    final imageResult = !_format.includesImage
        ? null
        : await ref
              .read(publicImageExporterProvider)
              .export(
                PublicImageExportRequest(
                  sourceImagePath: page.imagePath,
                  fileName: FileName.toJpegFileName(summary.title),
                  rotationDegrees: page.rotation,
                  jpegQuality: scanJpegQuality,
                ),
              );
    final pdfResult = !_format.includesPdf
        ? null
        : await ref
              .read(publicPdfExporterProvider)
              .export(
                PublicPdfExportRequest(
                  sourcePdfPath: workspace.docPdf(summary.id),
                  fileName: FileName.toFileName(summary.title),
                  category: PublicPdfCategory.scanned,
                ),
              );
    return _ScanExportResult(image: imageResult, pdf: pdfResult);
  }

  Future<void> _showExportResult(_ScanExportResult result) {
    final imageFailure = result.image is PdfErr<void>;
    final pdfFailure = result.pdf is PdfErr<void>;
    final title = imageFailure || pdfFailure ? '저장 결과' : '저장 완료';
    final message = switch (_format) {
      _SaveFormat.pdf => pdfFailure
          ? '${appText(context, 'PDF 저장에 실패했습니다.')}\n${_describeFailure(result.pdf)}'
          : appText(context, 'PDF로 저장했습니다. (Download/PDF 대리/스캔 문서)'),
      _SaveFormat.photo => imageFailure
          ? '${appText(context, '사진 저장에 실패했습니다.')}\n${_describeFailure(result.image)}'
          : appText(context, '사진으로 저장했습니다. (Pictures/PDF 대리/스캔 문서)'),
      _SaveFormat.both => switch ((imageFailure, pdfFailure)) {
        (false, false) => appText(context,
          '사진은 사진 앱의 Pictures/PDF 대리/스캔 문서에, PDF는 Download/PDF 대리/스캔 문서에 저장했습니다.'),
        (true, false) =>
          '${appText(context, 'PDF는 저장했지만 사진 저장에 실패했습니다.')}\n${_describeFailure(result.image)}',
        (false, true) =>
          '${appText(context, '사진은 저장했지만 PDF 저장에 실패했습니다.')}\n${_describeFailure(result.pdf)}',
        (true, true) =>
          '${appText(context, '앱 안의 문서는 저장됐지만 사진과 PDF의 공용 폴더 저장에 실패했습니다.')}\n${appText(context, '사진')}: ${_describeFailure(result.image)}\nPDF: ${_describeFailure(result.pdf)}',
      },
    };
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(appText(context, title)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText(context, '확인')),
          ),
        ],
      ),
    );
  }

  String _describeFailure(PdfResult<void>? result) {
    if (result case PdfErr<void>(:final failure)) return failure.toString();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages.current.pages.single.ref as ImagePageRef;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _title,
          decoration: InputDecoration(
            hintText: appText(context, '제목'),
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(appText(context, _saving ? '저장 중…' : '저장')),
          ),
        ],
      ),
      // 시스템 내비게이션 바(제스처/3버튼) 없이 두면 "사진 회전" 버튼이 화면 맨
      // 아래에 붙어 가려진다 — SafeArea로 하단 여백을 확보한다.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Transform.rotate(
                  angle: page.rotation * math.pi / 180,
                  child: Image.file(File(page.imagePath), fit: BoxFit.contain),
                ),
              ),
            ),
            const Divider(height: 1),
            FutureBuilder<ScanAdvice?>(
              future: _advice,
              builder: (context, snapshot) {
                final loading = snapshot.connectionState != ConnectionState.done;
                final advice = snapshot.data;
                final fmt = advice?.format;
                final q = advice?.quality;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScanAdviceHint(
                      loading: loading,
                      advice: advice,
                      includeFormat: true,
                      onRetake: _retake,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: SegmentedButton<_SaveFormat>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: _SaveFormat.pdf,
                            label: AdviceSegmentLabel(
                              label: appText(context, 'PDF'),
                              recommended: fmt == ScanFormatAdvice.pdf,
                            ),
                          ),
                          ButtonSegment(
                            value: _SaveFormat.photo,
                            label: AdviceSegmentLabel(
                              label: appText(context, '사진'),
                              recommended: fmt == ScanFormatAdvice.photo,
                            ),
                          ),
                          ButtonSegment(
                            value: _SaveFormat.both,
                            label: AdviceSegmentLabel(
                              label: appText(context, '둘 다'),
                              recommended: false,
                            ),
                          ),
                        ],
                        selected: {_format},
                        onSelectionChanged: _saving
                            ? null
                            : (v) => setState(() => _format = v.first),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<ImageQuality>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: ImageQuality.original,
                            label: AdviceSegmentLabel(
                              label: appText(context, '원본'),
                              recommended: q == ImageQuality.original,
                            ),
                          ),
                          ButtonSegment(
                            value: ImageQuality.high,
                            label: AdviceSegmentLabel(
                              label: appText(context, '고화질'),
                              recommended: q == ImageQuality.high,
                            ),
                          ),
                          ButtonSegment(
                            value: ImageQuality.standard,
                            label: AdviceSegmentLabel(
                              label: appText(context, '기본'),
                              recommended: q == ImageQuality.standard,
                            ),
                          ),
                          ButtonSegment(
                            value: ImageQuality.min,
                            label: AdviceSegmentLabel(
                              label: appText(context, '최소'),
                              recommended: false,
                            ),
                          ),
                        ],
                        selected: {_quality},
                        onSelectionChanged: _saving
                            ? null
                            : (v) => setState(() => _quality = v.first),
                      ),
                    ),
                  ],
                );
              },
            ),
            TextButton(onPressed: _rotate, child: Text(appText(context, '사진 회전'))),
          ],
        ),
      ),
    );
  }
}

class _ScanExportResult {
  const _ScanExportResult({required this.image, required this.pdf});

  final PdfResult<void>? image;
  final PdfResult<void>? pdf;
}

enum _SaveFormat {
  pdf,
  photo,
  both;

  bool get includesPdf => this != photo;
  bool get includesImage => this != pdf;
}
