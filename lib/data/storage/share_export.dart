/// 시스템 공유의 **유일한** 진입점 인터페이스. (설계 §5.2, T5 — 인터페이스만)
///
/// [2026-08-20 · 3주차 T5] 이번 라운드는 인터페이스 정의까지만이다. 구현체는
/// **T6**에서 `share_plus` 패키지 승인(Q-W2) 이후 별도 라운드로 만든다
/// (`pubspec.yaml`에 `share_plus`를 이번 라운드에 추가하지 않는다).
///
/// 공유 시 파일명 부여도 여기서만 한다(01 §1.2 소유표 · 중복 금지 원칙). 앱 내부
/// 저장 경로는 `docs/<uuid>/document.pdf`이므로 그대로 공유하면 받는 쪽에
/// **"document.pdf"로 도착한다** — 3주차 판정 기준("한글 제목 문서를 카카오톡·
/// Gmail·드라이브로 공유 시 파일명 정상")이 정확히 이 지점이다. 구현체는 반드시
/// `FileName.toFileName(title)` 이름의 사본을 `Workspace.shareFile(...)`
/// (`cache/share/`)에 만들어 그것을 공유해야 한다 — 내부 UUID 경로를 직접
/// 공유하지 않는다.
library;

import '../../core/app_error.dart';

abstract interface class ShareExport {
  /// [pdfPath]의 파일을 사용자 제목 기반 이름으로 노출해 시스템 공유 시트를 띄운다.
  ///
  /// [pdfPath]는 앱 작업공간 안의 실제 PDF 경로(`docs/<docId>/document.pdf` 또는
  /// `recent/<id>.pdf`)이고, [title]은 표시용 제목(한글 원문, 아직 정규화 전이어도
  /// 된다 — 정규화·확장자 부착은 구현체가 `FileName.toFileName`으로 한다).
  Future<PdfResult<void>> sharePdf({required String pdfPath, required String title});
}
