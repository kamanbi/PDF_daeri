/// S3와 사진→PDF 생성 편집이 **공유하는** 3열 썸네일 그리드. (설계 §1.4)
///
/// 이 위젯은 화면(Scaffold·앱바·저장 흐름)을 갖지 않는다 — 그리드와 드래그·선택
/// 제스처만 담당한다. 상태 소유는 전부 [EditController]에 있다(`edit_controller.dart`).
///
/// 드래그 재정렬은 신규 패키지를 쓰지 않는다(사용자 확정 Q-W1) — `LongPressDraggable`
/// + `DragTarget` 자체 구현.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_renderer.dart';
import 'edit_controller.dart';

/// 3열 · 3x DPI 기준 셀 폭 ≈ 120dp (설계 §1.4 확정). 상수는 이 파일 1곳에만 둔다.
const int gridThumbWidthPx = 240;

/// 이 그리드가 노출할 액션 집합. S3와 사진 흐름의 유일한 차이다(설계 §2.1).
enum EditAction { reorder, rotate, delete, crop, addPage, splitToNewDocument }

class PageGridEditor extends ConsumerStatefulWidget {
  const PageGridEditor({
    super.key,
    required this.controller,
    required this.actions,
    this.onCropRequested,
  });

  final EditController controller;
  final Set<EditAction> actions;

  /// [actions]에 [EditAction.crop]이 있을 때, 페이지의 크롭 아이콘을 탭하면 호출된다.
  /// 크롭 UI(`crop_editor.dart`)를 여는 것은 화면(사진 흐름 전용)의 책임이다 — 그리드는
  /// 자체 크롭 UI를 갖지 않는다(절대 규칙 1).
  final void Function(EditPage page)? onCropRequested;

  @override
  ConsumerState<PageGridEditor> createState() => _PageGridEditorState();
}

class _PageGridEditorState extends ConsumerState<PageGridEditor> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  int? _dragOverId;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeAutoScroll(Offset globalPosition, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    // §3.4-9 아키텍처 검사(저장 경로 프리셋 리터럴 전용 파일 검사)의 숫자 세트(2480/1754/
    // 1240/85/75/60)와 우연히 겹치는 것을 피하려고 64를 쓴다 — 이 값은 저장 프리셋과 무관한
    // 순수 UI 상수(드래그 중 자동 스크롤 시작 여백)다.
    const edge = 64.0;
    final height = box.size.height;
    _autoScrollTimer?.cancel();
    if (local.dy < edge) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final target = (_scrollController.offset - 12).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      });
    } else if (local.dy > height - edge) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final target = (_scrollController.offset + 12).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      });
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EditState>(
      stream: widget.controller.stream,
      initialData: widget.controller.current,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.controller.current;
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.72,
          ),
          itemCount: state.pages.length,
          itemBuilder: (context, index) {
            final page = state.pages[index];
            return _buildCell(context, state, page, index);
          },
        );
      },
    );
  }

  Widget _buildCell(BuildContext context, EditState state, EditPage page, int index) {
    final selected = state.selected.contains(page.id);
    final canDrag = widget.actions.contains(EditAction.reorder) && state.mode == EditMode.arrange;

    Widget cell = _PageCell(
      page: page,
      index: index,
      selected: selected,
      selectMode: state.mode == EditMode.select,
      showCrop: widget.actions.contains(EditAction.crop) && state.mode == EditMode.arrange,
      onCropTap: () => widget.onCropRequested?.call(page),
      onTap: () {
        if (state.mode == EditMode.select) {
          widget.controller.toggleSelect(page.id);
        }
        // arrange 모드의 탭은 아무 일도 하지 않는다(설계 §1.4 — v1에 페이지 확대
        // 보기를 만들지 않는다).
      },
    );

    if (state.mode == EditMode.select) {
      // 선택 모드에서는 드래그가 아니라 탭 선택만 동작한다(설계 §1.4 — 롱프레스가
      // 드래그와 선택 진입을 겸하지 않도록 선택 모드 진입은 앱바 버튼 1개뿐이다).
      return cell;
    }

    if (!canDrag) return cell;

    final highlighted = _dragOverId == page.id;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != page.id,
      onAcceptWithDetails: (details) {
        final oldIndex = state.pages.indexWhere((p) => p.id == details.data);
        if (oldIndex == -1) return;
        var newIndex = index;
        if (oldIndex < newIndex) newIndex += 1;
        widget.controller.reorder(oldIndex, newIndex);
        setState(() => _dragOverId = null);
        _stopAutoScroll();
      },
      onMove: (details) => setState(() => _dragOverId = page.id),
      onLeave: (_) => setState(() => _dragOverId = null),
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<int>(
          data: page.id,
          feedback: Material(
            elevation: 4,
            child: SizedBox(width: 100, height: 130, child: cell),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: cell),
          onDragUpdate: (details) => _maybeAutoScroll(details.globalPosition, context),
          onDragEnd: (_) => _stopAutoScroll(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: highlighted
                ? BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2))
                : null,
            child: cell,
          ),
        );
      },
    );
  }
}

