/// 뷰어 본문 검색 상태·순차 스캔. (설계 `_workspace/83` §4.2, §4.2a/b, §4.3)
///
/// 정규화는 이 파일이 직접 하지 않는다 — 질의어는 `FileName.normalizeForMatch`,
/// 페이지 본문은 `FileName.normalizeForMatchWithMap`만 쓴다(§4.2a QC 항목).
/// 화면 전용 — `app/providers.dart`에 올리지 않는다(§4.6).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/file_name.dart';
import '../../pdf/pdf_renderer.dart';

/// [ViewerTextSearchNotifier] family 키. 압축 교체로 pdfPath가 바뀌면 키가
/// 바뀌어 자동으로 새 인스턴스가 된다(§4.6). `pageCount`는 스캔 범위 결정에만
/// 쓰이며 문서 식별(동등성)에는 관여하지 않는다.
class ViewerSearchKey {
  const ViewerSearchKey(this.pdfPath, this.password, this.pageCount);
  final String pdfPath;
  // 렌더러 호출에 평문이 필요해 필드는 유지하되, 동등성·해시·toString에는 토큰만 쓴다.
  final String? password;
  final int pageCount;

  @override
  bool operator ==(Object other) =>
      other is ViewerSearchKey &&
      other.pdfPath == pdfPath &&
      pdfPasswordToken(other.password) == pdfPasswordToken(password);

  @override
  int get hashCode => Object.hash(pdfPath, pdfPasswordToken(password));

  @override
  String toString() => 'ViewerSearchKey($pdfPath, ${pdfPasswordToken(password)})';
}

class ViewerSearchMatch {
  const ViewerSearchMatch(this.pageIndex, this.start, this.end);
  final int pageIndex;
  final int start; // PdfPageTextData.text 기준(원문 인덱스), end 미포함
  final int end;
}

class ViewerSearchState {
  const ViewerSearchState({
    this.query = '',
    this.matches = const [],
    this.currentIndex,
    this.scannedPages = 0,
    this.totalPages = 0,
    this.searching = false,
    this.hasAnyText = true,
  });

  final String query;
  final List<ViewerSearchMatch> matches;
  final int? currentIndex;
  final int scannedPages;
  final int totalPages;
  final bool searching;
  // 문서 전체 스캔 완료 후에도 텍스트가 전혀 없었으면 false — "텍스트 인식을
  // 먼저 실행하세요" 안내에 쓰인다(§4.2 문서 흐름).
  final bool hasAnyText;

  ViewerSearchState copyWith({
    String? query,
    List<ViewerSearchMatch>? matches,
    int? Function()? currentIndex,
    int? scannedPages,
    int? totalPages,
    bool? searching,
    bool? hasAnyText,
  }) {
    return ViewerSearchState(
      query: query ?? this.query,
      matches: matches ?? this.matches,
      currentIndex: currentIndex != null ? currentIndex() : this.currentIndex,
      scannedPages: scannedPages ?? this.scannedPages,
      totalPages: totalPages ?? this.totalPages,
      searching: searching ?? this.searching,
      hasAnyText: hasAnyText ?? this.hasAnyText,
    );
  }
}

class ViewerTextSearchNotifier extends StateNotifier<ViewerSearchState> {
  ViewerTextSearchNotifier(this._renderer, this._key, this._pageCount)
    : super(ViewerSearchState(totalPages: _pageCount));

  final PdfRenderer _renderer;
  final ViewerSearchKey _key;
  final int _pageCount;

  CancelToken? _scanToken;
  final Map<int, PdfPageTextData> _textCache = {};

  /// 이전 검색을 취소하고 0p부터 순차 스캔. 공백·빈 문자열이면 reset.
  Future<void> search(String query) async {
    _scanToken?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      reset();
      return;
    }

    final token = CancelToken();
    _scanToken = token;
    final normalizedQuery = FileName.normalizeForMatch(query);

    state = ViewerSearchState(
      query: query,
      totalPages: _pageCount,
      searching: true,
    );

    if (normalizedQuery.isEmpty) {
      state = state.copyWith(searching: false);
      return;
    }

    var foundAnyTextAtAll = false;
    final matches = <ViewerSearchMatch>[];

    for (var pageIndex = 0; pageIndex < _pageCount; pageIndex++) {
      if (token.isCancelled) return;

      final pageText = await _loadPageText(pageIndex, token);
      if (token.isCancelled) return;
      if (pageText != null && pageText.text.isNotEmpty) {
        foundAnyTextAtAll = true;
        final normalized = FileName.normalizeForMatchWithMap(pageText.text);
        matches.addAll(_findMatches(pageIndex, normalizedQuery, normalized));
      }

      if (token.isCancelled) return;
      state = state.copyWith(
        matches: List.of(matches),
        scannedPages: pageIndex + 1,
        currentIndex: matches.isNotEmpty && state.currentIndex == null
            ? () => 0
            : () => state.currentIndex,
      );
    }

    if (token.isCancelled) return;
    state = state.copyWith(searching: false, hasAnyText: foundAnyTextAtAll);
  }

  List<ViewerSearchMatch> _findMatches(
    int pageIndex,
    String normalizedQuery,
    NormalizedText normalized,
  ) {
    final result = <ViewerSearchMatch>[];
    if (normalized.text.isEmpty) return result;
    var from = 0;
    while (true) {
      final ns = normalized.text.indexOf(normalizedQuery, from);
      if (ns < 0) break;
      final ne = ns + normalizedQuery.length;
      final start = normalized.origStart[ns];
      final end = normalized.origEnd[ne - 1];
      result.add(ViewerSearchMatch(pageIndex, start, end));
      from = ns + 1;
    }
    return result;
  }

  Future<PdfPageTextData?> _loadPageText(int pageIndex, CancelToken token) async {
    final cached = _textCache[pageIndex];
    if (cached != null) return cached;
    final result = await _renderer.pageText(
      pdfPath: _key.pdfPath,
      pageIndex: pageIndex,
      password: _key.password,
      cancelToken: token,
    );
    if (token.isCancelled) return null;
    switch (result) {
      case PdfOk<PdfPageTextData>(:final value):
        _textCache[pageIndex] = value;
        return value;
      case PdfErr<PdfPageTextData>():
        return null;
    }
  }

  void next() {
    final matches = state.matches;
    if (matches.isEmpty) return;
    final current = state.currentIndex ?? -1;
    final nextIndex = (current + 1) % matches.length;
    state = state.copyWith(currentIndex: () => nextIndex);
  }

  void prev() {
    final matches = state.matches;
    if (matches.isEmpty) return;
    final current = state.currentIndex ?? 0;
    final prevIndex = (current - 1 + matches.length) % matches.length;
    state = state.copyWith(currentIndex: () => prevIndex);
  }

  void reset() {
    _scanToken?.cancel();
    _scanToken = null;
    state = ViewerSearchState(totalPages: _pageCount);
  }

  /// 페이지의 텍스트(하이라이트 그릴 때 오버레이가 사용). 캐시 적중만 반환.
  PdfPageTextData? textOf(int pageIndex) => _textCache[pageIndex];

  @override
  void dispose() {
    _scanToken?.cancel();
    super.dispose();
  }
}

final viewerTextSearchProvider = StateNotifierProvider.autoDispose
    .family<ViewerTextSearchNotifier, ViewerSearchState, ViewerSearchKey>((
      ref,
      key,
    ) {
      return ViewerTextSearchNotifier(
        ref.watch(pdfRendererProvider),
        key,
        key.pageCount,
      );
    });
