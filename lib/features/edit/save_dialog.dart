/// 저장 다이얼로그 — S3와 사진→PDF 생성 편집이 **공유하는** 유일한 저장 UI. (설계 §1.7, §5.1)
///
/// `compress_sheet.dart`의 3상태 단일 시트 패턴을 그대로 따른다(입력 → 진행 → 종료).
/// **확인 창을 추가하지 않는다.**
///
/// ```
/// [저장] 1탭 → 저장 다이얼로그(제목 + 화질) → [저장] 1탭 → 진행률 + 취소
///   → 성공: 다이얼로그를 닫고 새 문서의 DocumentSummary를 반환(호출자가 S4로 이동 +
///     "새 파일로 저장됨" 스낵바를 띄운다)
///   → 실패: 다이얼로그 안에서 상태 1로 되돌아가며 FailureUi를 보여준다
/// ```
///
/// `GuardInput` 조립 — 유일한 조립 지점(설계 §1.6 표). op별로 어느 값을 baselineBytes로
/// 쓰는지는 [assembleGuardInput] 하나가 정의한다. 화면은 `SizeGuard.classify`가 고른
/// `SaveOp`와 원본 바이트 크기만 재고, 조립 자체는 항상 이 함수를 거친다.
library;

import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/progress.dart';
import '../../core/size_guard.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/image_quality.dart';
import '../../pdf/page_ref.dart';
import '../common/failure_ui.dart';

/// 저장 다이얼로그가 `createDocument`를 부르기 위해 필요한 것 전부. 화면이
/// `SaveOp`·`baselineBytes`를 즉흥적으로 만들지 않도록 한 곳에 모은다(설계 §5.1).
class SaveRequestSpec {
  const SaveRequestSpec({
    required this.suggestedTitle,
    required this.origin,
    required this.pages,
    required this.guardInput,
    required this.showQualityPicker,
  });

  final String suggestedTitle;
  final DocOrigin origin;
  final List<PageRef> pages;
  final GuardInput guardInput;

  /// `pages`에 `ImagePageRef`가 하나라도 있을 때만 true. PDF 페이지만이면 화질
  /// 선택을 띄우지 않는다 — quality가 `PdfPageRef`에 영향을 주지 않으므로 무의미한
  /// 선택지를 보여주지 않는다(UX 원칙).
  final bool showQualityPicker;
}

/// `GuardInput` 조립의 단일 지점(설계 §1.6 표). 호출부는 `SaveOp`와 원본 바이트만
/// 재고, 필드 조합은 여기서만 결정한다.
GuardInput assembleGuardInput({
  required SaveOp op,
  required int baselineBytes,
  int? totalPages,
  int? selectedPages,
  int addedImageBytes = 0,
}) {
  return GuardInput(
    op: op,
    baselineBytes: baselineBytes,
    totalPages: totalPages,
    selectedPages: selectedPages,
    addedImageBytes: addedImageBytes,
  );
}

/// 저장 다이얼로그를 띄운다. 성공하면 새 문서의 `DocumentSummary`를, 취소·실패면
/// `null`을 반환한다(실패 안내는 이 함수 안에서 `FailureUi`로 이미 보여준 뒤다).
Future<DocumentSummary?> showSaveDialog({
  required BuildContext context,
  required WidgetRef ref,
  required SaveRequestSpec spec,
}) {
  return showModalBottomSheet<DocumentSummary?>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _SaveDialog(spec: spec),
  );
}

enum _Stage { input, progress }

class _SaveDialog extends ConsumerStatefulWidget {
  const _SaveDialog({required this.spec});
  final SaveRequestSpec spec;

  @override
  ConsumerState<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends ConsumerState<_SaveDialog> {
  late final TextEditingController _titleController = TextEditingController(text: widget.spec.suggestedTitle);
  final FocusNode _titleFocusNode = FocusNode();

  _Stage _stage = _Stage.input;
  ImageQuality _quality = ImageQuality.standard;
  PdfProgress? _progress;
  CancelToken? _cancelToken;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    // 제목 필드는 전체 선택 상태로 포커스(설계 §5.1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNode.requestFocus();
      _titleController.selection = TextSelection(baseOffset: 0, extentOffset: _titleController.text.length);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  bool get _showCancelButton {
    final pages = widget.spec.pages.length;
    final baseline = widget.spec.guardInput.baselineBytes;
    return pages >= 50 || baseline >= 20 * 1024 * 1024;
  }

  Future<void> _save() async {
    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) {
      await FailureUi.showDialog(context, const UnknownFailure('저장소를 사용할 수 없습니다.'));
      return;
    }

    final title = _titleController.text.trim().isEmpty ? widget.spec.suggestedTitle : _titleController.text.trim();

    final token = CancelToken();
    setState(() {
      _stage = _Stage.progress;
      _progress = null;
      _cancelToken = token;
      _cancelling = false;
    });

    final result = await repo.createDocument(
      title: title,
      origin: widget.spec.origin,
      pages: widget.spec.pages,
      quality: widget.spec.showQualityPicker ? _quality : ImageQuality.standard,
      guardInput: widget.spec.guardInput,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      cancelToken: token,
    );

    if (!mounted) return;

    switch (result) {
      case PdfOk<DocumentSummary>(:final value):
        Navigator.of(context).pop(value);
      case PdfErr<DocumentSummary>(:final failure):
        developer.log('저장 실패', name: 'SaveDialog', error: failure);
        setState(() => _stage = _Stage.input);
        if (failure is! Cancelled) {
          await FailureUi.showDialog(context, failure);
        }
    }
  }

  void _cancel() {
    setState(() => _cancelling = true);
    _cancelToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    // 진행 중에는 스와이프·뒤로가기로 닫히지 않는다(압축 시트와 동일 규약).
    return PopScope(
      canPop: _stage != _Stage.progress,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: switch (_stage) {
              _Stage.input => _buildInput(context),
              _Stage.progress => _buildProgress(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('저장', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
        ),
        if (widget.spec.showQualityPicker) ...[
          const SizedBox(height: 16),
          // compress_sheet.dart와 같은 문구·배치(설계 §5.1). 여기서는 탭이 곧 실행은
          // 아니다 — 선택만 갱신하고 [저장] 버튼이 실행한다.
          _QualityTile(
            title: '고화질',
            subtitle: '도면·작은 글씨',
            selected: _quality == ImageQuality.high,
            onTap: () => setState(() => _quality = ImageQuality.high),
          ),
          _QualityTile(
            title: '기본',
            subtitle: '권장',
            selected: _quality == ImageQuality.standard,
            onTap: () => setState(() => _quality = ImageQuality.standard),
          ),
          _QualityTile(
            title: '최소',
            subtitle: '메일 첨부',
            selected: _quality == ImageQuality.min,
            onTap: () => setState(() => _quality = ImageQuality.min),
          ),
        ],
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _save, child: const Text('저장')),
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final fraction = _progress?.fraction ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('저장 중…', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: fraction == 0 ? null : fraction),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(fraction * 100).round()}%'),
            if (_showCancelButton)
              TextButton(
                onPressed: _cancelling ? null : _cancel,
                child: Text(_cancelling ? '취소 중…' : '취소'),
              ),
          ],
        ),
      ],
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
      onTap: onTap,
    );
  }
}
