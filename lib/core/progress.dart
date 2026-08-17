/// isolate → 메인으로 전달되는 진행률. 반드시 직렬화 가능한 원시 필드만 가진다.
///
/// 무손실 보장과 무관 (진행률 표시 전용 값 타입).
class PdfProgress {
  const PdfProgress({required this.phase, required this.done, required this.total});

  final PdfPhase phase;
  final int done; // 처리 완료 페이지 수
  final int total; // 전체 페이지 수 (0이면 불확정)

  double get fraction => total == 0 ? 0 : done / total;

  Map<String, Object?> toMap() => {'phase': phase.index, 'done': done, 'total': total};

  static PdfProgress fromMap(Map<String, Object?> m) => PdfProgress(
    phase: PdfPhase.values[m['phase']! as int],
    done: m['done']! as int,
    total: m['total']! as int,
  );
}

enum PdfPhase { opening, composing, writing, verifying, finalizing }
