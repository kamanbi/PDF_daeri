/// 용량 검증 게이트. `CLAUDE.md` 절대 규칙 3 · `pipeline.md` 게이트 표를 코드로 강제한다.
///
/// 이 파일이 비율 상수의 **유일한** 소유자다. 다른 파일에 리터럴 숫자로 흩뿌리지 않는다.
///
/// 무손실 보장: 이 파일은 PDF를 열거나 쓰지 않는다. 순수 산술 검증만 수행하며
/// 래스터화·재인코딩과 무관하다.
library;

import '../pdf/page_ref.dart';

enum SaveOp {
  deletePages, // 결과 <= 원본
  reorderOrRotate, // 결과 <= 원본 * 1.05
  split, // 결과 <= 원본 * (선택/전체) * 1.2
  merge, // 결과 <= 원본 합계 * 1.05
  compose, // 결과 <= (원본 + 추가 이미지 바이트) * 1.15 — §7 Q-W5 승인 완료(3주차)
}

/// [SizeGuard.classify]의 편집 의도. 화면이 판단하지 않고 이 값 하나로 `split` 분기를
/// 명시적으로 알려준다(설계 §1.6 — "선택 페이지로 새 문서"는 페이지 목록만 봐서는
/// `deletePages`와 구별할 수 없다).
enum EditIntent { edit, split }

/// 검증에 필요한 사실만 담는다. 파일 핸들·엔진 참조를 넣지 않는다.
class GuardInput {
  const GuardInput({
    required this.op,
    required this.baselineBytes,
    this.totalPages,
    this.selectedPages,
    this.addedImageBytes = 0,
  });

  final SaveOp op;

  /// 삭제·순서변경·회전·나누기: 원본 1개의 바이트.
  /// 합치기: 원본들의 **합계** 바이트.
  final int baselineBytes;

  final int? totalPages; // split 전용
  final int? selectedPages; // split 전용
  final int addedImageBytes; // compose 전용 (§14 Q6)
}

sealed class GuardResult {
  const GuardResult();
}

final class GuardPass extends GuardResult {
  const GuardPass({required this.resultBytes, required this.limitBytes});
  final int resultBytes;
  final int limitBytes;
}

final class GuardBlocked extends GuardResult {
  const GuardBlocked({required this.resultBytes, required this.limitBytes, required this.op});
  final int resultBytes;
  final int limitBytes;
  final SaveOp op;
}

abstract final class SizeGuard {
  // 비율 상수는 여기에만 존재한다. 호출부에 숫자를 쓰지 않는다.
  static const double deleteRatio = 1.00;
  static const double reorderRotateRatio = 1.05;
  static const double splitRatio = 1.20;
  static const double mergeRatio = 1.05;

  /// `compose`(혼합/페이지 추가) 결과 한계 = `(baselineBytes + addedImageBytes) * composeOverheadRatio`.
  /// 사용자 승인 완료(3주차 §7 Q-W5): `result ≤ (원본 + 추가 이미지 바이트) × 1.15`.
  /// 실측(M-W1)으로 근거가 쌓이면 이 상수만 조정한다 — 호출부에 매직넘버를 흩뿌리지 않는다.
  static const double composeOverheadRatio = 1.15;

  /// [composeOverheadRatio]의 구 이름. 기존 호출부 호환을 위해 남긴다.
  static const double composeRatio = composeOverheadRatio;

  /// split 결과 하한(바이트). 1페이지만 발췌해도 PDF 구조 오버헤드가 있으므로
  /// 계산된 한계가 이보다 작으면 이 값을 하한으로 쓴다.
  /// [실측 필요 · M2b] — 잠정값. 측정 후 아키텍트 경유로 조정한다.
  static const int splitMinLimitBytes = 4096;

  static int limitFor(GuardInput input) {
    switch (input.op) {
      case SaveOp.deletePages:
        return (input.baselineBytes * deleteRatio).floor();
      case SaveOp.reorderOrRotate:
        return (input.baselineBytes * reorderRotateRatio).floor();
      case SaveOp.split:
        final total = input.totalPages;
        final selected = input.selectedPages;
        if (total == null || selected == null || total <= 0 || selected <= 0 || selected > total) {
          throw ArgumentError('split requires totalPages >= selectedPages >= 1');
        }
        final computed = (input.baselineBytes * (selected / total) * splitRatio).floor();
        return computed < splitMinLimitBytes ? splitMinLimitBytes : computed;
      case SaveOp.merge:
        return (input.baselineBytes * mergeRatio).floor();
      case SaveOp.compose:
        return ((input.baselineBytes + input.addedImageBytes) * composeRatio).floor();
    }
  }

