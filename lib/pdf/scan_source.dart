/// ML Kit 문서 스캐너 래퍼(인터페이스로 감쌈) + Play 서비스 실패 시 정식
/// 대체 경로(PhotoSource). (설계 §2.7, §11 W6, 절대 규칙 5)
///
/// `google_mlkit_document_scanner`는 베타·Android 전용·Play 서비스 필수다.
/// 이 파일은 그 플로우를 **호출하고 결과만 받는다** — 자체 카메라·크롭·필터 UI를
/// 만들지 않는다. Play 서비스가 없거나 실패해도 앱을 죽이지 않고, "사진 → PDF"로
/// 유도할 수 있도록 [PhotoSource]를 **정식 경로**(예외 처리 흉내가 아니다)로
/// 같이 제공한다.
///
/// [ScanSource.scan]이 반환하는 경로는 ML Kit이 준 임시 파일 경로다. 호출자
/// (`DocumentRepository.createDocument`)가 이미 이 경로들을 즉시
/// `sources/pages/NNN.jpg`로 복사하므로(`_copySourcesToStaging`, §3.3 화이트리스트),
/// 이 파일은 임시 경로를 워크스페이스 경로로 바꾸는 책임을 지지 않는다.
library;

import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../core/app_error.dart';

abstract interface class ScanSource {
  /// Play 서비스·ML Kit 사용 가능 여부. 화면 진입 전에 확인한다.
  ///
  /// 이 패키지에는 별도의 가용성 조회 API가 없다 — Android 여부까지만 미리
  /// 걸러내고, Play 서비스 자체의 실제 가용성은 [scan] 호출 시점에 판가름난다
  /// (아래 [scan] 문서 참조). **실기기 확인 필요**: 에뮬레이터·Play 서비스 미탑재
  /// 기기에서 [scan]이 실제로 어떤 예외/코드를 던지는지는 빌드 없이 확인할 수
  /// 없었다 — 지금은 모든 예외를 [EngineUnsupported]로 뭉뚱그려 폴백을 유도한다.
  Future<bool> isAvailable();

  /// ML Kit 문서 스캐너 플로우를 호출하고 결과 이미지 경로만 받는다.
  /// 자체 카메라·크롭·필터 UI를 만들지 않는다(절대 규칙 5).
  ///
  /// 사용자가 스캔 없이 취소하면(빈 결과) [Cancelled]를 반환한다. Play 서비스
  /// 부재·설치 실패 등 스캐너 자체를 못 여는 경우 [EngineUnsupported]를
  /// 반환한다 — 호출자는 이 실패를 [PhotoSource]로의 정식 유도 신호로 쓴다.
  Future<PdfResult<List<String>>> scan({int pageLimit = 30});
}

/// Play 서비스 실패 시 사용하는 정식 경로(예외 처리가 아니다).
abstract interface class PhotoSource {
  Future<PdfResult<List<String>>> pickImages();
}

class MlKitScanSource implements ScanSource {
  @override
  Future<bool> isAvailable() async => Platform.isAndroid;

  @override
  Future<PdfResult<List<String>>> scan({int pageLimit = 30}) async {
    if (!await isAvailable()) {
      return const PdfErr(EngineUnsupported('mlkit_document_scanner'));
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        pageLimit: pageLimit,
        mode: ScannerMode.full,
        isGalleryImport: false,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      if (images.isEmpty) {
        // 사용자가 스캔 없이 뒤로 나감 — 부분 산출물 없음, 정상 취소.
        return const PdfErr(Cancelled());
      }
      return PdfOk(images);
    } catch (e) {
      // Play 서비스 미설치·업데이트 필요·기타 스캐너 초기화 실패 등을 전부
      // 여기서 흡수한다. 앱을 죽이지 않고 호출자가 PhotoSource로 유도하게
      // EngineUnsupported로 통일해 반환한다(우회 구현을 만들지 않는다).
      return const PdfErr(EngineUnsupported('mlkit_document_scanner'));
    } finally {
      try {
        await scanner.close();
      } catch (_) {
        // 닫기 실패는 무시한다 — 이미 실패 결과를 반환하는 경로다.
      }
    }
  }
}

class FilePickerPhotoSource implements PhotoSource {
  @override
  Future<PdfResult<List<String>>> pickImages() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
      );
      if (files.isEmpty) {
        return const PdfErr(Cancelled());
      }
      final paths = files.map((f) => f.path).whereType<String>().toList(growable: false);
      if (paths.isEmpty) {
        return const PdfErr(UnknownFailure('선택한 사진의 로컬 경로를 확인할 수 없습니다'));
      }
      return PdfOk(paths);
    } catch (e) {
      return PdfErr(UnknownFailure('사진 선택 실패: $e'));
    }
  }
}
