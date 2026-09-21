/// S1 홈 — 제품 소개와 빠른 시작만 제공한다.
///
/// 저장 문서의 열람·선택·공유·삭제는 `DocumentLibraryScreen`이 단일 소유한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/banner_host.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/platform_features.dart';
import '../../data/repository/draft_repository.dart';
import '../edit/edit_screen.dart' show resumeDraftProvider;

/// 앱 시작 시 1회 `DraftRepository.pending()`을 호출한다(§4.1·§4.8). 홈 화면을
/// 다시 열 때마다(뒤로가기 포함) 새로 조회해 카드가 최신 상태를 반영한다.
final pendingDraftProvider = FutureProvider.autoDispose<DraftSnapshot?>((ref) {
  final repo = ref.watch(draftRepositoryProvider);
  if (repo == null) return null;
  return repo.pending();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _exitDialogOpen = false;

  Future<void> _handleHomeBack(bool didPop, Object? _) async {
    if (didPop || _exitDialogOpen) return;

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
      if (shouldExit == true) await SystemNavigator.pop();
    } finally {
      if (mounted) _exitDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(documentRepositoryProvider);
    final workspace = ref.watch(workspaceProvider);
    final issues = ref.watch(bootIssuesProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleHomeBack,
      child: Scaffold(
        appBar: AppBar(
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
            const SliverToBoxAdapter(child: _DraftRecoveryCard()),
            const SliverToBoxAdapter(child: _HomeIntro()),
            SliverToBoxAdapter(
              child: _EntryPoints(
                canCreateDocuments: repository != null,
                canOpenPdf: workspace != null,
              ),
            ),
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

class _HomeIntro extends StatelessWidget {
  const _HomeIntro();

  static const double _imageAspectRatio = 4 / 3;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
          Text(
            'PDF 작업, 필요한 순간에 바로.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}

/// 스캔·PDF 열기·사진→PDF·내 문서의 빠른 진입점.
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppFeatures.scan) ...[
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
          ],
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.documents),
              child: const Text('내 문서'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 작업 중 상태 복구 카드(설계 §4.8). `DraftRepository.pending()`이 null이면
/// 렌더하지 않는다 — 배너처럼 높이를 선점하지 않는다(스크롤 콘텐츠 안의 일반
/// 위젯). 모달 다이얼로그를 쓰지 않는다(UX 원칙 "확인 창 금지").
class _DraftRecoveryCard extends ConsumerWidget {
  const _DraftRecoveryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(pendingDraftProvider).asData?.value;
    if (snapshot == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '편집하던 문서가 있습니다 — ${snapshot.title} · ${_formatDraftTime(snapshot.updatedAt)}',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _resume(context, ref, snapshot),
                    child: const Text('이어서 편집'),
                  ),
                  TextButton(
                    onPressed: () => _delete(ref, snapshot),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resume(
    BuildContext context,
    WidgetRef ref,
    DraftSnapshot snapshot,
  ) async {
    final source = switch (snapshot.source) {
      MyDocumentEditSource(:final docId) => EditSource.myDocument(docId),
      ExternalPdfEditSource(:final pdfPath, :final title, :final recentId) =>
        EditSource.externalPdf(pdfPath: pdfPath, title: title, recentId: recentId),
    };
    ref.read(resumeDraftProvider.notifier).state = snapshot;
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.edit,
      arguments: EditArgs(source: source, title: snapshot.title),
    );
  }

  Future<void> _delete(WidgetRef ref, DraftSnapshot snapshot) async {
    await ref.read(draftRepositoryProvider)?.discard(snapshot.draftId);
    ref.invalidate(pendingDraftProvider);
  }
}

String _formatDraftTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.month}.${twoDigits(value.day)} ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