  static GuardResult check({required GuardInput input, required int resultBytes}) {
    final limit = limitFor(input);
    if (resultBytes <= limit) {
      return GuardPass(resultBytes: resultBytes, limitBytes: limit);
    }
    return GuardBlocked(resultBytes: resultBytes, limitBytes: limit, op: input.op);
  }

  /// 편집 전/후 페이지 목록으로 적용할 `SaveOp`를 결정한다. 순수 함수 — 파일을 읽지 않는다.
  /// 판정 순서가 곧 우선순위이며, **애매하면 항상 더 엄격한 쪽**을 고른다(설계 §1.6).
  ///
  /// 1. [before]가 비어 있다            → 사진·스캔 신규 생성.
  ///    **`SaveOp.freshDocument`는 아직 도입하지 않는다**(§7 Q-W6 미결 — 상수 R·K 미확정).
  ///    설계 §3.4가 정한 임시 규약대로 `SaveOp.merge`를 대신 반환한다(baselineBytes를
  ///    호출부가 선택 이미지 바이트 합계로 채우면 안전 측 오류로 동작한다).
  /// 2. [intent] == `EditIntent.split`  → `SaveOp.split`
  /// 3. [after]에 [before]에 없던 `ImagePageRef`가 있다 → `SaveOp.compose`
  /// 4. [after]의 페이지 동일성 다중집합이 [before]의 **진부분집합** → `SaveOp.deletePages`
  ///    (삭제가 하나라도 있으면 순서·회전이 함께 바뀌었어도 `deletePages`다)
  /// 5. 그 외(삭제·추가 없음, 순서/회전만 변경) → `SaveOp.reorderOrRotate`
  ///
  /// **페이지 동일성**의 정의: `PdfPageRef`는 `(sourcePath, sourceIndex)`,
  /// `ImagePageRef`는 `(imagePath, crop)`. **`rotation`은 동일성에서 제외한다** —
  /// 회전은 페이지의 정체성이 아니라 변경 가능한 속성이다.
  static SaveOp classify({required List<PageRef> before, required List<PageRef> after, required EditIntent intent}) {
    if (before.isEmpty) return SaveOp.merge; // TODO(Q-W6): freshDocument 도입 시 교체.

    if (intent == EditIntent.split) return SaveOp.split;

    final beforeKeys = before.map(_identityKey).toSet();
    final hasNewImage = after.any((p) => p is ImagePageRef && !beforeKeys.contains(_identityKey(p)));
    if (hasNewImage) return SaveOp.compose;

    final afterKeyList = after.map(_identityKey).toList(growable: false);
    final beforeKeyList = before.map(_identityKey).toList(growable: false);
    if (_isProperMultisetSubset(afterKeyList, beforeKeyList)) return SaveOp.deletePages;

    return SaveOp.reorderOrRotate;
  }

  /// [classify]가 쓰는 페이지 동일성 키. `rotation`을 의도적으로 제외한다.
  static String _identityKey(PageRef p) => switch (p) {
    PdfPageRef(:final sourcePath, :final sourceIndex) => 'pdf|$sourcePath|$sourceIndex',
    ImagePageRef(:final imagePath, :final crop) => 'img|$imagePath|${crop?.encode() ?? ''}',
  };

  /// [after]가 [before]의 진부분집합(다중집합, 개수 포함)인가. 개수가 같거나 더 많으면
  /// 무조건 false다("삭제가 하나라도 있어야" `deletePages`이므로).
  static bool _isProperMultisetSubset(List<String> after, List<String> before) {
    if (after.length >= before.length) return false;
    final remaining = <String, int>{};
    for (final key in before) {
      remaining[key] = (remaining[key] ?? 0) + 1;
    }
    for (final key in after) {
      final count = remaining[key] ?? 0;
      if (count <= 0) return false;
      remaining[key] = count - 1;
    }
    return true;
  }
}
