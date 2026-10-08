/// S4 뷰어. 좌우 스와이프 · 핀치 줌 · 하단 썸네일 바. (설계 §2.0~§2.3, 2주차 신설)
///
/// `PdfRenderer.renderPage` 위에 `PageView` + `InteractiveViewer`로 직접 구현한다.
/// `pdfrx`의 `PdfViewer` 위젯은 쓰지 않는다(§2.2 — 두 번째 렌더 경로 금지).
/// 텍스트 선택(복사)·본문 검색은 2026-09-23 승인(`screens.md` S4,
/// `_workspace/83` 설계 B안) — 이 렌더 구조 위에 `PageTextOverlay`로 얹는다.
/// 텍스트 수정은 영구 제외(읽기 전용, `pdf_engine.dart` 저장 경로 미접촉).
/// 상단 액션은 AppBar.bottom 텍스트 버튼 줄(⋮ 금지). 검색 모드일 때는 같은
/// 44px 줄이 검색 바로 교체된다(레이아웃 점프 없음).
///
/// **오분류 흡수 판단(§FailureUi 문서, 인계 사항 반영)**: `pageGeometry`는
/// pdfrx 경로이므로 손상 파일을 `SourceEncrypted`로 오분류할 수 있다(`24번
/// 문서` 미해결 항목). 뷰어는 비밀번호 재입력 UI를 갖지 않는다 — 정말 암호가
/// 걸린 문서라면 S2-b가 이미 올바른 비밀번호로 `PdfEngine.inspect`를 통과시켜
/// 뷰어까지 넘어온 것이므로, 뷰어 단계에서 다시 `SourceEncrypted`가 나오는 것은
/// "비밀번호가 틀렸다"보다 "pdfrx가 이 파일을 못 읽는다"일 가능성이 훨씬 크다.
/// 그래서 여기서는 안전하게 `SourceCorrupted`로 합쳐 "열 수 없는 파일입니다"
/// 계열로 보여준다(재입력을 유도해 사용자를 막힌 화면에 가두지 않기 위함).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/banner_host.dart';
import '../../billing/billing_service.dart';
import '../../billing/entitlement.dart';
import '../../app/providers.dart';
import '../../app/app_locale.dart';
import '../../app/router.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/pdf_renderer.dart';
import '../common/failure_ui.dart';
import '../common/share_flow.dart';
import '../annotate/annotate_screen.dart';
import '../edit/ocr_screen.dart';
import '../edit/signature_screen.dart';
import 'compress_sheet.dart';
import 'page_text_overlay.dart';
import 'page_thumbnail_bar.dart';
import 'viewer_search_bar.dart';
import 'viewer_text_search.dart';

