library;

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
import '../edit/edit_controller.dart';
import '../edit/save_dialog.dart' show assembleGuardInput;
import 'scan_image_quality.dart';

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
        quality: ImageQuality.high,
        guardInput: assembleGuardInput(op: SaveOp.merge, baselineBytes: bytes),
        cancelToken: CancelToken(),
      );
      if (!mounted) return;
      switch (result) {
        case PdfOk<DocumentSummary>(:final value):
          final exportResult = await _exportOutputs(value);
          if (!mounted) return;
          await _showExportResult(exportResult);
          if (mounted) Navigator.of(context).pop(value);
        case PdfErr<DocumentSummary>(:final failure):
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('저장하지 못했습니다: $failure')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_ScanExportResult> _exportOutputs(DocumentSummary summary) async {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return const _ScanExportResult(
        image: PdfErr(UnknownFailure('작업 저장소를 찾을 수 없습니다.')),
        pdf: PdfErr(UnknownFailure('작업 저장소를 찾을 수 없습니다.')),
      );
    }
    final page = _pages.current.pages.single.ref as ImagePageRef;
    final imageResult = await ref
        .read(publicImageExporterProvider)
        .export(
          PublicImageExportRequest(
            sourceImagePath: page.imagePath,
            fileName: FileName.toJpegFileName(summary.title),
            rotationDegrees: page.rotation,
            jpegQuality: scanJpegQuality,
          ),
        );
    final pdfResult = await ref
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
    final message = switch ((imageFailure, pdfFailure)) {
      (false, false) =>
        '사진은 사진 앱의 Pictures/PDF 대리/스캔 문서에, PDF는 Download/PDF 대리/스캔 문서에 저장했습니다.',
      (true, false) =>
        'PDF는 저장했지만 사진 저장에 실패했습니다.\n${_describeFailure(result.image)}',
      (false, true) =>
        '사진은 저장했지만 PDF 저장에 실패했습니다.\n${_describeFailure(result.pdf)}',
      (true, true) =>
        '앱 안의 문서는 저장됐지만 사진과 PDF의 공용 폴더 저장에 실패했습니다.\n사진: ${_describeFailure(result.image)}\nPDF: ${_describeFailure(result.pdf)}',
    };
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String _describeFailure(PdfResult<void> result) {
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
          decoration: const InputDecoration(
            hintText: '제목',
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '저장 중…' : '저장'),
          ),
        ],
      ),
      body: Column(
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
          TextButton(onPressed: _rotate, child: const Text('사진 회전')),
        ],
      ),
    );
  }
}

class _ScanExportResult {
  const _ScanExportResult({required this.image, required this.pdf});

  final PdfResult<void> image;
  final PdfResult<void> pdf;
}
