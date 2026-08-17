/// 용량 검증 게이트. `CLAUDE.md` 절대 규칙 3 · `pipeline.md` 게이트 표를 코드로 강제한다.
///
/// 이 파일이 비율 상수의 **유일한** 소유자다. 다른 파일에 리터럴 숫자로 흩뿌리지 않는다.
///
/// 무손실 보장: 이 파일은 PDF를 열거나 쓰지 않는다. 순수 산술 검증만 수행하며
/// 래스터화·재인코딩과 무관하다.
library;

enum SaveOp {
  deletePages, // 결과 <= 원본
  reorderOrRotate, // 결과 <= 원본 * 1.05
  split, // 결과 <= 원본 * (선택/전체) * 1.2
  merge, // 결과 <= 원본 합계 * 1.05
  compose, // 혼합/페이지 추가 — §14 Q6 승인 전까지 호출부에서 사용 금지
}

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
  static const double composeRatio = 1.15; // Q6 승인 전 사용 금지

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
}