/// 프리로드 범위(현재 ±1)와 메모리 LRU 상한(§2.2).
const int _preloadRadius = 1;
const int _pageLruCapacity = 5;
const int _basePxCap = 2048;
const int _zoomPxCap = 4096;
const double _highResScaleThreshold = 1.8;
const Duration _zoomSettleDelay = Duration(milliseconds: 250);

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.args});
  final ViewerArgs args;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  bool _loading = true;
  PdfPageGeometry? _geometry;
  PdfFailure? _fatalFailure;
  late final PageController _pageController;
  int _currentPage = 0;

  // 압축 결과로 배경 문서를 교체할 수 있어야 하므로(§31 §4.3 "결과 시트가 뜨는
  // 순간 배경의 뷰어를 압축 결과 파일로 교체") `_args`를 고정값으로 쓰지
  // 않고 이 필드에 복사해 둔다. 화면을 새로 쌓지 않는다 -- 같은 ViewerScreen이
  // 새 pdfPath를 가리키도록 갱신될 뿐이다.
  late ViewerArgs _args = widget.args;

  // 페이지 이미지 메모리 캐시(LRU 5) + 페이지별 진행 중 취소 토큰. 뷰어 본체
  // 소유 — 썸네일 바(`PageThumbnailBar`)는 자신만의 캐시를 따로 갖는다(§2.2).
  final _bytesCache = <int, Uint8List>{};
  final _cancelTokens = <int, CancelToken>{};
  final _renderedWidthPx = <int, int>{};
  final _loadingPages = <int>{};
  late final StateController<bool> _busyNotifier;
  late final PdfRenderer _renderer;

  // 텍스트 선택·본문 검색(2026-09-23 승인, `_workspace/83` B안). 검색 모드와
  // 선택 모드는 동시에 하나만 켤 수 있다(§4.4 UI 배치 — 툴바 자리가 겹친다).
  bool _searchMode = false;
  bool _selectionMode = false;
  // 선택 모드는 현재 페이지에서만 동작한다(모드 진입 시 PageView가 잠기므로
  // 페이지 이동은 썸네일 바를 통해서만 일어나고, 그때마다 다시 로드한다).
  int? _selectionPageIndex;
  PdfPageTextData? _selectionPageText;
  (int, int)? _selectionRange; // [start, end)
  final _selectionOverlayKey = GlobalKey<PageTextOverlayState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _renderer = ref.read(pdfRendererProvider);
    // StateController 자체를 붙잡아 둔다 — `ref`(WidgetRef)는 dispose 이후
    // 접근하면 예외를 던지지만, 한 번 얻은 컨트롤러는 계속 유효하다.
    _busyNotifier = ref.read(appBusyProvider.notifier);
    // Riverpod은 위젯 생명주기(빌드·initState·dispose 등) 중 프로바이더 상태
    // 동기 수정을 금지한다("Tried to modify a provider while the widget tree
    // was building") — `scan_screen.dart`와 동일하게 `Future.microtask`로 미룬다.
    // `mounted`(StateController가 노출하는 것)는 미루는 동안 컨테이너가 먼저
    // dispose된 경우(위젯 테스트 종료 등)를 방어한다.
    Future.microtask(() {
      if (_busyNotifier.mounted) _busyNotifier.state = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGeometry());
  }

  Future<void> _loadGeometry() async {
    if (!mounted) {
      _busyNotifier.state = false;
      return;
    }
    try {
      final renderer = ref.read(pdfRendererProvider);
      final result = await renderer.pageGeometry(
        _args.pdfPath,
        password: _args.password,
      );
      if (!mounted) return;

      switch (result) {
        case PdfOk<PdfPageGeometry>(:final value):
          if (value.pageCount != _args.pageCount) {
            // §2.3: pageGeometry의 pageCount를 진실로 삼는다. 불일치는 임포트 경로의
            // 결함 신호이므로 로그만 남기고 진행을 막지 않는다.
            debugPrint(
              'ViewerScreen: pageCount 불일치 (args=${_args.pageCount}, geometry=${value.pageCount})',
            );
          }
          setState(() {
            _geometry = value;
            _loading = false;
          });
          _prefetchAround(0);
        case PdfErr<PdfPageGeometry>(:final failure):
          final mapped = failure is SourceEncrypted
              ? SourceCorrupted(_args.pdfPath)
              : failure;
          setState(() {
            _loading = false;
            _fatalFailure = mapped;
          });
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleFatalFailure(mapped),
          );
      }
    } finally {
      _busyNotifier.state = false;
    }
  }

  Future<void> _handleFatalFailure(PdfFailure failure) async {
    if (!mounted) return;
    final action = await FailureUi.showDialog(context, failure);
    if (!mounted) return;
    if (action == FailureAction.removeFromList && _args.recentId != null) {
      final recentRepo = ref.read(recentRepositoryProvider);
      await recentRepo?.removeFromList(_args.recentId!);
    }
    if (!mounted) return;
    // 뷰어가 스택 어디에 있었든(push든 pushReplacement든) 홈 하나로 정리한다 —
    // 실패 직후 사용자를 애매한 중간 화면에 남기지 않는다.
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _prefetchAround(index);
    if (_selectionMode && _selectionPageIndex != index) {
      _loadSelectionPageText(index);
    }
  }

  void _prefetchAround(int center) {
    final geometry = _geometry;
    if (geometry == null) return;
    final wanted = <int>{
      for (var i = center - _preloadRadius; i <= center + _preloadRadius; i++)
        if (i >= 0 && i < geometry.pageCount) i,
    };

    // 창 밖으로 나간 진행 중 렌더는 취소한다.
    for (final index in _cancelTokens.keys.toList()) {
      if (!wanted.contains(index)) {
        _cancelTokens.remove(index)?.cancel();
        _loadingPages.remove(index);
      }
    }

    for (final index in wanted) {
      if (_bytesCache.containsKey(index) || _loadingPages.contains(index)) {
        continue;
      }
      _renderPage(index, _basePxTarget());
    }
  }

  int _basePxTarget() {
    final width = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return math.min((width * dpr).round(), _basePxCap);
  }

  Future<void> _renderPage(
    int index,
    int targetWidthPx, {
    bool highRes = false,
  }) async {
    final renderer = ref.read(pdfRendererProvider);
    final token = CancelToken();
    _cancelTokens[index] = token;
    _loadingPages.add(index);

    final result = await renderer.renderPage(
      pdfPath: _args.pdfPath,
      pageIndex: index,
      targetWidthPx: targetWidthPx,
      password: _args.password,
      cancelToken: token,
    );

    _loadingPages.remove(index);
    if (token.isCancelled || !mounted) return;
    if (_cancelTokens[index] == token) _cancelTokens.remove(index);

    switch (result) {
      case PdfOk<Uint8List>(:final value):
        setState(() {
          _bytesCache[index] = value;
          _renderedWidthPx[index] = targetWidthPx;
          _evictLru();
        });
      case PdfErr<Uint8List>():
        // §5.4: 이 페이지만 "표시할 수 없음" 자리표시자로 남기고 문서 전체를
        // 실패로 만들지 않는다. 재시도 없이 넘어간다.
        break;
    }
  }

  void _evictLru() {
    if (_bytesCache.length <= _pageLruCapacity) return;
    // 현재 페이지에서 가장 먼 인덱스부터 정리한다.
    final indices = _bytesCache.keys.toList()
      ..sort(
        (a, b) => (b - _currentPage).abs().compareTo((a - _currentPage).abs()),
      );
    while (_bytesCache.length > _pageLruCapacity && indices.isNotEmpty) {
      final victim = indices.removeAt(0);
      if ((victim - _currentPage).abs() <= _preloadRadius) {
        break; // 화면 근접 페이지는 지키지 않는다
      }
      _bytesCache.remove(victim);
      _renderedWidthPx.remove(victim);
    }
  }

  Future<void> _requestHighRes(int index, double scale) async {
    final geometry = _geometry;
    if (geometry == null) return;
    final base = _basePxTarget();
    final target = math.min((base * scale).round(), _zoomPxCap);
    if (target <= (_renderedWidthPx[index] ?? 0)) return;
    await _renderPage(index, target, highRes: true);
  }

  void _openEdit() {
    // ViewerArgs.docId/recentId는 상호 배타다(§3.3 계약) — 그대로 EditSource 판별에 쓴다.
    final source = _args.docId != null
        ? EditSource.myDocument(_args.docId!)
        : EditSource.externalPdf(
            pdfPath: _args.pdfPath,
            title: _args.title,
            recentId: _args.recentId,
          );
    Navigator.of(context).pushNamed(
      AppRoutes.edit,
      arguments: EditArgs(source: source, title: _args.title),
    );
  }

  // [W4-T1] `shareExportProvider` 배선(설계 §2.6). 암호 PDF는 편집·압축과 달리
  // 공유가 차단되지 않는다("암호 PDF는 보기·공유만 허용하고 편집 진입을 차단한다",
  // 1주차 확정) — 버튼을 `_args.isEncrypted`로 비활성화하지 않는다.
  Future<void> _share() {
    return shareDocument(
      context: context,
      ref: ref,
      pdfPath: _args.pdfPath,
      title: _args.title,
    );
  }

  // Q12(승인) 신설: 서명 추가. `stamp_placement.dart`로 배치 후
  // `PdfEngine.stamp`로 새 문서를 만든다(§3.4). 암호 PDF는 편집·압축과 같은
  // 정책으로 차단한다(§3.3 Q10과 동일 취급 — 스탬프도 전체 재작성 저장이다).
  Future<void> _openSignature() async {
    final geometry = _geometry;
    if (geometry == null) return;
    final result = await showSignatureScreen(
      context: context,
      args: SignatureArgs(
        pdfPath: _args.pdfPath,
        title: _args.title,
        pageCount: geometry.pageCount,
        initialPageIndex: _currentPage,
        password: _args.password,
      ),
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appText(context, '새 파일로 저장됨'))));
    Navigator.of(context).pushNamed(
      AppRoutes.viewer,
      arguments: ViewerArgs(
        pdfPath: ref.read(workspaceProvider)!.docPdf(result.id),
        title: result.title,
        pageCount: result.pageCount,
        docId: result.id,
      ),
    );
  }

  // §13 배치 4 항목 12(주석) 신설: 형광펜·텍스트 상자 배치 후 §3.4와 같은
  // 저장 흐름(`stampToNewDocument`)을 탄다. 암호 PDF는 서명·편집·압축과 같은
  // 정책으로 차단한다(스탬프도 전체 재작성 저장이다).
  Future<void> _openAnnotate() async {
    final geometry = _geometry;
    if (geometry == null) return;
    final result = await showAnnotateScreen(
      context: context,
      args: AnnotateArgs(
        pdfPath: _args.pdfPath,
        title: _args.title,
        pageCount: geometry.pageCount,
        initialPageIndex: _currentPage,
        password: _args.password,
      ),
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appText(context, '새 파일로 저장됨'))));
    Navigator.of(context).pushNamed(
      AppRoutes.viewer,
      arguments: ViewerArgs(
        pdfPath: ref.read(workspaceProvider)!.docPdf(result.id),
        title: result.title,
        pageCount: result.pageCount,
        docId: result.id,
      ),
    );
  }

  // 스캔·사진 페이지와 텍스트가 없는 외부 PDF 페이지를 인식해 새 문서로 저장한다.
  // 암호 PDF는 서명·주석·편집·압축과 같은 정책으로 차단한다.
  Future<void> _openOcr() async {
    final geometry = _geometry;
    if (geometry == null) return;
    final entitlement = ref.read(ocrEntitlementProvider);
    if (entitlement.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, '구독 상태를 확인 중입니다. 잠시 후 다시 시도해 주세요.'))),
      );
      return;
    }
    if (entitlement.valueOrNull != true) {
      final subscribe = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(appText(dialogContext, '텍스트 인식 구독')),
          content: Text(appText(dialogContext, 'OCR로 글자를 검색·선택·복사하고 광고도 제거할 수 있습니다.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(appText(dialogContext, '취소'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(appText(dialogContext, '구독하기'))),
          ],
        ),
      );
      if (!mounted || subscribe != true) return;
      final billing = ref.read(billingServiceProvider);
      final plan = billing.yearlyPlan;
      if (billing.state != PurchaseUiState.available || plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText(context, '지금은 연간 구독 상품을 불러올 수 없습니다.'))),
        );
        return;
      }
      await billing.buy(plan);
      return;
    }
    final result = await showOcrScreen(
      context: context,
      args: OcrArgs(
        docId: _args.docId,
        pdfPath: _args.pdfPath,
        title: _args.title,
        pageCount: geometry.pageCount,
        password: _args.password,
      ),
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appText(context, '새 파일로 저장됨'))));
    Navigator.of(context).pushNamed(
      AppRoutes.viewer,
      arguments: ViewerArgs(
        pdfPath: ref.read(workspaceProvider)!.docPdf(result.id),
        title: result.title,
        pageCount: result.pageCount,
        docId: result.id,
      ),
    );
  }

  void _openCompressSheet() {
    showCompressSheet(
      context: context,
      ref: ref,
      pdfPath: _args.pdfPath,
      title: _args.title,
      docId: _args.docId,
      recentId: _args.recentId,
      onDocumentReady: _replaceWithCompressedDocument,
    );
  }

  /// §31 §4.3 확정: 압축 결과 시트가 뜨는 즉시(닫히기를 기다리지 않고) 호출된다.
  /// 새 화면을 쌓지 않고 같은 뷰어가 새 문서를 가리키도록 상태를 갈아 끼운다.
  void _replaceWithCompressedDocument(DocumentSummary newDocument) {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) return;

    final oldPath = _args.pdfPath;
    final oldPassword = _args.password;
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    _loadingPages.clear();

    // §T7: pdfPath가 바뀌면 검색 provider의 family 키가 자동으로 바뀌어 이전
    // 결과가 남지 않는다 — 여기서는 화면 로컬 모드/선택 상태만 정리한다.
    _searchMode = false;
    _selectionMode = false;
    _selectionPageIndex = null;
    _selectionPageText = null;
    _selectionRange = null;

    setState(() {
      _args = ViewerArgs(
        pdfPath: workspace.docPdf(newDocument.id),
        title: newDocument.title,
        pageCount: newDocument.pageCount,
        docId: newDocument.id,
      );
      _bytesCache.clear();
      _renderedWidthPx.clear();
      _loading = true;
      _geometry = null;
      _currentPage = 0;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    // 압축 전 문서의 렌더러 핸들을 닫는다 -- 새 문서는 _loadGeometry가 다시 연다.
    ref.read(pdfRendererProvider).evictDocument(oldPath, password: oldPassword);
    _loadGeometry();
  }

  // ---- 텍스트 선택·본문 검색 (2026-09-23 승인, `_workspace/83` B안) ----

  ViewerSearchKey? get _searchKey {
    final geometry = _geometry;
    if (geometry == null) return null;
    return ViewerSearchKey(_args.pdfPath, _args.password, geometry.pageCount);
  }

  void _toggleSearchMode() {
    if (_selectionMode) _toggleSelectionMode(force: false);
    setState(() => _searchMode = !_searchMode);
    if (!_searchMode) {
      final key = _searchKey;
      if (key != null) ref.read(viewerTextSearchProvider(key).notifier).reset();
    }
  }

  void _onSearchQueryChanged(String query) {
    final key = _searchKey;
    if (key == null) return;
    ref.read(viewerTextSearchProvider(key).notifier).search(query);
  }

  void _onSearchMatchSelected(ViewerSearchMatch match) {
    final index = _pageController.hasClients
        ? _pageController.page?.round()
        : _currentPage;
    if (index != match.pageIndex) {
      _pageController.jumpToPage(match.pageIndex);
    }
  }

  Future<void> _toggleSelectionMode({bool? force}) async {
    final next = force ?? !_selectionMode;
    if (next && _searchMode) {
      setState(() => _searchMode = false);
      final key = _searchKey;
      if (key != null) ref.read(viewerTextSearchProvider(key).notifier).reset();
    }
    setState(() {
      _selectionMode = next;
      _selectionRange = null;
    });
    if (next) {
      await _loadSelectionPageText(_currentPage);
    } else {
      _selectionPageText = null;
      _selectionPageIndex = null;
    }
  }

  Future<void> _loadSelectionPageText(int pageIndex) async {
    final renderer = ref.read(pdfRendererProvider);
    final result = await renderer.pageText(
      pdfPath: _args.pdfPath,
      pageIndex: pageIndex,
      password: _args.password,
    );
    if (!mounted || !_selectionMode) return;
    switch (result) {
      case PdfOk<PdfPageTextData>(:final value):
        setState(() {
          _selectionPageIndex = pageIndex;
          _selectionPageText = value;
          _selectionRange = null;
        });
        if (value.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appText(context, '이 페이지에는 선택할 수 있는 텍스트가 없습니다'))),
          );
        }
      case PdfErr<PdfPageTextData>():
        setState(() {
          _selectionPageIndex = pageIndex;
          _selectionPageText = null;
          _selectionRange = null;
        });
    }
  }

  void _onSelectionChanged(int? start, int? end) {
    setState(() {
      _selectionRange = (start != null && end != null) ? (start, end) : null;
    });
  }

  static const _clipChannel = MethodChannel('com.kamanbi.pdf_daeri/storage');

  Future<void> _copySelection() async {
    final range = _selectionRange;
    final text = _selectionPageText?.text;
    if (range == null || text == null) return;
    final s = range.$1.clamp(0, text.length);
    final e = range.$2.clamp(0, text.length);
    if (s >= e) return;
    final selected = text.substring(s, e);
    var copied = false;
    if (_args.isEncrypted) {
      // 암호 PDF: Android 13+ 클립보드 미리보기·히스토리에 노출되지 않게 민감 표시. 실패 시 폴백.
      try {
        copied = await _clipChannel.invokeMethod<bool>(
              'setSensitiveClip',
              {'text': selected},
            ) ??
            false;
      } catch (_) {
        copied = false;
      }
    }
    if (!copied) await Clipboard.setData(ClipboardData(text: selected));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appText(context, '복사됨'))));
  }

  void _selectAllOnPage() {
    _selectionOverlayKey.currentState?.selectAll();
  }

  /// [pageIndex]의 검색 하이라이트 사각형(일반/현재 매치 분리, pt 좌표).
  /// 스캔이 아직 이 페이지에 닿지 않았으면(텍스트 캐시 미적중) 빈 목록을
  /// 반환한다 — 순차 스캔이 진행되며 자연히 채워진다.
  (List<Rect>, List<Rect>) _searchHighlightsForPage(
    int pageIndex,
    ViewerSearchKey? searchKey,
  ) {
    if (!_searchMode || searchKey == null) return (const [], const []);
    final notifier = ref.read(viewerTextSearchProvider(searchKey).notifier);
    final pageText = notifier.textOf(pageIndex);
    if (pageText == null) return (const [], const []);
    final state = ref.read(viewerTextSearchProvider(searchKey));
    final normal = <Rect>[];
    final current = <Rect>[];
    for (var i = 0; i < state.matches.length; i++) {
      final match = state.matches[i];
      if (match.pageIndex != pageIndex) continue;
      final rects = pageText.rectsFor(match.start, match.end);
      if (i == state.currentIndex) {
        current.addAll(rects);
      } else {
        normal.addAll(rects);
      }
    }
    return (normal, current);
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    // 뷰어 이탈 — 이 문서의 핸들만 닫는다. evictCache()(전체 해제)는 쓰지 않는다
    // (§2.1 — 홈 그리드의 썸네일 생성용 핸들까지 닫으면 안 된다).
    _renderer.evictDocument(_args.pdfPath, password: _args.password);
    _pageController.dispose();
    super.dispose();
  }

  // 툴바 두 줄 높이(줄당 44px). 검색 바도 같은 높이를 써서 배너 위치가
  // 모드 전환 때 흔들리지 않는다.
  static const double _toolbarHeight = 88;

  /// 툴바 버튼을 절반씩 두 줄로 나눠 그린다. 줄마다 폭을 균등 분할하고,
  /// 라벨 글자 크기는 `_ToolbarButton` 안에서 전부 동일하게 고정한다.
  // 영어 툴바는 한 줄 고정 폭이라 짧은 라벨을 쓴다(제목용 긴 문구와 키 분리).
  static const _toolbarEnglish = {
    '서명 추가': 'Sign',
    '주석 추가': 'Annotate',
    '텍스트 인식': 'OCR',
  };

  String _toolbarLabel(String korean) =>
      Localizations.localeOf(context).languageCode == 'ko'
      ? korean
      : _toolbarEnglish[korean] ?? appText(context, korean);

  Widget _buildToolbarGrid(PdfPageGeometry? geometry) {
    final buttons = <_ToolbarButton>[
      // 본문 검색 — 읽기 전용이므로 암호 PDF에서도 활성.
      _ToolbarButton(
        onPressed: geometry == null ? null : _toggleSearchMode,
        label: appText(context, '검색'),
      ),
      // 텍스트 선택 — 토글. ON이면 라벨이 바뀌고 강조색.
      _ToolbarButton(
        onPressed: geometry == null ? null : () => _toggleSelectionMode(),
        label: _selectionMode ? appText(context, '선택 끝내기') : appText(context, '텍스트 선택'),
        emphasized: _selectionMode,
      ),
      // 편집 이동 — 암호 PDF는 편집 진입을 차단한다(1주차 Q10 확정 정책).
      // 비활성화가 아니라 버튼 자체를 없앤다(기존 동작 유지).
      if (!_args.isEncrypted) _ToolbarButton(onPressed: _openEdit, label: appText(context, '편집')),
      _ToolbarButton(
        onPressed: _args.isEncrypted ? null : _openCompressSheet,
        label: appText(context, '압축'),
      ),
      // 서명 추가 — 스탬프도 전체 재작성 저장이므로 암호 PDF에는 편집·압축과
      // 같은 정책을 적용한다.
      _ToolbarButton(
        onPressed: _args.isEncrypted ? null : _openSignature,
        label: _toolbarLabel('서명 추가'),
      ),
      // 주석 추가 — 서명과 같은 정책(암호 PDF 차단).
      _ToolbarButton(
        onPressed: _args.isEncrypted ? null : _openAnnotate,
        label: _toolbarLabel('주석 추가'),
      ),
      // 텍스트 인식 — 조건부로 숨기지 않는다. ImagePageRef 페이지가 없는
      // 문서(외부 PDF뿐)에서 눌러도 ocr_screen.dart 또는 `_openOcr`의 docId
      // 안내가 이유를 알려준다(§7.1).
      _ToolbarButton(
        onPressed: _args.isEncrypted ? null : _openOcr,
        label: _toolbarLabel('텍스트 인식'),
      ),
      _ToolbarButton(onPressed: _share, label: appText(context, '공유')),
    ];
    final split = (buttons.length / 2).ceil();
    return Column(
      children: [
        Expanded(child: Row(children: buttons.sublist(0, split))),
        Expanded(child: Row(children: buttons.sublist(split))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    final searchKey = _searchKey;

    // 검색 결과 페이지 이동 리스닝 — currentIndex가 바뀌면 그 매치의 페이지로
    // 이동한다(§4.3 데이터 흐름). geometry가 로드된 뒤에만 유효한 키가 있다.
    if (searchKey != null) {
      ref.listen(viewerTextSearchProvider(searchKey), (previous, next) {
        final idx = next.currentIndex;
        if (idx == null) return;
        if (previous?.currentIndex == idx &&
            previous?.matches == next.matches) {
          return;
        }
        if (idx < next.matches.length) {
          _onSearchMatchSelected(next.matches[idx]);
        }
      });
    }

    return PopScope(
      // 뒤로가기(시스템)는 검색 모드부터 닫는다(§4.4).
      canPop: !_searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchMode) _toggleSearchMode();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        appBar: AppBar(
          title: Text(_args.title, overflow: TextOverflow.ellipsis),
          // 사용자 피드백(2026-09-22) 반영 — Q12의 `⋮` 드롭다운 통합을 되돌린다.
          // "필요한 곳에서 필요한 기능이 눈에 보이게, 점세개 같은 건 절대 하지 마라."
          // 각 항목의 동작·활성화 조건은 그대로이며, 숨기지 않고 앱바 아래 두 번째
          // 줄에 텍스트 버튼으로 전부 노출한다.
          // 2026-09-23 피드백 — "한눈에 다 보였으면"(스크롤 제거) → "글자 크기는
          // 다 동일하게, 2줄로": 버튼을 2줄로 나눠 고정 폰트 크기로 표시한다(줄마다
          // 폭 균등 분할, 라벨별로 다르게 줄이지 않는다). 검색 모드도 같은 88px
          // 높이를 그대로 써서 배너 위치는 흔들리지 않는다.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(_toolbarHeight),
            child: _searchMode && searchKey != null
                ? SizedBox(
                    height: _toolbarHeight,
                    child: Center(
                      child: ViewerSearchBar(
                        state: ref.watch(viewerTextSearchProvider(searchKey)),
                        onQueryChanged: _onSearchQueryChanged,
                        onNext: () => ref
                            .read(viewerTextSearchProvider(searchKey).notifier)
                            .next(),
                        onPrev: () => ref
                            .read(viewerTextSearchProvider(searchKey).notifier)
                            .prev(),
                        onClose: _toggleSearchMode,
                      ),
                    ),
                  )
                : SizedBox(
                    height: _toolbarHeight,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: _buildToolbarGrid(geometry),
                    ),
                  ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (geometry == null || _fatalFailure != null)
            ? const SizedBox.shrink() // 실패 다이얼로그(_handleFatalFailure)가 처리한다
            : Column(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            // 선택 모드에서는 스와이프를 잠근다(§4.4 — 길게 누름·드래그가
                            // 페이지 전환 제스처와 경쟁하지 않도록 구조적으로 회피).
                            physics: _selectionMode
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            itemCount: geometry.pageCount,
                            onPageChanged: _onPageChanged,
                            itemBuilder: (context, index) {
                              final isCurrent = index == _currentPage;
                              final pageText = isCurrent
                                  ? _selectionPageText
                                  : null;
                              final (normalHi, currentHi) =
                                  _searchHighlightsForPage(index, searchKey);
                              return _ViewerPage(
                                key: ValueKey(index),
                                size: geometry.sizes[index],
                                bytes: _bytesCache[index],
                                onZoomSettled: (scale) =>
                                    _requestHighRes(index, scale),
                                panEnabled: !_selectionMode,
                                overlayKey: isCurrent
                                    ? _selectionOverlayKey
                                    : null,
                                selectionEnabled: _selectionMode && isCurrent,
                                pageText: isCurrent ? pageText : null,
                                searchHighlights: normalHi,
                                currentSearchHighlights: currentHi,
                                onSelectionChanged: isCurrent
                                    ? _onSelectionChanged
                                    : null,
                              );
                            },
                          ),
                          // 선택 결과 칩 — PageView 영역 안에만 배치(썸네일 바·배너
                          // 완충 밴드 침범 없음, §4.4 "배너와 최소 거리").
                          if (_selectionMode && _selectionRange != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 16,
                              child: Center(
                                child: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: _copySelection,
                                          child: Text(appText(context, '복사')),
                                        ),
                                        TextButton(
                                          onPressed: _selectAllOnPage,
                                          child: Text(appText(context, '전체 선택')),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PageThumbnailBar(
                    renderer: ref.read(pdfRendererProvider),
                    pdfPath: _args.pdfPath,
                    password: _args.password,
                    sizes: geometry.sizes,
                    currentPage: _currentPage,
                    onPageSelected: (index) => _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    ),
                  ),
                ],
              ),
        // W4-T6: §1 "뷰어 화면" 절 — 썸네일 바와 배너 사이 완충 밴드는
        // BannerHost 자신이 항상 그리므로(§1.3) 이 화면이 별도 패딩을 더하지
        // 않는다(§1.1 표 — S4는 스크롤 패딩 대상 아님).
        bottomNavigationBar: const BannerHost(slot: BannerSlot.viewer),
      ),
    );
  }
}

