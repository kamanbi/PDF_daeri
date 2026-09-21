/// 주석(형광펜·텍스트) 화면. (`_workspace/79_architect_v1.1_v2_design.md` §6, §13 배치 4 항목 12)
///
/// 진입: S4 뷰어 `⋮` 메뉴 "주석 추가" → 현재 페이지에서 시작(§6.4 — S3 편집
/// 화면에 넣지 않는다. S3는 3열 썸네일 그리드라 페이지 위 정밀 배치가 불가능).
///
/// 도구 3개뿐: `형광펜` / `텍스트` / `선택·삭제`. 되돌리기 1개(UX 원칙).
///
/// 저장 흐름은 §3.4(서명)와 동일하다 — `buildStampInIsolate` → `PdfEngine.stamp`
/// (`DocumentRepository.stampToNewDocument`, `titleFor: FileName.annotatedTitle`).
/// 서명과 주석이 서로 다른 저장 경로를 갖지 않는다.
///
/// **배너를 넣지 않는다.** `ads.md` 노출 지점표에 없는 화면 = 배너 없음(규칙 7).
/// 드래그 제스처가 상시 일어나는 화면이기도 하다.
///
/// 이 화면은 `AppRoutes`/`router.dart`에 새 라우트로 등록하지 않는다 —
/// `signature_screen.dart`와 같은 방식으로 [showAnnotateScreen]을 통해서만 연다.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/file_name.dart';
import '../../core/korean_font.dart';
import '../../core/progress.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/pdf_renderer.dart';
import '../../pdf/stamp_builder.dart';
import '../common/failure_ui.dart';
import '../edit/stamp_placement.dart';

/// 형광펜 4색(Q9 승인). 값 자체가 곧 [HighlightMark.colorArgb]다.
const List<int> highlightColorChoices = [
  0xFFFFF176, // 노랑
  0xFFAED581, // 연두
  0xFFF48FB1, // 분홍
  0xFF81D4FA, // 하늘색
];

const double _defaultTextFontSizePt = 18;

/// 주석 화면이 필요로 하는 대상 문서 정보. `ViewerArgs`에서 그대로 옮겨 담는다.
class AnnotateArgs {
  const AnnotateArgs({
    required this.pdfPath,
    required this.title,
    required this.pageCount,
    required this.initialPageIndex,
    this.password,
  });

  final String pdfPath;
  final String title;
  final int pageCount;
  final int initialPageIndex;
  final String? password;
}

/// 주석 화면을 전체화면으로 연다. 성공하면 새로 만들어진 문서의
/// `DocumentSummary`를, 취소·실패면 `null`을 반환한다.
Future<DocumentSummary?> showAnnotateScreen({
  required BuildContext context,
  required AnnotateArgs args,
}) {
  return Navigator.of(context).push<DocumentSummary?>(
    MaterialPageRoute(builder: (_) => AnnotateScreen(args: args)),
  );
}

enum _Tool { highlight, text, select }

enum _Stage { loading, placing, saving }

/// 화면에 얹힌 마크 하나. [StampMark]는 불변이므로 이동·리사이즈 시마다
/// 새 값으로 교체한다 — 식별은 [id]로 한다.
class _PlacedMark {
  _PlacedMark({required this.id, required this.mark});
  final int id;
  StampMark mark;
}

class AnnotateScreen extends ConsumerStatefulWidget {
  const AnnotateScreen({super.key, required this.args});
  final AnnotateArgs args;

  @override
  ConsumerState<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends ConsumerState<AnnotateScreen> {
  _Stage _stage = _Stage.loading;
  _Tool _tool = _Tool.highlight;
  Uint8List? _pageBytes;
  PdfPageGeometry? _geometry;
  PdfProgress? _progress;
  CancelToken? _cancelToken;
  bool _cancelling = false;

  final List<_PlacedMark> _marks = [];
  final List<List<_PlacedMark>> _undoStack = [];
  int _nextId = 0;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final renderer = ref.read(pdfRendererProvider);
    final geometryResult = await renderer.pageGeometry(
      widget.args.pdfPath,
      password: widget.args.password,
    );
    if (!mounted) return;
    if (geometryResult is PdfErr<PdfPageGeometry>) {
      await FailureUi.showDialog(context, geometryResult.failure);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _geometry = (geometryResult as PdfOk<PdfPageGeometry>).value;

    final pageResult = await renderer.renderPage(
      pdfPath: widget.args.pdfPath,
      pageIndex: widget.args.initialPageIndex,
      targetWidthPx: 900,
      password: widget.args.password,
    );
    if (!mounted) return;
    if (pageResult is PdfErr<Uint8List>) {
      await FailureUi.showDialog(context, pageResult.failure);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _pageBytes = (pageResult as PdfOk<Uint8List>).value;
      _stage = _Stage.placing;
    });
  }

