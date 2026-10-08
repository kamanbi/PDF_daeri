/// 뷰어 본문 검색 바. AppBar.bottom 44px 줄을 이 위젯으로 통째로 교체한다
/// (높이 불변 → 레이아웃 점프 없음, 배너 위치 불변). (설계 `_workspace/83` §4.4)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/app_locale.dart';

import 'viewer_text_search.dart';

class ViewerSearchBar extends StatefulWidget {
  const ViewerSearchBar({
    super.key,
    required this.state,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  final ViewerSearchState state;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  @override
  State<ViewerSearchBar> createState() => _ViewerSearchBarState();
}

class _ViewerSearchBarState extends State<ViewerSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onQueryChanged(value);
    });
  }

  String _countLabel() {
    final s = widget.state;
    if (s.query.trim().isEmpty) return '';
    if (s.searching) return '${s.scannedPages}/${s.totalPages}…';
    if (s.matches.isEmpty) return '0/0';
    final current = (s.currentIndex ?? 0) + 1;
    return '$current/${s.matches.length}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: appText(context, '검색 닫기'),
            onPressed: widget.onClose,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: appText(context, '문서 안 검색'),
                border: InputBorder.none,
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_countLabel().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_countLabel()),
            ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: appText(context, '이전 일치'),
            onPressed: widget.state.matches.isEmpty ? null : widget.onPrev,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: appText(context, '다음 일치'),
            onPressed: widget.state.matches.isEmpty ? null : widget.onNext,
          ),
        ],
      ),
    );
  }
}