/// 페이지 1장 — 핀치 줌 + 고해상도 재렌더 요청. 페이지 전환으로 다시 만들어질
/// 때마다 줌 배율이 1.0으로 초기화된다(§2.2 — 좌우 스와이프와 팬 제스처 충돌 방지).
class _ViewerPage extends StatefulWidget {
  const _ViewerPage({
    super.key,
    required this.size,
    required this.bytes,
    required this.onZoomSettled,
    this.panEnabled = true,
    this.overlayKey,
    this.selectionEnabled = false,
    this.pageText,
    this.searchHighlights = const [],
    this.currentSearchHighlights = const [],
    this.onSelectionChanged,
  });

  final PdfPageSize size;
  final Uint8List? bytes;
  final ValueChanged<double> onZoomSettled;

  // 텍스트 선택·본문 검색(2026-09-23 승인, `_workspace/83` B안). 오버레이는
  // `InteractiveViewer`의 `child` 안쪽에 그려 줌 변환을 자동으로 공유한다(§4.5).
  final bool panEnabled;
  final GlobalKey<PageTextOverlayState>? overlayKey;
  final bool selectionEnabled;
  final PdfPageTextData? pageText;
  final List<Rect> searchHighlights;
  final List<Rect> currentSearchHighlights;
  final void Function(int? start, int? end)? onSelectionChanged;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _controller = TransformationController();
  Timer? _settleTimer;

