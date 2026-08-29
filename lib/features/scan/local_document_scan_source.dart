/// 로컬 CameraX 문서 스캐너 진입점.
///
/// Google Play 서비스 문서 스캐너를 호출하지 않는다. 문서 모서리를 로컬에서
/// 검출하고, 네 점 원근 보정이 끝난 JPEG만 기존 사진 편집·PDF 흐름으로 넘긴다.
library;

import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';

import '../../core/app_error.dart';
import 'single_document_scanner.dart';

abstract interface class ScanSource {
  Future<bool> isAvailable();

  /// 보정된 JPEG 경로만 반환한다.
  ///
  /// 자동 검출이 어긋나면 스캐너의 네 점 조정 화면에서 다시 보정한다. 원근 보정에
  /// 실패한 원본을 사각형 크롭으로 강등하지 않는다.
  Future<PdfResult<List<String>>> scan(
    BuildContext context, {
    int pageLimit = 30,
  });
}

abstract interface class DocumentScanLauncher {
  Future<List<String>?> open(BuildContext context, {required int pageLimit});
}

/// CameraX의 로컬 윤곽 검출과 Android `Matrix.setPolyToPoly` 보정을 사용한다.
class DoclensDocumentScanLauncher implements DocumentScanLauncher {
  @override
  Future<List<String>?> open(
    BuildContext context, {
    required int pageLimit,
  }) async {
    final correctedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SingleDocumentScanner()),
    );
    if (correctedPath == null || correctedPath.isEmpty) return null;
    return [correctedPath];
  }
}

class LocalDocumentScanSource implements ScanSource {
  LocalDocumentScanSource({
    DocumentScanLauncher? launcher,
    bool Function()? isSupported,
  }) : _launcher = launcher ?? DoclensDocumentScanLauncher(),
       _isSupported = isSupported ?? (() => Platform.isAndroid);

  final DocumentScanLauncher _launcher;
  final bool Function() _isSupported;

  @override
  Future<bool> isAvailable() async => _isSupported();

  @override
  Future<PdfResult<List<String>>> scan(
    BuildContext context, {
    int pageLimit = 30,
  }) async {
    if (!await isAvailable()) {
      return const PdfErr(EngineUnsupported('local_document_scanner'));
    }
    if (!context.mounted) {
      return const PdfErr(Cancelled());
    }

    try {
      final imagePaths = await _launcher.open(context, pageLimit: pageLimit);
      if (imagePaths == null || imagePaths.isEmpty) {
        return const PdfErr(Cancelled());
      }
      return PdfOk(imagePaths);
    } on ScannerPermissionException catch (_) {
      return const PdfErr(PermissionDenied('카메라 접근이 허용되지 않았습니다.'));
    } on ScannerUnavailableException catch (error, stackTrace) {
      developer.log(
        '로컬 문서 스캐너를 사용할 수 없음',
        name: 'local_document_scan_source',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return const PdfErr(EngineUnsupported('local_document_scanner'));
    } on ScannerException catch (error, stackTrace) {
      developer.log(
        '로컬 문서 스캐너 실행 실패',
        name: 'local_document_scan_source',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return PdfErr(UnknownFailure(error.message));
    } catch (error, stackTrace) {
      developer.log(
        '예상하지 못한 로컬 문서 스캐너 실패',
        name: 'local_document_scan_source',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return PdfErr(UnknownFailure('문서 스캔에 실패했습니다. 다시 시도해 주세요.'));
    }
  }
}
