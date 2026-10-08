/// Google Play 서비스 문서 스캐너 진입점.
///
/// 스캔 UI와 문서 보정은 ML Kit가 담당하고, 이 파일은 보정된 JPEG 한 장을 기존
/// 저장 흐름으로 넘기는 얇은 경계층만 가진다.
library;

import 'dart:developer' as developer;


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_error.dart';
import '../../core/platform_features.dart';

abstract interface class ScanSource {
  Future<bool> isAvailable();

  /// ML Kit에서 정리된 JPEG 경로 한 장을 반환한다.
  Future<PdfResult<List<String>>> scan(
    BuildContext context, {
    int pageLimit = 1,
  });
}

abstract interface class DocumentScanLauncher {
  Future<String?> open();
}

class MethodChannelDocumentScanLauncher implements DocumentScanLauncher {
  const MethodChannelDocumentScanLauncher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.kamanbi.pdf_daeri/document_scanner';
  final MethodChannel _channel;

  @override
  Future<String?> open() => _channel.invokeMethod<String>('start');
}

class GoogleDocumentScanSource implements ScanSource {
  GoogleDocumentScanSource({
    DocumentScanLauncher? launcher,
    bool Function()? isSupported,
  }) : _launcher = launcher ?? const MethodChannelDocumentScanLauncher(),
       _isSupported = isSupported ?? (() => AppFeatures.scan);

  final DocumentScanLauncher _launcher;
  final bool Function() _isSupported;

  @override
  Future<bool> isAvailable() async => _isSupported();

  @override
  Future<PdfResult<List<String>>> scan(
    BuildContext context, {
    int pageLimit = 1,
  }) async {
    if (!await isAvailable()) {
      return const PdfErr(EngineUnsupported('google_document_scanner'));
    }
    if (!context.mounted) return const PdfErr(Cancelled());

    try {
      final imagePath = await _launcher.open();
      if (imagePath == null || imagePath.isEmpty)
        return const PdfErr(Cancelled());
      return PdfOk([imagePath]);
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'Google 문서 스캐너 실행 실패',
        name: 'google_document_scan_source',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return switch (error.code) {
        'UNAVAILABLE' => const PdfErr(
          EngineUnsupported('google_document_scanner'),
        ),
        'IN_PROGRESS' => const PdfErr(ScannerUnavailable('스캔 작업이 이미 진행 중입니다.')),
        'COPY_FAILED' => const PdfErr(
          ScannerUnavailable('스캔 결과를 가져오지 못했습니다. 다시 시도해 주세요.'),
        ),
        _ => PdfErr(UnknownFailure(error.message ?? '문서 스캔에 실패했습니다.')),
      };
    } catch (error, stackTrace) {
      developer.log(
        '예상하지 못한 Google 문서 스캐너 실패',
        name: 'google_document_scan_source',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return const PdfErr(UnknownFailure('문서 스캔에 실패했습니다. 다시 시도해 주세요.'));
    }
  }
}
