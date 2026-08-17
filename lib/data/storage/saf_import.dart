/// `content://` URI 수신·표시명 추출·앱 작업공간 복사. (설계 §1.2, §11 W6)
///
/// 셋 다 이 파일이 소유한다: ① 인텐트로 전달된 `content://` URI를 받는다
/// (콜드 스타트로 앱을 연 경우 + 이미 떠 있는 앱에 새 인텐트가 도착한 경우)
/// ② 표시명(display name)을 추출한다 ③ 워크스페이스 경로로 복사한다.
///
/// **원본을 수정하지 않는다(절대 규칙 6).** 복사만 하며, `content://` URI에
/// 대해 `takePersistableUriPermission` 등 지속 권한을 요청하지 않는다 — 인텐트가
/// 부여한 일회성 grant로 이 호출 동안의 복사에는 충분하다.
library;

import 'package:flutter/services.dart'
    show EventChannel, MethodChannel, MissingPluginException, PlatformException;

import '../../core/app_error.dart';

abstract interface class SafImporter {
  /// 콜드 스타트로 앱을 연 `application/pdf` VIEW 인텐트의 `content://` URI.
  /// 없으면 `null`. **한 번 호출하면 네이티브 쪽에서 소비된다** — 같은 실행 중에
  /// 다시 호출하면 `null`이 온다(화면 재구성 시 같은 문서를 중복 임포트하지
  /// 않기 위함). 앱 시작 시 1회 호출한다.
  Future<String?> takeInitialUri();

  /// 앱이 이미 실행 중일 때(포그라운드) 새로 도착하는 VIEW 인텐트의
  /// `content://` URI 스트림. 구독을 유지하는 동안 계속 이벤트를 받는다.
  Stream<String> onNewIntentUri();

  /// [contentUri]가 가리키는 파일을 [destinationPath]로 복사하고 원본 표시명을
  /// 반환한다. [destinationPath]의 상위 디렉터리가 없으면 만든다.
  ///
  /// 표시명 조회가 실패해도(권한·프로바이더 문제) 복사 자체는 계속 시도한다 —
  /// [SafImportResult.displayName]이 `null`이면 호출자가 `FileName.normalize`로
  /// 대체 이름을 만든다.
  Future<PdfResult<SafImportResult>> importToPath({
    required String contentUri,
    required String destinationPath,
  });
}

class SafImportResult {
  const SafImportResult({required this.displayName, required this.bytes});

  /// 원본 파일의 표시명(한글 원문 그대로). 추출 실패 시 `null`.
  final String? displayName;
  final int bytes;
}

class MethodChannelSafImporter implements SafImporter {
  static const MethodChannel _safChannel = MethodChannel('com.kamanbi.pdf_daeri/saf');
  static const MethodChannel _intentMethodChannel = MethodChannel('com.kamanbi.pdf_daeri/intent');
  static const EventChannel _intentEventChannel = EventChannel('com.kamanbi.pdf_daeri/intent/stream');

  @override
  Future<String?> takeInitialUri() async {
    try {
      return await _intentMethodChannel.invokeMethod<String>('takeInitialUri');
    } on MissingPluginException {
      // 실기기 확인 필요 항목 — 채널 미연결(테스트·구버전 엔진 등) 시 조용히
      // "대기 중인 URI 없음"으로 취급한다. 인텐트 수신 자체가 안 되는 상황을
      // 숨기지 않도록 호출부(향후 main.dart)가 로그를 남기는 편이 안전하다.
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<String> onNewIntentUri() {
    return _intentEventChannel.receiveBroadcastStream().map((event) => event as String);
  }

  @override
  Future<PdfResult<SafImportResult>> importToPath({
    required String contentUri,
    required String destinationPath,
  }) async {
    try {
      final raw = await _safChannel.invokeMapMethod<String, Object?>('copyContentUri', {
        'uri': contentUri,
        'destinationPath': destinationPath,
      });
      if (raw == null) {
        return const PdfErr(UnknownFailure('SAF 임포트: 네이티브 채널이 빈 결과를 반환했습니다'));
      }
      return PdfOk(
        SafImportResult(
          displayName: raw['displayName'] as String?,
          bytes: (raw['bytes'] as int?) ?? 0,
        ),
      );
    } on PlatformException catch (e) {
      return PdfErr(_mapPlatformFailure(e, contentUri));
    } on MissingPluginException {
      return const PdfErr(EngineUnsupported('saf_import_channel'));
    } catch (e) {
      return PdfErr(UnknownFailure('SAF 임포트 실패: $e'));
    }
  }

  PdfFailure _mapPlatformFailure(PlatformException e, String contentUri) {
    return switch (e.code) {
      'NOT_FOUND' => SourceMissing(e.message ?? contentUri),
      'PERMISSION_DENIED' => PermissionDenied(e.message ?? 'content URI 접근 거부: $contentUri'),
      _ => UnknownFailure(e.message ?? '${e.code}: $contentUri'),
    };
  }
}
