/// 스캔 보정 이미지를 Android 공용 사진 보관함으로 내보내는 단일 진입점.
library;

import 'package:flutter/services.dart';

import '../../core/app_error.dart';

class PublicImageExportRequest {
  const PublicImageExportRequest({
    required this.sourceImagePath,
    required this.fileName,
    required this.rotationDegrees,
    required this.jpegQuality,
  });

  final String sourceImagePath;
  final String fileName;
  final int rotationDegrees;
  final int jpegQuality;
}

abstract interface class PublicImageExporter {
  Future<PdfResult<void>> export(PublicImageExportRequest request);
}

class MethodChannelPublicImageExporter implements PublicImageExporter {
  static const _channel = MethodChannel('com.kamanbi.pdf_daeri/storage');

  @override
  Future<PdfResult<void>> export(PublicImageExportRequest request) async {
    try {
      await _channel.invokeMethod<void>('exportImage', {
        'sourceImagePath': request.sourceImagePath,
        'displayName': request.fileName,
        'rotationDegrees': request.rotationDegrees,
        'jpegQuality': request.jpegQuality,
      });
      return const PdfOk(null);
    } on PlatformException catch (error) {
      return PdfErr(UnknownFailure('사진 저장 실패: ${error.message ?? error.code}'));
    } on MissingPluginException {
      return const PdfErr(EngineUnsupported('public_image_export'));
    }
  }
}
