/// 편집 화면의 큰 페이지 미리보기와 하단 가로 페이지 바.
library;

import '../../app/app_locale.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import 'edit_controller.dart';

const int _editorPageWidthPx = 1800;
const int _editorThumbWidthPx = 180;
const double _editorThumbBarHeight = 88;

class EditDocumentPager extends ConsumerStatefulWidget {
  const EditDocumentPager({
    super.key,
    required this.controller,
    required this.onPageOrderRequested,
  });

  final EditController controller;
  final VoidCallback onPageOrderRequested;

  @override
  ConsumerState<EditDocumentPager> createState() => _EditDocumentPagerState();
}

class _EditDocumentPagerState extends ConsumerState<EditDocumentPager> {
  final PageController _pageController = PageController();
  var _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(EditState state, EditPage page, int index) {
    if (state.mode == EditMode.select) {
      widget.controller.toggleSelect(page.id);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EditState>(
      stream: widget.controller.stream,
      initialData: widget.controller.current,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.controller.current;
        final pages = state.pages;
        if (pages.isEmpty) {
          return Center(child: Text(appText(context, '페이지가 없습니다.')));
        }
        final currentIndex = _currentIndex.clamp(0, pages.length - 1);
        if (currentIndex != _currentIndex) _currentIndex = currentIndex;
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) => _EditorPagePreview(
                  key: ValueKey(pages[index].id),
                  page: pages[index],
                  selected: state.selected.contains(pages[index].id),
                  selectMode: state.mode == EditMode.select,
                  onTap: () => _selectPage(state, pages[index], index),
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: _editorThumbBarHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: pages.length,
                itemBuilder: (context, index) => _EditorThumbnail(
                  page: pages[index],
                  index: index,
                  current: index == currentIndex,
                  selected: state.selected.contains(pages[index].id),
                  selectMode: state.mode == EditMode.select,
                  onTap: () => _selectPage(state, pages[index], index),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onPageOrderRequested,
                child: Text(appText(context, '페이지 순서 변경')),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EditorPagePreview extends ConsumerStatefulWidget {
  const _EditorPagePreview({
    super.key,
    required this.page,
    required this.selected,
    required this.selectMode,
    required this.onTap,
  });

  final EditPage page;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;

  @override
  ConsumerState<_EditorPagePreview> createState() => _EditorPagePreviewState();
}

class _EditorPagePreviewState extends ConsumerState<_EditorPagePreview> {
  Uint8List? _bytes;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EditorPagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.ref != widget.page.ref) _load();
  }

  Future<void> _load() async {
    setState(() {
      _bytes = null;
      _failed = false;
    });
    final result = await ref
        .read(pdfRendererProvider)
        .renderPageThumbnail(
          page: widget.page.ref,
          targetWidthPx: _editorPageWidthPx,
        );
    if (!mounted) return;
    switch (result) {
      case PdfOk<Uint8List>(:final value):
        setState(() => _bytes = value);
      case PdfErr<Uint8List>():
        setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _bytes != null
        ? LayoutBuilder(
            builder: (context, constraints) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.memory(
                _bytes!,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          )
        : Center(
            child: _failed
                ? Text(appText(context, '페이지를 표시할 수 없습니다.'))
                : const CircularProgressIndicator(),
          );
    return GestureDetector(
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: widget.selectMode && widget.selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                )
              : null,
        ),
        child: content,
      ),
    );
  }
}

class _EditorThumbnail extends ConsumerStatefulWidget {
  const _EditorThumbnail({
    required this.page,
    required this.index,
    required this.current,
    required this.selected,
    required this.selectMode,
    required this.onTap,
  });

  final EditPage page;
  final int index;
  final bool current;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;

  @override
  ConsumerState<_EditorThumbnail> createState() => _EditorThumbnailState();
}

class _EditorThumbnailState extends ConsumerState<_EditorThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EditorThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.ref != widget.page.ref) _load();
  }

  Future<void> _load() async {
    final result = await ref
        .read(pdfRendererProvider)
        .renderPageThumbnail(
          page: widget.page.ref,
          targetWidthPx: _editorThumbWidthPx,
        );
    if (!mounted || result is! PdfOk<Uint8List>) return;
    setState(() => _bytes = result.value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 68,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.selected || widget.current
                    ? accent
                    : Colors.transparent,
                width: widget.selected ? 3 : 2,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _bytes == null
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Image.memory(
                        _bytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                Positioned(
                  left: 2,
                  bottom: 2,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.black54),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        '${widget.index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
