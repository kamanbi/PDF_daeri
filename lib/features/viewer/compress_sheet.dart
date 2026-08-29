/// S4 뷰어 압축 시트 — 하나의 `showModalBottomSheet`가 3상태(강도 선택 · 진행 ·
/// 결과)를 오간다. (`_workspace/31_architect_external_compress_l2.md` §4.3, M-E8)
///
/// **목표 흐름**(설계 §4.1, `screens.md` UX 원칙 확정): `[압축] 1탭 → 강도 선택
/// 1탭 → 완료(감소율 숫자) → [원본 삭제]/[공유](강제 아님)`. **확인 창을 만들지
/// 않는다** — 강도를 고르는 탭이 곧 실행 지시다.
///
/// **UI는 `PdfCompressor`를 직접 부르지 않는다**(설계 §4.5 확정) —
/// `DocumentRepository.compressToNewDocument`를 통해서만 호출한다. 시트는
/// 스테이징 경로·파일 커밋 규약을 알지 못한다.
///
/// **Q20 확정(설계 §8.4, 재논의 불필요)**: 결과 시트의 삭제 버튼 라벨은 압축 대상
/// 출처에 따라 문맥 분기한다 — 내 문서(`docId` non-null) → **"원본 삭제"**, 외부에서
/// 연 PDF(`recentId` non-null) → **"앱에서 원본 제거"**. 버튼은 숨기지 않는다. 이
/// 라벨 분기의 단일 소유는 이 파일이다 — Repository나 다른 곳에 두 번째 판단
/// 지점을 만들지 않는다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_gate.dart';
import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/progress.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/image_quality.dart';
import '../common/failure_ui.dart';
import '../common/share_flow.dart';

/// 압축 시트를 띄운다. [docId]는 "내 문서"(홈 섹션 2)를 열었을 때만, [recentId]는
/// 외부에서 연 PDF(최근 연 파일 포함)를 열었을 때만 채워진다 — 둘은 상호 배타다
/// (`lib/app/router.dart`의 `ViewerArgs` 계약).
///
/// [onDocumentReady]는 압축이 성공하고 `keptOriginal == false`일 때, **결과 화면이
/// 뜨는 즉시** 호출된다(설계 §4.3 "결과 시트가 뜨는 순간 배경의 뷰어를 압축 결과
/// 파일로 교체한다") — 사용자가 시트를 닫을 때까지 기다리지 않는다. 호출부
/// (`viewer_screen.dart`)는 이 콜백에서 뷰어가 보여주는 문서를 새 압축 문서로
/// 교체한다.
void showCompressSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String pdfPath,
  required String title,
  required String? docId,
  required String? recentId,
  required void Function(DocumentSummary newDocument) onDocumentReady,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _CompressSheet(
      pdfPath: pdfPath,
      title: title,
      docId: docId,
      recentId: recentId,
      onDocumentReady: onDocumentReady,
    ),
  );
}

enum _Stage { pickPreset, progress, result }

class _CompressSheet extends ConsumerStatefulWidget {
  const _CompressSheet({
    required this.pdfPath,
    required this.title,
    required this.docId,
    required this.recentId,
    required this.onDocumentReady,
  });

  final String pdfPath;
  final String title;
  final String? docId;
  final String? recentId;
  final void Function(DocumentSummary newDocument) onDocumentReady;

  @override
  ConsumerState<_CompressSheet> createState() => _CompressSheetState();
}

class _CompressSheetState extends ConsumerState<_CompressSheet> {
  _Stage _stage = _Stage.pickPreset;
  PdfProgress? _progress;
  CancelToken? _cancelToken;
  CompressToNewDocumentResult? _result;
  bool _removed = false; // 원본 삭제/제거 버튼 중복 클릭 방지
  int? _sourceBytes;

  @override
  void initState() {
    super.initState();
    _loadSourceBytes();
  }

  Future<void> _loadSourceBytes() async {
    try {
      final bytes = await File(widget.pdfPath).length();
      if (mounted) setState(() => _sourceBytes = bytes);
    } catch (_) {
      // 예상 용량을 표시하지 못해도 압축 자체는 계속 가능하다.
    }
  }

  Future<void> _startCompress(ImageQuality preset) async {
    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) {
      await FailureUi.showDialog(
        context,
        const UnknownFailure('저장소를 사용할 수 없습니다.'),
      );
      return;
    }

    final token = CancelToken();
    _cancelToken = token;
    setState(() {
      _stage = _Stage.progress;
      _progress = const PdfProgress(phase: PdfPhase.opening, done: 0, total: 0);
    });

    // §4.5 파일 소유표: "내 문서인가 외부 PDF인가"는 이 호출부가 CompressSource로
    // 명시한다 -- Repository가 recent_files 등 출처를 추측하지 않는다.
    final source = widget.docId != null
        ? CompressSource.myDocument(widget.docId!)
        : CompressSource.externalPdf(
            pdfPath: widget.pdfPath,
            title: widget.title,
          );

    final result = await repo.compressToNewDocument(
      source: source,
      preset: preset,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      cancelToken: token,
    );

    if (!mounted) return;

