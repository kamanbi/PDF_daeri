/// S4 뷰어. 좌우 스와이프 · 핀치 줌 · 하단 썸네일 바. (설계 §2.0~§2.3, 2주차 신설)
///
/// `PdfRenderer.renderPage` 위에 `PageView` + `InteractiveViewer`로 직접 구현한다.
/// `pdfrx`의 `PdfViewer` 위젯은 쓰지 않는다(§2.2 — 두 번째 렌더 경로 금지).
/// 텍스트 선택·검색·주석 없음(`screens.md` S4, 영구 제외). 공유·편집 이동 버튼은
/// 3주차(설계 §0.4) — 이번 라운드는 상단 액션이 없다.
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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/pdf_renderer.dart';
import '../common/failure_ui.dart';
import 'compress_sheet.dart';
import 'page_thumbnail_bar.dart';

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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
      final result = await renderer.pageGeometry(_args.pdfPath, password: _args.password);
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
          final mapped = failure is SourceEncrypted ? SourceCorrupted(_args.pdfPath) : failure;
          setState(() {
            _loading = false;
            _fatalFailure = mapped;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _handleFatalFailure(mapped));
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
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _prefetchAround(index);
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
      if (_bytesCache.containsKey(index) || _loadingPages.contains(index)) continue;
      _renderPage(index, _basePxTarget());
    }
  }

  int _basePxTarget() {
    final width = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return math.min((width * dpr).round(), _basePxCap);
  }

  Future<void> _renderPage(int index, int targetWidthPx, {bool highRes = false}) async {
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
      ..sort((a, b) => (b - _currentPage).abs().compareTo((a - _currentPage).abs()));
    while (_bytesCache.length > _pageLruCapacity && indices.isNotEmpty) {
      final victim = indices.removeAt(0);
      if ((victim - _currentPage).abs() <= _preloadRadius) break; // 화면 근접 페이지는 지키지 않는다
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

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    // 뷰어 이탈 — 이 문서의 핸들만 닫는다. evictCache()(전체 해제)는 쓰지 않는다
    // (§2.1 — 홈 그리드의 썸네일 생성용 핸들까지 닫으면 안 된다).
    ref.read(pdfRendererProvider).evictDocument(_args.pdfPath, password: _args.password);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    return Scaffold(
      appBar: AppBar(
        title: Text(_args.title, overflow: TextOverflow.ellipsis),
        // §31 §4.2 신설: 압축 진입 아이콘 1개. 암호 PDF는 편집과 같은 정책으로
        // 비활성화한다(`ViewerArgs.isEncrypted`, §3.3 Q10). 공유·편집 이동은
        // 3주차(설계 §0.4)에 이 자리에 함께 붙는다 — 지금은 아이콘 1개뿐이다.
        actions: [
          IconButton(
            icon: const Icon(Icons.compress),
            tooltip: '압축',
            onPressed: _args.isEncrypted ? null : _openCompressSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (geometry == null || _fatalFailure != null)
          ? const SizedBox.shrink() // 실패 다이얼로그(_handleFatalFailure)가 처리한다
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: geometry.pageCount,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) => _ViewerPage(
                      key: ValueKey(index),
                      size: geometry.sizes[index],
                      bytes: _bytesCache[index],
                      onZoomSettled: (scale) => _requestHighRes(index, scale),
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
  });

  final PdfPageSize size;
  final Uint8List? bytes;
  final ValueChanged<double> onZoomSettled;

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
      child: AspectRatio(
        aspectRatio: widget.size.aspectRatio,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1.0,
          maxScale: 5.0,
          onInteractionEnd: _onInteractionEnd,
          child: widget.bytes == null
              ? const ColoredBox(
                  color: Color(0x11000000),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Image.memory(widget.bytes!, gaplessPlayback: true),
        ),
      ),
    );
  }
}
