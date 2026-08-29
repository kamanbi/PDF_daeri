/// S1 홈 — 제품 소개, 빠른 시작, 최근 연 파일, 내 문서를 한 화면에 둔다.
/// (설계 §1.0~§1.5)
///
/// **두 섹션을 한 그리드에 섞지 않는다.** 섹션 1은 `RecentRepository.watchRecent()`
/// (`opened_at DESC`), 섹션 2는 `DocumentRepository.watchDocuments()`
/// (`updated_at DESC`)를 각각 독립 스트림으로 구독한다 — 새 조회 경로를 만들지
/// 않는다(§1.1·§1.3). 정렬 옵션은 만들지 않는다(v1 확정).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../ads/banner_host.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../data/repository/document_repository.dart';
import '../../data/repository/recent_repository.dart';
import '../common/share_flow.dart';
import '../viewer/open_pdf_flow.dart';
import 'merge_documents_flow.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// 다중 선택 상태. **"내 문서" 섹션에만 적용된다** — "최근 연 파일"은 `documents` 행이
/// 없어 합치기·삭제 대상이 아니다(설계 §3.1, 2주차 §163). 두 섹션을 한 선택 집합에
/// 섞지 않는다.
///
/// [2026-08-25 · 3주차 T5-1 · platform-integration] 여기서는 선택 상태 관리와 합치기
/// 실행 배선(`mergeDocumentsAndCreate` 호출)만 담당한다. 체크박스·액션바 비주얼은
/// 최소 형태로만 두었다 — **flutter-ui 확인 필요**: 최종 UI(카드 위 체크마크 오버레이
/// 스타일, `⋮` 메뉴의 나누기/압축/공유/삭제/이름변경 5항목 배선, "최근 연 파일" 삭제와의
/// 시각적 구분)는 담당 U가 T4 이후 라운드에서 다듬는다.
class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _selectionMode = false;
  bool _exitDialogOpen = false;
  final Set<String> _selectedIds = {};

  void _toggleSelection(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  void _enterSelectionMode(String docId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(docId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _mergeSelected(List<DocumentSummary> documents) async {
    // 화면에 보이는 순서(= updated_at DESC) 그대로 유지한다 — 선택 순서를 기억하지
    // 않는다(설계 §3.1 "합치기 순서" 확정 사항).
    final selected = documents
        .where((d) => _selectedIds.contains(d.id))
        .toList();
    if (selected.length < 2) return;
    final result = await mergeDocumentsAndCreate(
      context: context,
      ref: ref,
      selected: selected,
    );
    if (result != null && mounted) _exitSelectionMode();
  }

  Future<void> _handleHomeBack(bool didPop, Object? _) async {
    if (didPop) return;
    if (_selectionMode) {
      _exitSelectionMode();
      return;
    }
    if (_exitDialogOpen) return;

    _exitDialogOpen = true;
    try {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('앱을 종료할까요?'),
          content: const Text('진행 중인 작업이 없으면 앱을 종료합니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('종료'),
            ),
          ],
        ),
      );
      if (shouldExit == true) {
        await SystemNavigator.pop();
      }
    } finally {
      if (mounted) _exitDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(documentRepositoryProvider);
    final workspace = ref.watch(workspaceProvider);
    final issues = ref.watch(bootIssuesProvider);
    final recentAsync = ref.watch(recentFilesStreamProvider);
    final docsAsync = ref.watch(documentsStreamProvider);

    // 스캔/사진→PDF는 DocumentRepository가 있어야 저장할 수 있다.
    // PDF 열기(S2-b)는 Workspace만 있으면 된다(RecentRepository가 복사·표시).
    final canCreateDocuments = repository != null;
    final canOpenPdf = workspace != null;

    final recentFiles = recentAsync.asData?.value ?? const <RecentFile>[];
    final documents = docsAsync.asData?.value ?? const <DocumentSummary>[];
    final isEmpty = recentFiles.isEmpty && documents.isEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleHomeBack,
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: TextButton(
                  onPressed: _exitSelectionMode,
                  child: const Text('취소'),
                ),
                title: Text('${_selectedIds.length}개 선택'),
                actions: [
                  TextButton(
                    onPressed: _selectedIds.length >= 2
                        ? () => _mergeSelected(documents)
                        : null,
                    child: const Text('합치기'),
                  ),
                ],
              )
            : AppBar(
                title: const Text('PDF 대리'),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(AppRoutes.settings),
                    child: const Text('설정'),
                  ),
                ],
              ),
        body: CustomScrollView(
          slivers: [
            if (issues.isNotEmpty)
              SliverToBoxAdapter(
                child: MaterialBanner(
                  content: Text(issues.join('\n')),
                  leading: const Icon(Icons.warning_amber_rounded),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).clearMaterialBanners(),
                      child: const Text('확인'),
                    ),
                  ],
                ),
              ),
            const SliverToBoxAdapter(child: _HomeIntro()),
            SliverToBoxAdapter(
              child: _EntryPoints(
                canCreateDocuments: canCreateDocuments,
                canOpenPdf: canOpenPdf,
              ),
            ),
            if (isEmpty)
              const SliverToBoxAdapter(child: _EmptyDocumentsNotice())
            else ...[
              if (recentFiles.isNotEmpty) ...[
                const _SectionHeader('최근 연 파일'),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _RecentFileTile(file: recentFiles[index]),
                    childCount: recentFiles.length,
                  ),
                ),
              ],
              if (documents.isNotEmpty) ...[
                const _SectionHeader('내 문서'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _DocumentCard(
                        summary: documents[index],
                        selectionMode: _selectionMode,
                        selected: _selectedIds.contains(documents[index].id),
                        onLongPress: () =>
                            _enterSelectionMode(documents[index].id),
                        onToggleSelected: () =>
                            _toggleSelection(documents[index].id),
                      ),
                      childCount: documents.length,
                    ),
                  ),
                ),
              ],
            ],
            // W4-T6: 배너 완충 밴드(§1.3) — BannerHost.contentBottomPadding이
            // 광고 제거 구매 시 0을 돌려주므로 여기 분기가 생기지 않는다.
            SliverToBoxAdapter(
              child: SizedBox(height: BannerHost.contentBottomPadding(ref)),
            ),
          ],
        ),
        bottomNavigationBar: const BannerHost(slot: BannerSlot.home),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _HomeIntro extends StatelessWidget {
  const _HomeIntro();

  static const double _imageAspectRatio = 4 / 3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: _imageAspectRatio,
              child: Image.asset(
                'assets/images/home_document_workspace.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('PDF 작업, 필요한 순간에 바로.', style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '서류를 스캔하고, 받은 PDF를 열고, 사진을 하나의 문서로 정리하세요.',
            style: textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _EmptyDocumentsNotice extends StatelessWidget {
  const _EmptyDocumentsNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Text('저장된 문서가 아직 없습니다.'),
    );
  }
}

