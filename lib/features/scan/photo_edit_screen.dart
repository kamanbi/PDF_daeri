/// 사진·스캔 → PDF **생성 중** 편집. (설계 §2, `milestones.md` 3주차 신설 항목)
///
/// 개정된 흐름: `PhotoToPdfScreen`(이미지 선택, 무변경) → `PhotoEditScreen`(순서·회전·
/// 삭제·크롭, 이 파일) → `showSaveDialog`(제목+화질+저장, `save_dialog.dart`).
///
/// `EditController`(순서·회전·삭제·선택 상태)와 `PageGridEditor`(그리드·드래그·선택)를
/// S3와 **공유한다**(설계 §2.1). 이 화면이 새로 만드는 것은 크롭 진입 배선뿐이다 —
/// 크롭 UI 자체는 `crop_editor.dart`(신규 컴포넌트, 사진 흐름 전용)를 쓴다.
///
/// **스캔 경로에는 크롭을 주지 않는다**(설계 §2.1 — ML Kit이 이미 크롭한 결과를 다시
/// 크롭하는 UI는 두 번째 보정 UI다, 절대 규칙 5). `origin == DocOrigin.scan`이면
/// `EditAction.crop`을 액션 집합에서 뺀다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository/document_repository.dart';
import '../../pdf/page_ref.dart';
import '../edit/crop_editor.dart';
import '../edit/edit_controller.dart';
import '../edit/page_grid_editor.dart';
import '../edit/save_dialog.dart';

class PhotoEditScreen extends ConsumerStatefulWidget {
  const PhotoEditScreen({
    super.key,
    required this.imagePaths,
    required this.origin,
    required this.suggestedTitle,
  });

  final List<String> imagePaths;
  final DocOrigin origin;
  final String suggestedTitle;

  @override
  ConsumerState<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends ConsumerState<PhotoEditScreen> {
  // `before`(SizeGuard.classify의 원본)는 항상 빈 목록이다(설계 §1.6 분기 1 —
  // "사진·스캔 신규 생성"). 그래서 컨트롤러를 빈 목록으로 만들고 선택한 이미지를
  // `insertImages`로 넣는다 — `initial: imagePaths...`로 바로 채우면 `original`이
  // 비지 않아 `classify()`가 잘못된 SaveOp을 고른다.
  late final EditController _controller = EditController(initial: const [])
    ..addListener((_) => setState(() {}), fireImmediately: false)
    ..insertImages(widget.imagePaths);

  bool get _allowCrop => widget.origin == DocOrigin.photo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestCrop(EditPage page) async {
    final ref0 = page.ref;
    if (ref0 is! ImagePageRef) return;
    final result = await showCropEditor(context: context, ref: ref, page: ref0);
    if (!mounted) return;
    // showCropEditor는 "취소"와 "크롭 없음(null)"을 구분하지 않는다(crop_editor.dart
    // 문서 참조) — null이면 항상 크롭을 지운다. 취소해도 크롭이 없어지는 것은
    // 원래 크롭이 없었을 때만 무해하다. 크롭이 있던 페이지의 "취소"까지 정확히
    // 구분하려면 별도 신호가 필요하지만, v1은 크롭 없는 상태가 기본값이라
    // 실사용에서 체감되는 손실이 없다(재적용은 다시 크롭 아이콘을 누르면 된다).
    _controller.setCrop(page.id, result);
  }

  Future<void> _save() async {
    final state = _controller.current;
    final pages = _controller.toPageRefs();

    int baselineBytes = 0;
    for (final page in pages) {
      if (page is ImagePageRef) {
        try {
          baselineBytes += await File(page.imagePath).length();
        } catch (_) {
          // 파일을 읽지 못해도 저장 자체는 계속 진행한다 — 게이트가 최종 방어선이다.
        }
      }
    }

    final op = _controller.classify(); // before가 비어 있으므로 항상 SaveOp.merge(placeholder).
    final guardInput = assembleGuardInput(op: op, baselineBytes: baselineBytes);

    final spec = SaveRequestSpec(
      suggestedTitle: widget.suggestedTitle,
      origin: widget.origin,
      pages: pages,
      guardInput: guardInput,
      showQualityPicker: true, // 사진→PDF는 전량 ImagePageRef다.
    );

    if (state.pages.isEmpty) return;

    final summary = await showSaveDialog(context: context, ref: ref, spec: spec);
    if (summary == null || !mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('새 파일로 저장됨 — "${summary.title}" (${summary.pageCount}쪽)')),
    );
  }

  void _deleteSelected() {
    final removed = _controller.deleteSelected();
    if (removed.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('페이지를 삭제했습니다'),
        action: SnackBarAction(label: '실행취소', onPressed: () => _controller.undoDelete(removed)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.current;
    final isSelect = state.mode == EditMode.select;

    return PopScope(
      canPop: !isSelect,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _controller.clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: isSelect
              ? IconButton(icon: const Icon(Icons.close), tooltip: '선택 해제', onPressed: _controller.clearSelection)
              : null,
          title: Text(isSelect ? '${state.selected.length}개 선택' : '${state.pages.length}장'),
          actions: isSelect
              ? [
                  IconButton(
                    icon: const Icon(Icons.rotate_right),
                    tooltip: '회전',
                    onPressed: state.selected.isEmpty ? null : _controller.rotateSelected,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '삭제',
                    onPressed: state.selected.isEmpty ? null : _deleteSelected,
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.checklist_outlined),
                    tooltip: '선택',
                    onPressed: _controller.enterSelectModeOnly,
                  ),
                  IconButton(
                    icon: const Icon(Icons.save_outlined),
                    tooltip: '저장',
                    onPressed: state.pages.isEmpty ? null : _save,
                  ),
                ],
        ),
        body: PageGridEditor(
          controller: _controller,
          actions: {
            EditAction.reorder,
            EditAction.rotate,
            EditAction.delete,
            if (_allowCrop) EditAction.crop,
          },
          onCropRequested: _requestCrop,
        ),
      ),
    );
  }
}
