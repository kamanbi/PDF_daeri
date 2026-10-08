/// 스캔 추천 표시용 공용 위젯. 배지(추천)와 제안 줄. 선택값을 바꾸지 않고 표시만 한다.
library;

import 'package:flutter/material.dart';

import '../../app/app_locale.dart';
import '../../pdf/scan_quality_advisor.dart';

/// 추천 표시. 빨간 알약 + 아이콘 + 글자로 한눈에 띄게 한다(흰 글자 대비 충분).
/// 다크 모드에서도 같은 색을 쓴다.
class AdviceBadge extends StatelessWidget {
  const AdviceBadge({super.key});

  static const Color _background = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.thumb_up_alt, size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              appText(context, '추천'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 세그먼트 라벨: 1행 라벨, 2행 '추천' 배지. 추천이 아닌 세그먼트도 2행 공간을 유지해
/// 분석이 끝나도 버튼 높이가 변하지 않는다. 글자 크기는 모든 세그먼트가 같다.
class AdviceSegmentLabel extends StatelessWidget {
  const AdviceSegmentLabel({
    super.key,
    required this.label,
    required this.recommended,
  });

  final String label;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(height: 2),
        Visibility(
          visible: recommended,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: const AdviceBadge(),
        ),
      ],
    );
  }
}

/// 리스트 항목 제목 옆 '추천' 배지(추천일 때만).
class AdviceInlineBadge extends StatelessWidget {
  const AdviceInlineBadge({super.key});

  @override
  Widget build(BuildContext context) => const AdviceBadge();
}

/// 제안 줄에 표시할 문구들(번역 완료). 문제가 있으면 첫 문제를 맨 앞에 두고, 이어서 추천 이유.
/// 여러 장이면 문제 페이지 번호를 문구 앞에 붙인다.
List<String> scanAdviceLines(
  BuildContext context,
  ScanAdvice advice, {
  bool includeFormat = false,
}) {
  final lines = <String>[];
  if (advice.issues.isNotEmpty) {
    final issue = advice.issues.first;
    final message = appText(context, scanIssueMessage(issue));
    final pages = advice.issuePages[issue] ?? const <int>[];
    if (advice.pageCount > 1 && pages.isNotEmpty) {
      lines.add(
        appText(context, '사진 {pages}: {message}')
            .replaceAll('{pages}', pages.map((i) => '${i + 1}').join(', '))
            .replaceAll('{message}', message),
      );
    } else {
      lines.add(message);
    }
  }
  lines.add(appText(context, advice.qualityReason));
  if (includeFormat) lines.add(appText(context, advice.formatReason));
  return lines;
}

/// 제안 줄. 분석 중에는 같은 자리에 진행 문구를 둔다. 결과가 없으면(`advice == null`이고
/// 분석이 끝났으면) 접는다. 저장 버튼 등 다른 동작을 막지 않는다.
class ScanAdviceHint extends StatelessWidget {
  const ScanAdviceHint({
    super.key,
    required this.loading,
    required this.advice,
    this.includeFormat = false,
    this.onRetake,
  });

  final bool loading;
  final ScanAdvice? advice;
  final bool includeFormat;

  /// 문제가 있을 때만 '다시 찍기' 버튼을 노출한다(카메라 스캔 흐름 전용).
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adv = advice;
    if (loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(appText(context, '사진을 살펴보는 중…'))),
            ],
          ),
        ),
      );
    }
    if (adv == null) return const SizedBox.shrink();
    final lines = scanAdviceLines(context, adv, includeFormat: includeFormat);
    final color = adv.needsRetake
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.lightbulb_outline, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Text(
                    lines[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: i == 0 && adv.needsRetake ? color : null,
                    ),
                  ),
              ],
            ),
          ),
          if (adv.needsRetake && onRetake != null)
            TextButton(
              onPressed: onRetake,
              child: Text(appText(context, '다시 찍기')),
            ),
        ],
      ),
    );
  }
}