/// 하단 3진입점(스캔·PDF 열기·사진→PDF). 1주차부터 유지, 스크롤 콘텐츠 하단에
/// 둔다(고정 하단 바가 아니다, §1.0).
class _EntryPoints extends StatelessWidget {
  const _EntryPoints({
    required this.canCreateDocuments,
    required this.canOpenPdf,
  });
  final bool canCreateDocuments;
  final bool canOpenPdf;

  static const double _buttonHeight = 52;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: FilledButton(
              onPressed: canCreateDocuments
                  ? () => Navigator.of(context).pushNamed(AppRoutes.scan)
                  : null,
              child: const Text('스캔'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: OutlinedButton(
              onPressed: canOpenPdf
                  ? () => Navigator.of(context).pushNamed(AppRoutes.openPdf)
                  : null,
              child: const Text('PDF 열기'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: OutlinedButton(
              onPressed: canCreateDocuments
                  ? () => Navigator.of(context).pushNamed(AppRoutes.photoToPdf)
                  : null,
              child: const Text('사진 → PDF'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentFileTile extends ConsumerWidget {
  const _RecentFileTile({required this.file});
  final RecentFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.picture_as_pdf_outlined,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(
            file.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_formatBytes(file.size)} · ${_formatOpenedAt(file.openedAt)}',
          ),
          trailing: TextButton(
            onPressed: () async {
              final repo = ref.read(recentRepositoryProvider);
              await repo?.removeFromList(file.id);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('목록에서 제거했습니다')));
              }
            },
            child: const Text('제거'),
          ),
          onTap: () => openPdfAndGoToViewer(
            context: context,
            ref: ref,
            source: ExistingRecentSource(file),
          ),
        ),
      ),
    );
  }
}

