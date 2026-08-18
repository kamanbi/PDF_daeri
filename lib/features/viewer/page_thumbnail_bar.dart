/// S4 뷰어 하단 썸네일 바. (설계 §2.1·§2.2·§5.3, 2주차 신설)
///
/// 이 파일은 뷰어 본체(`viewer_screen.dart`)와 분리해 **자신만의** 렌더 큐·LRU를
/// 갖는다 — 렌더 큐 로직이 화면 상태와 섞이지 않게 하기 위함(설계 §6.1).
///
/// 규칙(설계 §2.2): 높이 72dp, 셀 폭 = 높이 × 종횡비, `renderPage(targetWidthPx: 96)`,
/// LRU 40장, 동시 렌더 2개. 2,668p 문서에서도 화면 밖 셀은 렌더하지 않는다(§5.3).
library;

import 'dart:async' show unawaited;
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../pdf/pdf_renderer.dart';

const double _barHeight = 72;
const int _thumbWidthPx = 96;
const int _lruCapacity = 40;
const int _maxConcurrent = 2;

class PageThumbnailBar extends StatefulWidget {
  const PageThumbnailBar({
    super.key,
    required this.renderer,
    required this.pdfPath,
    required this.password,
    required this.sizes,
    required this.currentPage,
    required this.onPageSelected,
  });

  final PdfRenderer renderer;
  final String pdfPath;
  final String? password;
  final List<PdfPageSize> sizes;
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  @override
  State<PageThumbnailBar> createState() => _PageThumbnailBarState();
}

class _PageThumbnailBarState extends State<PageThumbnailBar> {
  // LRU: LinkedHashMap 순서 = 접근 순서. 가장 앞이 가장 오래된 항목.
  final _cache = <int, Uint8List>{};
  final _inFlight = <int>{};
  final _queue = Queue<int>();
  int _running = 0;
  bool _disposed = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  void _request(int index) {
    if (_disposed) return;
    if (_cache.containsKey(index)) return;
    if (_inFlight.contains(index)) return;
    if (index < 0 || index >= widget.sizes.length) return;
    _queue.add(index);
    _pump();
  }

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      final index = _queue.removeFirst();
      if (_cache.containsKey(index) || _inFlight.contains(index)) continue;
      _inFlight.add(index);
      _running++;
      unawaited(_renderOne(index));
    }
  }

  Future<void> _renderOne(int index) async {
    try {
      final result = await widget.renderer.renderPage(
        pdfPath: widget.pdfPath,
        pageIndex: index,
        targetWidthPx: _thumbWidthPx,
        password: widget.password,
        cancelToken: CancelToken(),
      );
      if (_disposed) return;
      switch (result) {
        case PdfOk<Uint8List>(:final value):
          _cache[index] = value; // 최근 사용으로 끝에 삽입
          if (_cache.length > _lruCapacity) {
            _cache.remove(_cache.keys.first);
          }
          if (mounted) setState(() {});
        case PdfErr<Uint8List>():
          // §5.4: 한 페이지의 렌더 실패가 나머지 열람을 막지 않는다 — 자리표시자 유지, 재시도 안 함.
          break;
      }
    } finally {
      _inFlight.remove(index);
      _running--;
      if (!_disposed) _pump();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _barHeight,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: widget.sizes.length,
        itemBuilder: (context, index) {
          _request(index);
          final bytes = _cache[index];
          final aspect = widget.sizes[index].aspectRatio;
          final selected = index == widget.currentPage;
          return GestureDetector(
            onTap: () => widget.onPageSelected(index),
            child: Container(
              width: _barHeight * aspect,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: bytes == null
                  ? const ColoredBox(
                      color: Color(0x11000000),
                      child: Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          );
        },
      ),
    );
  }
}
