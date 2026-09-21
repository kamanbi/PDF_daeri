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
import '../../pdf/pdf_compressor.dart' show TargetAttempt;
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

  // 목표 용량 모드(설계 §76 §3.6) 상태. 기존 프리셋 상태(_result)와 별개로 두되
  // 같은 시트·같은 _Stage를 그대로 오간다 — 새 스테이지를 만들지 않는다.
  bool _targetExpanded = false;
  final _customMbController = TextEditingController();
  String? _customMbError;
  TargetAttempt? _targetAttempt;
  CompressToTargetResult? _targetResult;

  @override
  void initState() {
    super.initState();
    _loadSourceBytes();
  }

  @override
  void dispose() {
    _customMbController.dispose();
    super.dispose();
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
      _targetResult = null;
      _targetAttempt = null;
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

  /// 목표 용량 모드(설계 §76 §3.6). 칩 탭이 곧 실행 지시다 — 확인 창을 거치지 않는다.
  Future<void> _startCompressToTarget(int targetBytes) async {
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
      _result = null;
      _targetAttempt = null;
    });

    final source = widget.docId != null
        ? CompressSource.myDocument(widget.docId!)
        : CompressSource.externalPdf(
            pdfPath: widget.pdfPath,
            title: widget.title,
          );

    final result = await repo.compressToTargetSize(
      source: source,
      targetBytes: targetBytes,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      // 매 시도마다 진행률 바가 0부터 다시 오르므로(§3.4), 이 줄이 없으면 사용자가
      // 멈춘 줄 오해한다(§3.6).
      onAttempt: (a) {
        if (!mounted) return;
        setState(() => _targetAttempt = a);
      },
      cancelToken: token,
    );

    if (!mounted) return;

    switch (result) {
      case PdfOk<CompressToTargetResult>(:final value):
        setState(() {
          _targetResult = value;
          _stage = _Stage.result;
        });
        // §3.5 확정: reachedTarget이 true일 때만 기존 압축 완료 흐름과 동일하게 즉시
        // 배경을 교체한다. false면 사용자가 "이 결과로 저장"을 눌러야 교체한다 —
        // 자동 저장하지 않는다.
        if (value.reachedTarget &&
            !value.base.keptOriginal &&
            value.base.summary != null) {
          widget.onDocumentReady(value.base.summary!);
        }
        // 광고: 기존 ad_gate 지점 그대로 재사용 — 시도 횟수와 무관하게 압축 1회당 1번.
        unawaited(ref.read(adGateProvider).registerCompletedTask());
      case PdfErr<CompressToTargetResult>(:final failure):
        setState(() => _stage = _Stage.pickPreset);
        if (failure is! Cancelled) {
          await FailureUi.showDialog(context, failure);
        }
    }
  }

  void _startCompressToCustomTarget() {
    final raw = _customMbController.text.trim();
    final mb = int.tryParse(raw);
    if (mb == null || mb <= 0) {
      setState(() => _customMbError = '1 이상의 숫자를 입력하세요.');
      return;
    }
    setState(() => _customMbError = null);
    _startCompressToTarget(mb * 1024 * 1024);
  }

  /// §3.5 "이 결과로 저장" — 목표 미달 시 기본 동작이 아니라 사용자가 눌러야 하는
  /// 선택지다. 여기서 처음이자 유일하게 배경 문서를 교체한다.
  void _acceptTargetResult() {
    final base = _targetResult!.base;
    if (!base.keptOriginal && base.summary != null) {
      widget.onDocumentReady(base.summary!);
    }
    Navigator.of(context).pop();
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

  /// 프리셋 흐름(`_result`)과 목표 용량 흐름(`_targetResult`, reachedTarget: true)이
  /// 공유한다 — 둘 다 성공 결과 화면에서만 쓰이므로 상호 배타적이다.
  DocumentSummary? get _currentSummary =>
      _result?.summary ?? _targetResult?.base.summary;

  Future<void> _share() async {
    // [W4-T1] `shareExportProvider` 배선(설계 §2.6). 이 버튼은 `!keptOriginal`일
    // 때만 표시되므로(`_buildResult`) `_currentSummary`는 항상 non-null이다
    // (`document_repository.dart` 계약: keptOriginal false면 summary도 non-null).
    // 공유 대상은 압축 전 원본이 아니라 새로 만들어진 압축 문서다.
    final summary = _currentSummary!;
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
        const Divider(height: 24),
        // §76 §3.6: 새 스테이지·새 다이얼로그를 만들지 않고 같은 시트 안에서 펼친다.
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('목표 용량 맞추기'),
          subtitle: const Text('원하는 파일 크기를 정해서 압축합니다.'),
          trailing: Icon(_targetExpanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _targetExpanded = !_targetExpanded),
        ),
        if (_targetExpanded) _buildTargetPicker(context),
      ],
    );
  }

  Widget _buildTargetPicker(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 칩 탭이 곧 실행 지시다 — 확인 버튼을 두지 않는다(UX 원칙, §3.6).
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('1MB'),
                onPressed: () => _startCompressToTarget(1 * 1024 * 1024),
              ),
              ActionChip(
                label: const Text('5MB'),
                onPressed: () => _startCompressToTarget(5 * 1024 * 1024),
              ),
              ActionChip(
                label: const Text('10MB'),
                onPressed: () => _startCompressToTarget(10 * 1024 * 1024),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // "직접 입력"은 숫자를 받아야 하므로 입력 필드 + 실행 버튼은 예외로 허용한다
          // (§3.6). 확인 창이 아니라 실행 그 자체다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _customMbController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '직접 입력 (MB)',
                    isDense: true,
                    errorText: _customMbError,
                  ),
                  onSubmitted: (_) => _startCompressToCustomTarget(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startCompressToCustomTarget,
                child: const Text('실행'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final fraction = _progress?.fraction ?? 0;
    final attempt = _targetAttempt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('압축 중…', style: Theme.of(context).textTheme.titleLarge),
        if (attempt != null) ...[
          const SizedBox(height: 4),
          // §3.6: 진행률 바가 매 시도 0부터 다시 오르므로 이 줄이 없으면 사용자가
          // 멈춘 줄 오해한다.
          Text(
            '${attempt.attempt}/${attempt.maxAttempts}번째 시도 중',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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

  /// 프리셋 흐름(`_result`)과 목표 용량 흐름(reachedTarget: true, `_targetResult`)이
  /// 공유하는 디스패처다. 둘은 상호 배타적으로만 채워진다(§3.6).
  Widget _buildResult(BuildContext context) {
    final targetResult = _targetResult;
    if (targetResult != null) {
      return _buildTargetResult(context, targetResult);
    }
    final result = _result!;
    if (result.keptOriginal) {
      return _buildKeptOriginalBody(context);
    }
    return _buildSuccessBody(
      context,
      originalBytes: result.originalBytes,
      resultBytes: result.resultBytes,
    );
  }

  Widget _buildTargetResult(BuildContext context, CompressToTargetResult target) {
    final base = target.base;
    if (base.keptOriginal) {
      // §3.5: 모든 시도가 원본보다 큰 경우(사다리를 내려갈 필요가 없었던 경우)는
      // 기존 "이미 최적화된 문서" 문구를 그대로 재사용한다 — 새 문구를 만들지 않는다.
      return _buildKeptOriginalBody(context);
    }
    if (target.reachedTarget) {
      // §3.5: 목표에 도달했으면 기존 압축 완료 문구를 그대로 재사용한다.
      return _buildSuccessBody(
        context,
        originalBytes: base.originalBytes,
        resultBytes: base.resultBytes,
      );
    }

    // §3.5 미달 흐름 — "이 결과로 저장"이 기본 동작이 아니라 사용자가 눌러야 하는
    // 선택지다. 자동 저장하지 않는다.
    final targetMb = _formatMb(target.targetBytes);
    final fromMb = _formatMb(base.originalBytes);
    final toMb = _formatMb(base.resultBytes);
    final pct =
        (1 - base.resultBytes / base.originalBytes).clamp(0, 1) * 100;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '목표 $targetMb에 맞추지 못했습니다',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text('최선 결과: $fromMb → $toMb (${pct.round()}% 감소)'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _acceptTargetResult,
                child: const Text('이 결과로 저장'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // §4.3 확정: 감소율·[원본 삭제]/[공유] 전부 숨기고 안내만 표시한다. 새 문서를
  // 만들지 않았으므로 지울 원본도, 공유할 결과도 없다.
  Widget _buildKeptOriginalBody(BuildContext context) {
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

  Widget _buildSuccessBody(
    BuildContext context, {
    required int originalBytes,
    required int resultBytes,
  }) {
    final fromMb = _formatMb(originalBytes);
    final toMb = _formatMb(resultBytes);
    final pct = (1 - resultBytes / originalBytes).clamp(0, 1) * 100;

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
