/// `PdfFailure` → 사용자 문구·복구 행동의 유일한 매핑. (설계 §5.1, 2주차 T6)
///
/// **보안**: `UnknownFailure`의 원본 예외 메시지는 이 파일 밖(UI 문자열)으로 절대
/// 나가지 않는다 — 경로·qpdf 내부 문자열·비밀번호가 섞여 있을 수 있다. 원본은
/// `developer.log`(디버그 전용)로만 남기고, 화면에는 일반화된 안내만 보인다.
///
/// **pdfrx 경로 오분류 판단(24번 문서 인계 사항)**: `PdfxRenderer`(뷰어의
/// `pageGeometry` 등)는 손상된 PDF를 구조 파싱 단계에서 완전히 읽지 못하면
/// `SourceCorrupted`가 아니라 `SourceEncrypted`로 분류하는 사례가 실측됐다.
/// 이 파일의 매핑 자체는 설계 §5.1 표를 그대로 따른다(`SourceEncrypted`→비밀번호
/// 입력 분기, `SourceCorrupted`→열 수 없는 파일). 이미 올바른 비밀번호로 열람 중인
/// 뷰어에서 다시 `SourceEncrypted`가 나오는 경우(= 오분류 신호)는 그 문맥을 아는
/// 호출부(`lib/features/viewer/viewer_screen.dart`)가 "열 수 없는 파일" 계열로
/// 안전하게 합쳐 보여준다 — 여기서는 일반적인 실패 매핑만 제공하고, 문맥 판단을
/// 이 파일에 넣지 않는다(단일 소유 매핑에 문맥 분기를 섞지 않기 위함).
library;

import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../core/app_error.dart';

/// 실패에서 사용자가 할 수 있는 행동. §5.1.
enum FailureAction { retry, removeFromList, goHome, dismiss, freeUpSpace }

abstract final class FailureUi {
  /// 짧은 제목. 다이얼로그 타이틀.
  static String title(PdfFailure f) => switch (f) {
    SourceEncrypted() => '암호로 보호된 문서',
    SourceCorrupted() => '열 수 없는 파일',
    SourceMissing() => '파일을 찾을 수 없음',
    PermissionDenied() => '파일에 접근할 수 없음',
    OutOfSpace() => '저장 공간 부족',
    Cancelled() => '',
    SizeGuardViolation() => '저장 중단',
    EngineUnsupported() => '지원하지 않는 파일',
    UnknownFailure() => '처리하지 못했습니다',
  };

  /// 설명 문구. 기술 용어·경로·비밀번호를 절대 노출하지 않는다.
  static String message(PdfFailure f) {
    switch (f) {
      case SourceEncrypted():
        return '비밀번호를 입력하세요';
      case SourceCorrupted():
        return '파일이 손상되어 열 수 없습니다';
      case SourceMissing():
        return '파일이 더 이상 없습니다';
      case PermissionDenied():
        return '보낸 앱에서 다시 열어 주세요';
      case OutOfSpace(:final requiredBytes):
        final mb = (requiredBytes / (1024 * 1024)).ceil();
        return '약 ${mb}MB가 더 필요합니다';
      case Cancelled():
        return '';
      case SizeGuardViolation():
        // op별 상세 문구는 3주차 저장 경로(SizeGuard 발동 지점) 소유. 여기서는
        // 이 실패 타입이 뷰어·열기 흐름에서도 안전하게 표시될 수 있는 일반형만 둔다.
        return '용량 제한으로 작업을 완료하지 못했습니다';
      case EngineUnsupported():
        return '이 파일은 처리할 수 없습니다';
      case UnknownFailure(:final message):
        // 원본 메시지는 UI로 절대 내보내지 않는다 — 디버그 전용 로그로만 남긴다.
        developer.log('UnknownFailure: $message', name: 'FailureUi', level: 900);
        return '다시 시도해 주세요';
    }
  }

  /// 이 실패에서 사용자가 할 수 있는 행동.
  static List<FailureAction> actions(PdfFailure f) => switch (f) {
    SourceEncrypted() => const [],
    SourceCorrupted() => const [FailureAction.removeFromList, FailureAction.goHome],
    SourceMissing() => const [FailureAction.removeFromList, FailureAction.goHome],
    PermissionDenied() => const [FailureAction.goHome],
    OutOfSpace() => const [FailureAction.freeUpSpace, FailureAction.dismiss],
    Cancelled() => const [],
    SizeGuardViolation() => const [FailureAction.dismiss],
    EngineUnsupported() => const [FailureAction.goHome],
    UnknownFailure() => const [FailureAction.retry, FailureAction.goHome],
  };

  static String _actionLabel(FailureAction a) => switch (a) {
    FailureAction.retry => '다시 시도',
    FailureAction.removeFromList => '목록에서 제거',
    FailureAction.goHome => '홈으로',
    FailureAction.dismiss => '확인',
    FailureAction.freeUpSpace => '정리하기',
  };

  /// 표준 에러 다이얼로그. 모든 화면이 이것을 쓴다.
  ///
  /// `Cancelled`는 §5.1대로 다이얼로그를 띄우지 않고 즉시 `null`을 반환한다 —
  /// 사용자가 스스로 취소한 것을 다시 알리지 않는다.
  static Future<FailureAction?> showDialog(BuildContext context, PdfFailure f) async {
    if (f is Cancelled) return null;

    final acts = actions(f);
    final msg = message(f);
    return _showMaterialDialog<FailureAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title(f)),
        content: Text(msg),
        actions: acts.isEmpty
            ? [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('확인'))]
            : [
                for (final a in acts)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(a),
                    child: Text(_actionLabel(a)),
                  ),
              ],
      ),
    );
  }
}

/// `showDialog`(material.dart)와 이 파일의 정적 메서드 이름이 같아 클래스 내부에서
/// 자기 자신을 가리키게 되는 것을 피하기 위한 얇은 별칭. 동작은
/// `package:flutter/material.dart`의 `showDialog`와 동일하다.
Future<T?> _showMaterialDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(context: context, builder: builder);
}