enum _DocumentCardAction { share }

class _DocumentCard extends ConsumerWidget {
  const _DocumentCard({
    required this.summary,
    required this.selectionMode,
    required this.selected,
    required this.onLongPress,
    required this.onToggleSelected,
  });
  final DocumentSummary summary;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onLongPress: selectionMode ? null : onLongPress,
      onTap: () {
        if (selectionMode) {
          onToggleSelected();
          return;
        }
        final workspace = ref.read(workspaceProvider);
        if (workspace == null) return;
        Navigator.of(context).pushNamed(
          AppRoutes.viewer,
          arguments: ViewerArgs(
            pdfPath: workspace.docPdf(summary.id),
            title: summary.title,
            pageCount: summary.pageCount,
            docId: summary.id,
          ),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _DocumentThumbnail(summary: summary)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary.pageCount}p · ${_formatBytes(summary.fileSize)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _formatDate(summary.updatedAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (selectionMode)
              Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surface,
                ),
              )
            else
              // [W4-T1] `shareExportProvider` 배선(설계 §2.6·§11 W4-T1). 항목은
              // "공유" 1개뿐이다 — 나누기/삭제/이름변경은 스펙 밖 선제 추가라
              // 이번 라운드에 넣지 않는다(다음 라운드 flutter-ui가 확장).
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<_DocumentCardAction>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: '더보기',
                  onSelected: (action) {
                    switch (action) {
                      case _DocumentCardAction.share:
                        final workspace = ref.read(workspaceProvider);
                        if (workspace == null) return;
                        shareDocument(
                          context: context,
                          ref: ref,
                          pdfPath: workspace.docPdf(summary.id),
                          title: summary.title,
                        );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _DocumentCardAction.share,
                      child: Text('공유'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 목록 썸네일 — 지연 로딩(설계 §1.1·§1.4). 셀이 빌드될 때(=뷰포트에 들어올 때)
/// `summary.thumbPath`가 없으면 `DocumentRepository.ensureThumbnail(docId)`를 1회
/// 호출한다. 완료되면 `watchDocuments()` 스트림이 갱신된 `thumbPath`를 밀어 넣어
/// `_DocumentCard`가 새 `summary`로 다시 빌드되므로, 이 위젯은 성공 결과를 직접
/// 들고 있지 않는다 — 실패(`PdfOk(null)`, 손상·암호)에서만 "같은 세션 재시도 안 함"을
/// 이 위젯 스스로 기억한다(Repository도 내부적으로 억제하지만, 스크롤로 이 위젯이
/// 재생성되며 중복 호출하는 것까지 막기 위한 2차 방어).
class _DocumentThumbnail extends ConsumerStatefulWidget {
  const _DocumentThumbnail({required this.summary});
  final DocumentSummary summary;

  @override
  ConsumerState<_DocumentThumbnail> createState() => _DocumentThumbnailState();
}

class _DocumentThumbnailState extends ConsumerState<_DocumentThumbnail> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _maybeRequest();
  }

  @override
  void didUpdateWidget(covariant _DocumentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.id != widget.summary.id) _requested = false;
    _maybeRequest();
  }

  void _maybeRequest() {
    if (_requested) return;
    if (widget.summary.thumbPath != null) return;
    final repo = ref.read(documentRepositoryProvider);
    if (repo == null) return;
    _requested = true;
    // 결과는 무시한다 — 성공 시 watchDocuments() 스트림이 새 thumbPath를 밀어
    // 넣어 이 위젯이 자연히 다시 빌드된다. 실패(PdfOk(null))는 자리표시자 유지.
    unawaited(repo.ensureThumbnail(widget.summary.id));
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.summary.thumbPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover, width: double.infinity);
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.picture_as_pdf_outlined, size: 32)),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatOpenedAt(DateTime dt) => _formatDate(dt);

String _formatDate(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}.${p2(dt.month)}.${p2(dt.day)} ${p2(dt.hour)}:${p2(dt.minute)}';
}