  double get _aspectRatio =>
      _geometry!.sizes[widget.args.initialPageIndex].aspectRatio;

  void _pushUndoSnapshot() {
    _undoStack.add([for (final m in _marks) _PlacedMark(id: m.id, mark: m.mark)]);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _marks
        ..clear()
        ..addAll(_undoStack.removeLast());
      _selectedId = null;
    });
  }

  Future<void> _addHighlight() async {
    final color = await _pickHighlightColor();
    if (color == null || !mounted) return;
    _pushUndoSnapshot();
    final id = _nextId++;
    setState(() {
      _marks.add(
        _PlacedMark(
          id: id,
          mark: HighlightMark(rect: defaultStampRect(), colorArgb: color),
        ),
      );
      _selectedId = id;
      _tool = _Tool.select;
    });
  }

  Future<void> _addText() async {
    final text = await _promptText();
    if (text == null || text.trim().isEmpty || !mounted) return;
    _pushUndoSnapshot();
    final id = _nextId++;
    setState(() {
      _marks.add(
        _PlacedMark(
          id: id,
          mark: TextMark(
            rect: defaultStampRect(aspectRatio: 4),
            text: text.trim(),
            fontSizePt: _defaultTextFontSizePt,
          ),
        ),
      );
      _selectedId = id;
      _tool = _Tool.select;
    });
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    _pushUndoSnapshot();
    setState(() {
      _marks.removeWhere((m) => m.id == id);
      _selectedId = null;
    });
  }

  Future<int?> _pickHighlightColor() {
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final color in highlightColorChoices)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(color),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _promptText() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('텍스트 추가'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '내용을 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  bool get _showCancelButton {
    final baseline = File(widget.args.pdfPath).lengthSync();
    return widget.args.pageCount >= 50 || baseline >= 20 * 1024 * 1024;
  }

  Future<void> _save() async {
    final geometry = _geometry;
    if (geometry == null || _marks.isEmpty) return;

    Uint8List? koreanFontBytes;
    final hasTextMark = _marks.any((m) => m.mark is TextMark);
    if (hasTextMark) {
      try {
        koreanFontBytes = await KoreanFont.bytes();
      } on KoreanFontMissing {
        if (!mounted) return;
        await FailureUi.showDialog(
          context,
          const UnknownFailure('한글 폰트를 불러오지 못해 텍스트를 추가할 수 없습니다.'),
        );
        return;
      }
    }

    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) {
      if (!mounted) return;
      await FailureUi.showDialog(
        context,
        const UnknownFailure('저장소를 사용할 수 없습니다.'),
      );
      return;
    }

    final token = CancelToken();
    setState(() {
      _stage = _Stage.saving;
      _progress = null;
      _cancelToken = token;
      _cancelling = false;
    });

    final pageSpecs = [
      for (var i = 0; i < geometry.pageCount; i++)
        StampPageSpec(
          widthPt: geometry.sizes[i].widthPt,
          heightPt: geometry.sizes[i].heightPt,
          marks: i == widget.args.initialPageIndex
              ? [for (final m in _marks) m.mark]
              : const [],
        ),
    ];

    final buildResult = await buildStampInIsolate(
      pages: pageSpecs,
      koreanFontBytes: koreanFontBytes,
    );

    if (!mounted) return;
    if (buildResult.error != null) {
      setState(() => _stage = _Stage.placing);
      await FailureUi.showDialog(
        context,
        const UnknownFailure('주석을 적용하지 못했습니다.'),
      );
      return;
    }

    final baselineBytes = File(widget.args.pdfPath).lengthSync();
    final result = await repo.stampToNewDocument(
      sourcePdfPath: widget.args.pdfPath,
      originalTitle: widget.args.title,
      stampPdfBytes: buildResult.pdfBytes!,
      pageCount: geometry.pageCount,
      baselineBytes: baselineBytes,
      titleFor: FileName.annotatedTitle,
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
        setState(() => _stage = _Stage.placing);
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
    return Scaffold(
      appBar: AppBar(title: const Text('주석 추가')),
      body: switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator()),
        _Stage.placing => _buildPlacing(context),
        _Stage.saving => _buildSaving(context),
      },
    );
  }

  Widget _buildPlacing(BuildContext context) {
    final pageBytes = _pageBytes;
    if (pageBytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _PlacedMark? selected;
    for (final m in _marks) {
      if (m.id == _selectedId) {
        selected = m;
        break;
      }
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(pageBytes, fit: BoxFit.contain),
                      for (final m in _marks)
                        if (m.id != _selectedId)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => setState(() {
                                _tool = _Tool.select;
                                _selectedId = m.id;
                              }),
                              child: _StaticMarkView(mark: m.mark),
                            ),
                          ),
                    ],
                  ),
                ),
                if (selected case final _PlacedMark selectedMark)
                  StampPlacement(
                    pageAspectRatio: _aspectRatio,
                    pageChild: const SizedBox.expand(),
                    overlayChild: _MarkContentView(mark: selectedMark.mark),
                    rect: selectedMark.mark.rect,
                    onRectChanged: (rect) => setState(() {
                      selectedMark.mark = _withRect(selectedMark.mark, rect);
                    }),
                  ),
              ],
            ),
          ),
        ),
        // Q6(승인): 저장 후 재편집 불가 — 저장 버튼 직전 1줄 안내(확인 다이얼로그
        // 아님, UX 원칙 "확인 창 만들지 않는다").
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '저장하면 주석이 문서에 합쳐져 수정할 수 없습니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            children: [
              _ToolButton(
                label: '형광펜',
                selected: _tool == _Tool.highlight,
                onPressed: _addHighlight,
              ),
              _ToolButton(
                label: '텍스트',
                selected: _tool == _Tool.text,
                onPressed: _addText,
              ),
              _ToolButton(
                label: '선택·삭제',
                selected: _tool == _Tool.select,
                onPressed: () => setState(() => _tool = _Tool.select),
              ),
              TextButton(
                onPressed: _undoStack.isEmpty ? null : _undo,
                child: const Text('되돌리기'),
              ),
              if (_selectedId != null)
                TextButton(
                  onPressed: _deleteSelected,
                  child: const Text('삭제'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              const Spacer(),
              FilledButton(
                onPressed: _marks.isEmpty ? null : _save,
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaving(BuildContext context) {
    final fraction = _progress?.fraction ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('저장 중…', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: fraction == 0 ? null : fraction),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${(fraction * 100).round()}%'),
                if (_showCancelButton) ...[
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: _cancelling ? null : _cancel,
                    child: Text(_cancelling ? '취소 중…' : '취소'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

StampMark _withRect(StampMark mark, StampRect rect) => switch (mark) {
  ImageMark(:final pngBytes) => ImageMark(rect: rect, pngBytes: pngBytes),
  HighlightMark(:final colorArgb, :final opacity) =>
    HighlightMark(rect: rect, colorArgb: colorArgb, opacity: opacity),
  TextMark(:final text, :final fontSizePt, :final colorArgb, :final invisible) =>
    TextMark(rect: rect, text: text, fontSizePt: fontSizePt, colorArgb: colorArgb, invisible: invisible),
};

/// 선택되지 않은 마크를 화면에 정적으로 표시한다(탭하면 선택 전환).
/// 실제 저장 결과의 렌더는 `StampBuilder`가 하며, 이 위젯은 배치 편집용 근사
/// 미리보기일 뿐이다.
class _StaticMarkView extends StatelessWidget {
  const _StaticMarkView({required this.mark});
  final StampMark mark;

  @override
  Widget build(BuildContext context) {
    final rect = mark.rect;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned(
              left: rect.left * constraints.maxWidth,
              top: rect.top * constraints.maxHeight,
              width: rect.widthFraction * constraints.maxWidth,
              height: rect.heightFraction * constraints.maxHeight,
              child: _MarkContentView(mark: mark),
            ),
          ],
        );
      },
    );
  }
}

/// 마크 하나의 실제 내용(색 사각형 또는 텍스트).
class _MarkContentView extends StatelessWidget {
  const _MarkContentView({required this.mark});
  final StampMark mark;

  @override
  Widget build(BuildContext context) {
    return switch (mark) {
      HighlightMark(:final colorArgb, :final opacity) => Container(
        color: Color(colorArgb).withValues(alpha: opacity),
      ),
      TextMark(:final text, :final colorArgb) => Container(
        alignment: Alignment.centerLeft,
        color: Colors.transparent,
        child: Text(
          text,
          style: TextStyle(color: Color(colorArgb)),
          overflow: TextOverflow.fade,
        ),
      ),
      ImageMark() => const SizedBox.shrink(),
    };
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.selected, required this.onPressed});
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}
