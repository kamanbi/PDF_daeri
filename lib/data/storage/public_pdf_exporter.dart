/// 공용 Documents 폴더로 PDF 사본을 내보내는 단일 진입점.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_error.dart';
import '../../core/file_name.dart';

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

/// Windows: MediaStore가 없으므로 사용자 `문서(Documents)` 폴더 아래 카테고리
/// 폴더에 직접 쓴다. (68 §3.4) `getApplicationDocumentsDirectory()`는
/// `path_provider_windows`에서 실제 사용자 `내 문서` 폴더를 가리킨다 —
/// Android에서는 앱 전용 내부 저장소를 가리키므로 이 구현체를 Android에
/// 쓰면 안 된다(그래서 `AppFeatures`/`Platform.isWindows`가 선택을 소유한다,
/// `lib/app/providers.dart`).
class FileSystemPublicPdfExporter implements PublicPdfExporter {
  @override
  Future<PdfResult<void>> export(PublicPdfExportRequest request) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final categoryFolder = switch (request.category) {
        PublicPdfCategory.scanned => '스캔 문서',
        PublicPdfCategory.modified => '수정 PDF',
      };
      final targetDir = Directory(
        p.join(documentsDir.path, 'PDF 대리', categoryFolder),
      );
      await targetDir.create(recursive: true);

      final uniqueFileName = await _uniqueFileName(targetDir, request.fileName);
      await File(request.sourcePdfPath).copy(p.join(targetDir.path, uniqueFileName));
      return const PdfOk(null);
    } catch (e) {
      return PdfErr(UnknownFailure('기본 폴더 복사 실패: $e'));
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