    switch (result) {
      case PdfOk<CompressToNewDocumentResult>(:final value):
        setState(() {
          _result = value;
          _stage = _Stage.result;
        });
        if (!value.keptOriginal && value.summary != null) {
          // §4.3 확정: 결과 화면이 뜨는 즉시 배경 교체 — 시트를 닫을 때까지 기다리지 않는다.
          widget.onDocumentReady(value.summary!);
        }
        unawaited(ref.read(adGateProvider).registerCompletedTask());
      case PdfErr<CompressToNewDocumentResult>(:final failure):
        setState(() => _stage = _Stage.pickPreset);
        if (failure is! Cancelled) {
          await FailureUi.showDialog(context, failure);
        }
    }
  }

  void _cancel() => _cancelToken?.cancel();

  Future<void> _removeOriginal() async {
    if (widget.docId != null) {
      // 내 문서 — 진짜로 원본 문서를 지운다(DocumentRepository.delete, §4.4 표).
      final repo = ref.read(documentRepositoryProvider);
      await repo?.delete(widget.docId!);
    } else if (widget.recentId != null) {
      // 외부 PDF — 앱 작업공간 복사본 + 최근 목록 항목만 제거한다. 진짜 원본 파일은
      // 앱이 권한을 갖고 있지 않으므로 지울 수 없다(절대 규칙 6, §4.4 표).
      final recentRepo = ref.read(recentRepositoryProvider);
      await recentRepo?.removeFromList(widget.recentId!);
    }
    if (!mounted) return;
    setState(() => _removed = true);
  }

  Future<void> _share() async {
    // [W4-T1] `shareExportProvider` 배선(설계 §2.6). 이 버튼은 `!keptOriginal`일
    // 때만 표시되므로(`_buildResult`) `_result.summary`는 항상 non-null이다
    // (`document_repository.dart` 계약: keptOriginal false면 summary도 non-null).
    // 공유 대상은 압축 전 원본이 아니라 새로 만들어진 압축 문서다.
    final summary = _result!.summary!;
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      await FailureUi.showDialog(
        context,
        const UnknownFailure('공유 기능을 사용할 수 없습니다.'),
      );
      return;
    }
    await shareDocument(
      context: context,
      ref: ref,
      pdfPath: workspace.docPdf(summary.id),
      title: summary.title,
    );
  }

  String get _deleteLabel => widget.docId != null ? '원본 삭제' : '앱에서 원본 제거';

  @override
  Widget build(BuildContext context) {
    // 진행 중에는 스와이프·뒤로가기로 닫히지 않는다(설계 §4.3 상태2 확정). 강도
    // 선택·결과 상태는 평소대로 닫을 수 있다(시트 진입 시 isDismissible/enableDrag는
    // 항상 true — PopScope로 진행 상태에서만 pop을 막는다).
    return PopScope(
      canPop: _stage != _Stage.progress,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: switch (_stage) {
              _Stage.pickPreset => _buildPickPreset(context),
              _Stage.progress => _buildProgress(context),
              _Stage.result => _buildResult(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPickPreset(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('압축', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _CompressionQualityTile(
          profile: ImageQualityProfile.high,
          sourceBytes: _sourceBytes,
          onTap: () => _startCompress(ImageQuality.high),
        ),
        _CompressionQualityTile(
          profile: ImageQualityProfile.standard,
          sourceBytes: _sourceBytes,
          onTap: () => _startCompress(ImageQuality.standard),
        ),
        _CompressionQualityTile(
          profile: ImageQualityProfile.min,
          sourceBytes: _sourceBytes,
          onTap: () => _startCompress(ImageQuality.min),
        ),
        const SizedBox(height: 8),
        const Text('예상치는 사진 중심 PDF 기준입니다. 텍스트 중심 PDF는 원본 유지 또는 소폭 변화할 수 있습니다.'),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final fraction = _progress?.fraction ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('압축 중…', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        // 패스 A/B/C/D를 사용자에게 나누어 보이지 않는다 -- 0~100 하나로만 표시(§4.3).
        LinearProgressIndicator(value: fraction == 0 ? null : fraction),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(fraction * 100).round()}%'),
            // 취소는 즉시 듣는다 -- CancelToken이 패스 A/B/C 루프를 이미지 단위로 끊는다.
            TextButton(onPressed: _cancel, child: const Text('취소')),
          ],
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;
    if (result.keptOriginal) {
      // §4.3 확정: 감소율·[원본 삭제]/[공유] 전부 숨기고 안내만 표시한다. 새 문서를
      // 만들지 않았으므로 지울 원본도, 공유할 결과도 없다.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이미 최적화된 문서입니다', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('새 파일을 만들지 않았습니다.'),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ),
        ],
      );
    }

    final fromMb = _formatMb(result.originalBytes);
    final toMb = _formatMb(result.resultBytes);
    final pct =
        (1 - result.resultBytes / result.originalBytes).clamp(0, 1) * 100;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 형식은 `pipeline.md` 압축 절 그대로: "4.2MB → 1.1MB (74% 감소)".
        // 강조 대상은 감소율(%) — headlineSmall(테마 정의)로 표시한다.
        Text(
          '${pct.round()}% 감소',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text('$fromMb → $toMb', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        // 두 버튼 모두 선택지다 -- 아무것도 누르지 않고 닫아도 압축된 새 문서는
        // 이미 저장돼 있다(swap은 결과 화면 진입 시점에 이미 일어났다).
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: _share, child: const Text('공유')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _removed ? null : _removeOriginal,
                child: Text(_removed ? '제거됨' : _deleteLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatMb(int bytes) => ImageQualityProfile.formatBytes(bytes);
}

class _CompressionQualityTile extends StatelessWidget {
  const _CompressionQualityTile({
    required this.profile,
    required this.sourceBytes,
    required this.onTap,
  });

  final ImageQualityProfile profile;
  final int? sourceBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(profile.label),
      subtitle: Text(
        '${profile.recommendedFor}\n${profile.processingDescription}\n${profile.estimateFor(sourceBytes ?? 0)}',
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
