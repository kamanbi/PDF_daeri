/// 사진 파일 선택의 순수 데이터 계층 진입점.
///
/// 카메라 미리보기·문서 모서리 보정처럼 Flutter UI가 필요한 스캔 기능은
/// `features/scan/local_document_scan_source.dart`에 둔다. 이 파일은 PDF 저장
/// 경로가 UI·래스터링 계층을 직접 의존하지 않도록 유지한다.
library;

import 'package:file_picker/file_picker.dart';

import '../core/app_error.dart';

abstract interface class PhotoSource {
  Future<PdfResult<List<String>>> pickImages();
}

class FilePickerPhotoSource implements PhotoSource {
  @override
  Future<PdfResult<List<String>>> pickImages() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) {
        return const PdfErr(Cancelled());
      }
      final paths = files
          .map((file) => file.path)
          .whereType<String>()
          .toList(growable: false);
      if (paths.isEmpty) {
        return const PdfErr(UnknownFailure('선택한 사진의 로컬 경로를 확인할 수 없습니다'));
      }
      return PdfOk(paths);
    } catch (error) {
      return PdfErr(UnknownFailure('사진 선택 실패: $error'));
    }
  }
}