/// 그리드 셀 1개: 썸네일 + 좌상단 페이지 번호 + 우상단 종류 배지 + (선택 모드)
/// 체크 오버레이. 썸네일은 지연 로딩(뷰포트 진입 시에만 요청, `_ThumbnailLoader`가
/// 동시 3개 상한 + 동일 키 합치기를 담당한다).
class _PageCell extends ConsumerStatefulWidget {
  const _PageCell({
    required this.page,
    required this.index,
    required this.selected,
    required this.selectMode,
    required this.showCrop,
    required this.onCropTap,
    required this.onTap,
  });

  final EditPage page;
  final int index;
  final bool selected;
  final bool selectMode;
  final bool showCrop;
  final VoidCallback onCropTap;
  final VoidCallback onTap;

  @override
  ConsumerState<_PageCell> createState() => _PageCellState();
}

class _PageCellState extends ConsumerState<_PageCell> {
  Uint8List? _bytes;
  bool _failed = false;
  Object? _requestedKey;

  @override
  void initState() {
    super.initState();
    _requestThumbnail();
  }

  @override
  void didUpdateWidget(covariant _PageCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_cacheKey(oldWidget.page.ref) != _cacheKey(widget.page.ref)) {
      _bytes = null;
      _failed = false;
      _requestThumbnail();
    }
  }

  static String _cacheKey(PageRef ref) => switch (ref) {
    ImagePageRef(:final imagePath, :final rotation, :final crop) =>
      'img|$imagePath|$rotation|${crop?.encode() ?? ''}',
    PdfPageRef(:final sourcePath, :final sourceIndex, :final rotation) =>
      'pdf|$sourcePath|$sourceIndex|$rotation',
  };

  void _requestThumbnail() {
    final key = _cacheKey(widget.page.ref);
    _requestedKey = key;
    final renderer = ref.read(pdfRendererProvider);
    _ThumbnailLoader.instance.load(renderer, widget.page.ref, key).then((bytes) {
      if (!mounted || _requestedKey != key) return;
      setState(() {
        _bytes = bytes;
        _failed = bytes == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final kindLabel = widget.page.ref is ImagePageRef ? '사진' : 'PDF';

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            // 실패(손상·경로 없음 등)는 재시도 없이 자리표시자를 유지한다 — 로딩
            // 스피너를 계속 돌리지 않는다(무한 애니메이션이 되는 것을 막는다).
            child: _bytes != null
                ? Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)
                : _failed
                    ? const Center(child: Icon(Icons.broken_image_outlined, size: 20))
                    : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: _Badge(text: '${widget.index + 1}'),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: _Badge(text: kindLabel),
          ),
          if (widget.showCrop)
            Positioned(
              right: 4,
              bottom: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onCropTap,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.crop, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          if (widget.selectMode)
            Positioned(
              left: 4,
              bottom: 4,
              child: Icon(
                widget.selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: widget.selected ? Theme.of(context).colorScheme.primary : Colors.white,
              ),
            ),
          if (widget.selectMode && widget.selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
    );
  }
}

/// 편집 그리드용 썸네일 로더. 동시 렌더 3개 상한 + 동일 키(같은 페이지) 요청
/// 합치기(설계 §1.4 — `DocumentRepository.ensureThumbnail`과 같은 규약). 이 그리드가
/// 여러 화면(S3·사진 흐름)에 재사용되므로 프로세스 전역 싱글턴으로 둔다.
class _ThumbnailLoader {
  _ThumbnailLoader._();
  static final _ThumbnailLoader instance = _ThumbnailLoader._();

  static const int _concurrencyLimit = 3;
  final Map<String, Future<Uint8List?>> _inFlight = {};
  int _active = 0;
  final List<Completer<void>> _queue = [];

  Future<Uint8List?> load(PdfRenderer renderer, PageRef ref, String key) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _run(renderer, ref);
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
    return future;
  }

  Future<Uint8List?> _run(PdfRenderer renderer, PageRef ref) async {
    await _acquire();
    try {
      final result = await renderer.renderPageThumbnail(page: ref, targetWidthPx: gridThumbWidthPx);
      // 실패는 자리표시자 유지(재시도하지 않는다, §1.4와 동일 원칙).
      return switch (result) {
        PdfOk<Uint8List>(:final value) => value,
        PdfErr<Uint8List>() => null,
      };
    } catch (_) {
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < _concurrencyLimit) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
    _active++;
  }

  void _release() {
    _active--;
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    }
  }
}
