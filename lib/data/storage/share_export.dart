/// 시스템 공유의 **유일한** 진입점 인터페이스 + `share_plus` 구현체. (설계 §5.2)
///
/// [2026-08-20 · 3주차 T5] 인터페이스만 신설.
/// [2026-08-25 · 3주차 T6 · Q-W2 승인] `share_plus: ^13.3.0`으로 구현체
/// [SharePlusExport]를 추가했다. `pubspec.yaml`에 이미 추가됨(`flutter pub add
/// share_plus`, 추측 버전 없음).
///
/// 공유 시 파일명 부여도 여기서만 한다(01 §1.2 소유표 · 중복 금지 원칙). 앱 내부
/// 저장 경로는 `docs/<uuid>/document.pdf`이므로 그대로 공유하면 받는 쪽에
/// **"document.pdf"로 도착한다** — 3주차 판정 기준("한글 제목 문서를 카카오톡·
/// Gmail·드라이브로 공유 시 파일명 정상")이 정확히 이 지점이다. 구현체는 반드시
/// `FileName.toFileName(title)` 이름의 사본을 `Workspace.shareFile(...)`
/// (`cache/share/`)에 만들어 그것을 공유해야 한다 — 내부 UUID 경로를 직접
/// 공유하지 않는다.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/app_error.dart';
import '../../core/file_name.dart';
import 'workspace.dart';

abstract interface class ShareExport {
  /// [pdfPath]의 파일을 사용자 제목 기반 이름으로 노출해 시스템 공유 시트를 띄운다.
  ///
  /// [pdfPath]는 앱 작업공간 안의 실제 PDF 경로(`docs/<docId>/document.pdf` 또는
  /// `recent/<id>.pdf`)이고, [title]은 표시용 제목(한글 원문, 아직 정규화 전이어도
  /// 된다 — 정규화·확장자 부착은 구현체가 `FileName.toFileName`으로 한다).
  Future<PdfResult<void>> sharePdf({required String pdfPath, required String title});
}

/// [ShareExport]의 `share_plus` 구현체. (T6, 담당 P)
///
/// 절차: ① `FileName.toFileName(title)`로 한글 제목이 살아있는 파일명을 만든다
/// ② `pdfPath`를 `Workspace.shareFile(fileName)`(`cache/share/<fileName>`)로
/// 복사한다 ③ `SharePlus.instance.share(ShareParams(files: [XFile(...)]))`로
/// 시스템 공유 시트를 띄운다 ④ 공유 시트가 닫히면(완료·취소 무관)
/// `Workspace.clearShareStaging()`으로 정리한다 — "항상 지워도 안전"
/// 원칙이므로 결과와 무관하게 항상 호출한다.
class SharePlusExport implements ShareExport {
  /// [share] 주입 지점은 테스트 전용이다(§ 파일 상단 참조) — 실기기 코드 경로는
  /// 기본값(`SharePlus.instance.share`) 그대로다.
  SharePlusExport(this._workspace, {Future<ShareResult> Function(ShareParams)? share})
    : _share = share ?? SharePlus.instance.share;

  final Workspace _workspace;
  final Future<ShareResult> Function(ShareParams) _share;

  @override
  Future<PdfResult<void>> sharePdf({required String pdfPath, required String title}) async {
    final source = File(pdfPath);
    if (!await source.exists()) {
      return PdfErr(SourceMissing(pdfPath));
    }

    // 동일 파일명이 이전 공유에서 남아 있을 수 있으니(정리 실패 재시도 여지) 매번
    // 새로 정리하고 시작한다 — `cache/`는 언제 지워도 안전하다는 계약을 그대로 쓴다.
    await _workspace.clearShareStaging();

    final fileName = FileName.toFileName(title);
    final stagedPath = _workspace.shareFile(fileName);
    try {
      await Directory(p.dirname(stagedPath)).create(recursive: true);
      await source.copy(stagedPath);
    } catch (e) {
      return PdfErr(UnknownFailure('공유용 사본을 만들지 못했습니다: $e'));
    }

    try {
      await _share(ShareParams(files: [XFile(stagedPath)]));
      return const PdfOk(null);
    } catch (e) {
      return PdfErr(UnknownFailure('공유하지 못했습니다: $e'));
    } finally {
      // 완료·취소·실패 어떤 경로든 스테이징 사본은 남겨두지 않는다.
      await _workspace.clearShareStaging();
    }
  }
}
