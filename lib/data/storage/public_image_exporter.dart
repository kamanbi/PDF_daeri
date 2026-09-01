/// 스캔 보정 이미지를 공용 사진 보관함으로 내보내는 단일 진입점.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_error.dart';
import '../../core/file_name.dart';

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

/// Windows: MediaStore가 없으므로 사용자 `문서(Documents)` 폴더 아래
/// `PDF 대리/`에 직접 쓴다. (68 §3.4) 회전·재인코딩은 기존 네이티브 구현과
/// 동등하게 이 구현체가 직접 수행한다.
class FileSystemPublicImageExporter implements PublicImageExporter {
  @override
  Future<PdfResult<void>> export(PublicImageExportRequest request) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(documentsDir.path, 'PDF 대리'));
      await targetDir.create(recursive: true);

      final bytes = await File(request.sourceImagePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) {
        return const PdfErr(UnknownFailure('사진 저장 실패: 이미지를 디코드할 수 없습니다'));
      }
      if (request.rotationDegrees != 0) {
        image = img.copyRotate(image, angle: request.rotationDegrees);
      }
      final encoded = img.encodeJpg(image, quality: request.jpegQuality);

      final uniqueFileName = await _uniqueFileName(targetDir, request.fileName);
      await File(p.join(targetDir.path, uniqueFileName)).writeAsBytes(encoded);
      return const PdfOk(null);
    } catch (e) {
      return PdfErr(UnknownFailure('사진 저장 실패: $e'));
    }
  }
}

/// 대상 디렉터리의 기존 파일명과 충돌하지 않는 파일명을 만든다. 정규화·중복
/// 회피 규칙 자체는 `FileName`(`lib/core/file_name.dart`)에 위임한다 — 여기서
/// 두 번째 규칙을 만들지 않는다.
Future<String> _uniqueFileName(Directory dir, String fileName) async {
  final ext = p.extension(fileName);
  final base = FileName.normalize(p.basenameWithoutExtension(fileName));
  final existing = <String>{};
  if (await dir.exists()) {
    await for (final entity in dir.list()) {
      if (entity is File) {
        existing.add(p.basenameWithoutExtension(entity.path));
      }
    }
  }
  final deduped = FileName.dedupe(base, existing);
  return '$deduped$ext';
}
