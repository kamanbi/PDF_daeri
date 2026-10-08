/// 페이지 텍스트 오버레이 — 검색 하이라이트 페인트 + 길게 누름·드래그 선택.
/// (설계 `_workspace/83` §4.4, §4.5)
///
/// `InteractiveViewer`의 `child` 안쪽(줌 변환을 자동 공유하는 좌표계)에 놓인다.
/// 좌표 변환(PDF pt → 위젯 px)은 이 파일 안의 [_toLocal]에서만 한다(다른 곳에
/// 두지 않는다 — §4.1 소유표).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../pdf/pdf_renderer.dart';

class PageTextOverlay extends StatefulWidget {
  const PageTextOverlay({
    super.key,
    required this.pageWidthPt,
    required this.pageText,
    required this.selectionEnabled,
    this.searchHighlights = const [],
    this.currentSearchHighlights = const [],
    required this.onSelectionChanged,
  });

  /// 페이지 폭(포인트). 위젯 폭과의 비율이 pt → px 스케일이다.
  final double pageWidthPt;
  final PdfPageTextData? pageText;
  final bool selectionEnabled;
  final List<Rect> searchHighlights;
  final List<Rect> currentSearchHighlights;

  /// 선택 범위가 바뀔 때마다 호출된다. null이면 선택 없음.
  final void Function(int? start, int? end) onSelectionChanged;

  @override
  State<PageTextOverlay> createState() => PageTextOverlayState();
}

class PageTextOverlayState extends State<PageTextOverlay> {
  int? _anchor;
  int? _focus;

  @override
  void didUpdateWidget(covariant PageTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selectionEnabled && oldWidget.selectionEnabled) {
      _clearSelection();
    }
    if (oldWidget.pageText != widget.pageText) {
      _clearSelection();
    }
  }

  void _clearSelection() {
    if (_anchor == null && _focus == null) return;
    setState(() {
      _anchor = null;
      _focus = null;
    });
    widget.onSelectionChanged(null, null);
  }

  /// 외부(하단 칩 "전체 선택")에서 호출.
  void selectAll() {
    final text = widget.pageText;
    if (text == null || text.text.isEmpty) return;
    setState(() {
      _anchor = 0;
      _focus = text.text.length - 1;
    });
    widget.onSelectionChanged(0, text.text.length);
  }

  Offset _toPt(Offset local, double scale) => Offset(local.dx / scale, local.dy / scale);

  void _reportSelection() {
    if (_anchor == null || _focus == null) return;
    final start = math.min(_anchor!, _focus!);
    final end = math.max(_anchor!, _focus!) + 1;
    widget.onSelectionChanged(start, end);
  }

  void _onLongPressStart(LongPressStartDetails details, double scale) {
    final pageText = widget.pageText;
    if (pageText == null || pageText.text.isEmpty) return;
    final idx = pageText.hitTest(_toPt(details.localPosition, scale));
    if (idx == null) return;
    setState(() {
      _anchor = idx;
      _focus = idx;
    });
    _reportSelection();
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details, double scale) {
    final pageText = widget.pageText;
    if (pageText == null || _anchor == null) return;
    final idx = pageText.hitTest(_toPt(details.localPosition, scale), slopPt: 24);
    if (idx == null) return;
    setState(() => _focus = idx);
    _reportSelection();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.biggest.width;
        final scale = widget.pageWidthPt <= 0 ? 1.0 : width / widget.pageWidthPt;
        Rect toLocal(Rect r) => Rect.fromLTRB(
          r.left * scale,
          r.top * scale,
          r.right * scale,
          r.bottom * scale,
        );

        final pageText = widget.pageText;
        final selectionRects = (_anchor != null && _focus != null && pageText != null)
            ? pageText
                  .rectsFor(
                    math.min(_anchor!, _focus!),
                    math.max(_anchor!, _focus!) + 1,
                  )
                  .map(toLocal)
                  .toList()
            : const <Rect>[];

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: widget.selectionEnabled
              ? (d) => _onLongPressStart(d, scale)
              : null,
          onLongPressMoveUpdate: widget.selectionEnabled
              ? (d) => _onLongPressMove(d, scale)
              : null,
          child: CustomPaint(
            size: constraints.biggest,
            painter: _OverlayPainter(
              searchHighlights: widget.searchHighlights.map(toLocal).toList(),
              currentSearchHighlights: widget.currentSearchHighlights
                  .map(toLocal)
                  .toList(),
              selectionHighlights: selectionRects,
            ),
          ),
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.searchHighlights,
    required this.currentSearchHighlights,
    required this.selectionHighlights,
  });

  final List<Rect> searchHighlights;
  final List<Rect> currentSearchHighlights;
  final List<Rect> selectionHighlights;

  @override
  void paint(Canvas canvas, Size size) {
    final normalPaint = Paint()..color = const Color(0x80FFEB3B); // 노랑
    final currentPaint = Paint()..color = const Color(0xB0FF9800); // 주황
    final selectionPaint = Paint()..color = const Color(0x552196F3); // 파랑

    for (final r in searchHighlights) {
      canvas.drawRect(r, normalPaint);
    }
    for (final r in currentSearchHighlights) {
      canvas.drawRect(r, currentPaint);
    }
    for (final r in selectionHighlights) {
      canvas.drawRect(r, selectionPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return !_listEquals(oldDelegate.searchHighlights, searchHighlights) ||
        !_listEquals(
          oldDelegate.currentSearchHighlights,
          currentSearchHighlights,
        ) ||
        !_listEquals(oldDelegate.selectionHighlights, selectionHighlights);
  }

  bool _listEquals(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
