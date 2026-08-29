/// S3 페이지 편집 화면. (설계 §1, `screens.md` S3)
///
/// 3열 썸네일 그리드(`page_grid_editor.dart`) + 앱바(모드 전환·저장·페이지 추가 —
/// 배너 오터치 방지 배치 원칙, 배너 자체는 4주차). 상태는 `EditController`가
/// 단독 소유한다(§1.2) — 이 화면은 페이지 목록을 직접 들고 있지 않는다.
///
/// **크롭은 여기 없다**(설계 §2.2 판정 — 크롭은 사진→PDF 생성 흐름 전용).
/// **저장은 항상 새 문서**(§1.5) — 이 화면은 원본 파일을 직접 수정하는 코드를
/// 갖지 않는다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/banner_host.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/app_error.dart';
import '../../core/file_name.dart';
import '../../core/size_guard.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_engine.dart';
import '../common/failure_ui.dart';
import 'edit_controller.dart';
import 'edit_document_pager.dart';
import 'page_grid_editor.dart';
import 'save_dialog.dart';

class EditScreen extends ConsumerStatefulWidget {
  const EditScreen({super.key, required this.args});
  final EditArgs args;

  @override
  ConsumerState<EditScreen> createState() => _EditScreenState();
}

enum _LoadState { loading, ready, failed }