  void _onInteractionEnd(ScaleEndDetails details) {
    _settleTimer?.cancel();
    _settleTimer = Timer(_zoomSettleDelay, () {
      final scale = _controller.value.getMaxScaleOnAxis();
      if (scale >= _highResScaleThreshold) {
        widget.onZoomSettled(scale);
      }
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: widget.size.aspectRatio,
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1.0,
              maxScale: 5.0,
              panEnabled: widget.panEnabled,
              onInteractionEnd: _onInteractionEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.bytes == null
                      ? ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Image.memory(widget.bytes!, gaplessPlayback: true),
                  if (widget.selectionEnabled ||
                      widget.searchHighlights.isNotEmpty ||
                      widget.currentSearchHighlights.isNotEmpty)
                    PageTextOverlay(
                      key: widget.overlayKey,
                      pageWidthPt: widget.size.widthPt,
                      pageText: widget.pageText,
                      selectionEnabled: widget.selectionEnabled,
                      searchHighlights: widget.searchHighlights,
                      currentSearchHighlights: widget.currentSearchHighlights,
                      onSelectionChanged:
                          widget.onSelectionChanged ?? (start, end) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 뷰어 상단 툴바 버튼 하나. `Expanded`로 감싸 부모 `Row`(한 줄 4개)가 폭을
/// 균등 분할하게 하고, 라벨 글자 크기는 모든 버튼이 동일한 고정값을 쓴다
/// (2026-09-23 피드백 — "글자 크기는 다 동일하게, 2줄로": 라벨 길이에 따라
/// 제각각 줄어들던 이전 `FittedBox` 방식을 버리고 2줄 균등 그리드로 바꾼다).
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.onPressed,
    required this.label,
    this.emphasized = false,
  });

  static const double _fontSize = 13;

  final VoidCallback? onPressed;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Expanded(
    child: TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: _fontSize,
          color: emphasized ? Theme.of(context).colorScheme.primary : null,
          fontWeight: emphasized ? FontWeight.bold : null,
        ),
      ),
    ),
  );
}
