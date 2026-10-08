import 'dart:io';

/// 서명·주석·OCR 배치 화면이 공통으로 쓰는 "취소 버튼을 보여줄지" 판정.
/// 큰 문서(대략 15초 이상 걸릴 가능성)에서만 취소 버튼을 노출한다.
/// 파일이 작업 도중(정리·취소 등) 사라질 수 있어 실패 시 보수적으로 true를 반환한다.
bool shouldShowCancelButton({required int pageCount, required String pdfPath}) {
  if (pageCount >= 50) return true;
  try {
    return File(pdfPath).lengthSync() >= 20 * 1024 * 1024;
  } on FileSystemException {
    return true;
  }
}
