/// Android 공용 Documents 폴더로 PDF 사본을 내보내는 단일 진입점.
library;

import 'package:flutter/services.dart';

import '../../core/app_error.dart';

enum PublicPdfCategory { scanned, modified }

class PublicPdfExportRequest {
  const PublicPdfExportRequest({
    required this.sourcePdfPath,
    required this.fileName,
    required this.category,
  });

  final String sourcePdfPath;
  final String fileName;
  final PublicPdfCategory category;
}

abstract interface class PublicPdfExporter {
  Future<PdfResult<void>> export(PublicPdfExportRequest request);
}

class MethodChannelPublicPdfExporter implements PublicPdfExporter {
  static const _channel = MethodChannel('com.kamanbi.pdf_daeri/storage');

  @override
  Future<PdfResult<void>> export(PublicPdfExportRequest request) async {
    try {
      await _channel.invokeMethod<void>('exportPdf', {
        'sourcePdfPath': request.sourcePdfPath,
        'displayName': request.fileName,
        'folder': switch (request.category) {
          PublicPdfCategory.scanned => '스캔 문서',
          PublicPdfCategory.modified => '수정 PDF',
        },
      });
      return const PdfOk(null);
    } on PlatformException catch (error) {
      return PdfErr(
        UnknownFailure('기본 폴더 복사 실패: ${error.message ?? error.code}'),
      );
    } on MissingPluginException {
      return const PdfErr(EngineUnsupported('public_pdf_export'));
    }
  }
}