class _EditScreenState extends ConsumerState<EditScreen> {
  _LoadState _loadState = _LoadState.loading;
  EditController? _controller;
  int _baselineBytes = 0;
  bool _externalNoticeShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = widget.args.source;
    switch (source) {
      case EditSourceMyDocument(:final docId):
        final repo = ref.read(documentRepositoryProvider);
        if (repo == null) {
          _fail();
          return;
        }
        final result = await repo.load(docId);
        if (!mounted) return;
        switch (result) {
          case PdfOk<DocumentDetail>(:final value):
            setState(() {
              _controller = EditController(initial: value.pages)
                ..addListener((_) => setState(() {}), fireImmediately: false);
              if (widget.args.initialMode == EditMode.select) {
                _controller!.enterSelectModeOnly();
              }
              _baselineBytes = value.summary.fileSize;
              _loadState = _LoadState.ready;
            });
          case PdfErr<DocumentDetail>(:final failure):
            await FailureUi.showDialog(context, failure);
            _fail();
        }
      case EditSourceExternalPdf(:final pdfPath):
        final engine = ref.read(pdfEngineProvider);
        if (engine == null) {
          _fail();
          return;
        }
        final result = await engine.inspect(pdfPath);
        if (!mounted) return;
        switch (result) {
          case PdfOk<PdfDocInfo>(:final value):
            final pages = [
              for (var i = 0; i < value.pageCount; i++)
                PdfPageRef(sourcePath: pdfPath, sourceIndex: i, rotation: 0),
            ];
            setState(() {
              _controller = EditController(initial: pages)
                ..addListener((_) => setState(() {}), fireImmediately: false);
              if (widget.args.initialMode == EditMode.select) {
                _controller!.enterSelectModeOnly();
              }
              _baselineBytes = value.bytes;
              _loadState = _LoadState.ready;
            });
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _maybeShowExternalNotice(),
            );
          case PdfErr<PdfDocInfo>(:final failure):
            await FailureUi.showDialog(context, failure);
            _fail();
        }
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() => _loadState = _LoadState.failed);
    Navigator.of(context).pop();
  }

  Future<void> _maybeShowExternalNotice() async {
    if (_externalNoticeShown || !mounted) return;
    _externalNoticeShown = true;
    // 외부 PDF 최초 1회 안내(설계 §1.1, `screens.md` S3 확정 문구). 편집 세션
    // 1회 범위 — 앱 전역 플래그를 만들지 않는다.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('복사본으로 편집합니다. 원본은 변경되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDiscardIfDirty() async {
    final controller = _controller;
    if (controller == null || !controller.current.dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('저장하지 않고 나갈까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _addPages() async {
    final controller = _controller;
    if (controller == null) return;
    final selected = controller.current.selected;
    final selectedIndex = selected.length == 1
        ? controller.current.pages.indexWhere(
            (page) => selected.contains(page.id),
          )
        : -1;
    final choice = await showModalBottomSheet<_AddPageChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('카메라로 스캔'),
              onTap: () => Navigator.of(ctx).pop(_AddPageChoice.camera),
            ),
            ListTile(
              title: const Text('사진에서 선택'),
              onTap: () => Navigator.of(ctx).pop(_AddPageChoice.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final PdfResult<List<String>> result = switch (choice) {
      _AddPageChoice.camera => await ref.read(scanSourceProvider).scan(context),
      _AddPageChoice.gallery =>
        await ref.read(photoSourceProvider).pickImages(),
    };
    if (!mounted) return;
    switch (result) {
      case PdfOk<List<String>>(:final value):
        final insertion = await _chooseInsertionTarget(selectedIndex);
        if (!mounted || insertion == null) return;
        controller.insertImages(value, at: insertion);
      case PdfErr<List<String>>(:final failure):
        if (failure is! Cancelled) {
          await FailureUi.showDialog(context, failure);
        }
    }
  }

  Future<void> _changePageOrder() {
    final controller = _controller;
    if (controller == null) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('페이지 순서 변경'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('완료'),
              ),
            ],
          ),
          body: PageGridEditor(
            controller: controller,
            actions: const {EditAction.reorder},
          ),
        ),
      ),
    );
  }

  Future<int?> _chooseInsertionTarget(int selectedIndex) {
    final controller = _controller;
    if (controller == null) return Future.value(null);
    if (selectedIndex < 0) return Future.value(controller.current.pages.length);
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('선택 페이지 앞에 추가'),
              onTap: () => Navigator.of(ctx).pop(selectedIndex),
            ),
            ListTile(
              title: const Text('선택 페이지 뒤에 추가'),
              onTap: () => Navigator.of(ctx).pop(selectedIndex + 1),
            ),
            ListTile(
              title: const Text('마지막에 추가'),
              onTap: () =>
                  Navigator.of(ctx).pop(controller.current.pages.length),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final controller = _controller;
    if (controller == null) return;
    final op = controller.classify();
    final pages = controller.toPageRefs();

    int addedImageBytes = 0;
    if (op == SaveOp.compose) {
      for (final page in controller.current.pages) {
        if (page.origin == EditPageOrigin.added && page.ref is ImagePageRef) {
          try {
            addedImageBytes += await File(
              (page.ref as ImagePageRef).imagePath,
            ).length();
          } catch (_) {
            // 파일을 읽지 못해도 저장 자체는 계속 진행한다 — 게이트가 최종 방어선이다.
          }
        }
      }
    }

    final guardInput = assembleGuardInput(
      op: op,
      baselineBytes: _baselineBytes,
      addedImageBytes: addedImageBytes,
    );

    final spec = SaveRequestSpec(
      suggestedTitle: FileName.editedTitle(widget.args.title),
      origin: DocOrigin.imported,
      pages: pages,
      guardInput: guardInput,
      showQualityPicker: pages.any((p) => p is ImagePageRef),
    );

    final summary = await showSaveDialog(
      context: context,
      ref: ref,
      spec: spec,
    );
    if (summary == null || !mounted) return;
    _goToViewerAfterSave(summary);
  }

  Future<void> _split() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.current;
    if (state.selected.isEmpty) return;

    final selectedRefs = [
      for (final page in state.pages)
        if (state.selected.contains(page.id)) page.ref,
    ];

    final guardInput = assembleGuardInput(
      op: SaveOp.split,
      baselineBytes: _baselineBytes,
      totalPages: controller.original.length,
      selectedPages: selectedRefs.length,
    );

    final spec = SaveRequestSpec(
      suggestedTitle: FileName.splitTitle(widget.args.title),
      origin: DocOrigin.imported,
      pages: selectedRefs,
      guardInput: guardInput,
      showQualityPicker: selectedRefs.any((p) => p is ImagePageRef),
    );

    final summary = await showSaveDialog(
      context: context,
      ref: ref,
      spec: spec,
    );
    if (summary == null || !mounted) return;
    _goToViewerAfterSave(summary);
  }

  void _goToViewerAfterSave(DocumentSummary summary) {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) return;
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.viewer,
      arguments: ViewerArgs(
        pdfPath: workspace.docPdf(summary.id),
        title: summary.title,
        pageCount: summary.pageCount,
        docId: summary.id,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('새 파일로 저장됨 — "${summary.title}" (${summary.pageCount}쪽)'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_loadState != _LoadState.ready || controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final state = controller.current;
    final isSelect = state.mode == EditMode.select;

    return PopScope(
      canPop: !isSelect && !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (isSelect) {
          controller.clearSelection();
          return;
        }
        if (await _confirmDiscardIfDirty() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: isSelect
              ? TextButton(
                  onPressed: controller.clearSelection,
                  child: const Text('취소'),
                )
              : null,
          title: Text(
            isSelect ? '${state.selected.length}개 선택' : widget.args.title,
            overflow: TextOverflow.ellipsis,
          ),
          actions: isSelect
              ? [
                  TextButton(
                    onPressed: state.selected.isEmpty
                        ? null
                        : controller.rotateSelected,
                    child: const Text('회전'),
                  ),
                  TextButton(
                    onPressed: state.selected.isEmpty ? null : _deleteSelected,
                    child: const Text('삭제'),
                  ),
                  TextButton(
                    onPressed: state.selected.isEmpty ? null : _split,
                    child: const Text('선택 페이지로 새 문서'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: controller.enterSelectModeOnly,
                    child: const Text('선택'),
                  ),
                  TextButton(onPressed: _addPages, child: const Text('페이지 추가')),
                  TextButton(onPressed: _save, child: const Text('저장')),
                ],
        ),
        body: EditDocumentPager(
          controller: controller,
          onPageOrderRequested: _changePageOrder,
        ),
        bottomNavigationBar: const BannerHost(slot: BannerSlot.edit),
      ),
    );
  }

  void _deleteSelected() {
    final controller = _controller;
    if (controller == null) return;
    final removed = controller.deleteSelected();
    if (removed.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('페이지를 삭제했습니다'),
        action: SnackBarAction(
          label: '실행취소',
          onPressed: () => controller.undoDelete(removed),
        ),
      ),
    );
  }
}

enum _AddPageChoice { camera, gallery }
