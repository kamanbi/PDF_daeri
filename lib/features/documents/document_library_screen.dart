/// 앱이 소유한 문서와 최근에 연 외부 PDF를 관리하는 단일 화면.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_locale.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../ads/banner_host.dart';
import '../../core/app_error.dart';
import '../../data/repository/document_repository.dart';
import '../common/share_flow.dart';

class DocumentLibraryScreen extends ConsumerStatefulWidget {
  const DocumentLibraryScreen({super.key});

  @override
  ConsumerState<DocumentLibraryScreen> createState() =>
      _DocumentLibraryScreenState();
}

class _DocumentLibraryScreenState extends ConsumerState<DocumentLibraryScreen> {
  final Set<String> _selectedDocumentIds = {};
  bool _selectionMode = false;

  // 제목 검색(설계 §4.1). 새 화면을 만들지 않고 이 화면의 앱바를 인라인
  // TextField로 바꾼다. 검색은 "내 문서" 섹션에만 적용하고, 검색 중에는
  // "최근 연 파일" 섹션을 숨긴다.
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  Stream<List<DocumentSummary>>? _searchStream;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _searching = true;
      _selectionMode = false;
      _selectedDocumentIds.clear();
      _searchStream = ref
          .read(documentRepositoryProvider)
          ?.watchDocuments(titleQuery: '');
    });
  }

  void _stopSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
      _searchStream = null;
    });
  }

  void _updateSearch(String value) {
    setState(() {
      _searchStream = ref
          .read(documentRepositoryProvider)
          ?.watchDocuments(titleQuery: value);
    });
  }

  void _toggleSelection(String documentId) {
    setState(() {
      if (!_selectedDocumentIds.add(documentId)) {
        _selectedDocumentIds.remove(documentId);
      }
      if (_selectedDocumentIds.isEmpty) _selectionMode = false;
    });
  }

  void _startSelection(String documentId) {
    setState(() {
      _selectionMode = true;
      _selectedDocumentIds.add(documentId);
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedDocumentIds.clear();
    });
  }

  void _toggleSelectAll(List<DocumentSummary> documents) {
    setState(() {
      if (_selectedDocumentIds.length == documents.length) {
        _selectedDocumentIds.clear();
      } else {
        _selectedDocumentIds
          ..clear()
          ..addAll(documents.map((document) => document.id));
      }
      _selectionMode = _selectedDocumentIds.isNotEmpty;
    });
  }

  Future<bool> _confirmDelete({required String message}) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(appText(context, '문서를 삭제할까요?')),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(appText(context, '취소')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(appText(context, '삭제')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteDocument(DocumentSummary document) async {
    if (!await _confirmDelete(
      message: appText(context, '‘{title}’ 문서와 앱 안의 원본이 삭제됩니다.').replaceAll('{title}', document.title),
    )) {
      return;
    }
    final repository = ref.read(documentRepositoryProvider);
    if (repository == null) return;
    final result = await repository.delete(document.id);
    if (!mounted) return;
    switch (result) {
      case PdfOk<void>():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appText(context, '문서를 삭제했습니다'))));
      case PdfErr<void>(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText(context, '삭제하지 못했습니다: {reason}').replaceAll('{reason}', _failureMessage(context, failure)))),
        );
    }
  }

  Future<void> _deleteSelected(List<DocumentSummary> documents) async {
    final selected = documents
        .where((document) => _selectedDocumentIds.contains(document.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    if (!await _confirmDelete(
      message: appCount(context, '{count}개 문서와 앱 안의 원본이 삭제됩니다.', selected.length),
    )) {
      return;
    }
    final repository = ref.read(documentRepositoryProvider);
    if (repository == null) return;
    var deletedCount = 0;
    for (final document in selected) {
      final result = await repository.delete(document.id);
      if (result is PdfOk<void>) deletedCount++;
    }
    if (!mounted) return;
    _cancelSelection();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appCount(context, '{count}개 문서를 삭제했습니다', deletedCount))));
  }

  Future<void> _shareSelected(List<DocumentSummary> documents) async {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) return;
    final selected = documents
        .where((document) => _selectedDocumentIds.contains(document.id))
        .map(
          (document) =>
              (pdfPath: workspace.docPdf(document.id), title: document.title),
        )
        .toList(growable: false);
    if (selected.isEmpty) return;
    await shareDocuments(context: context, ref: ref, documents: selected);
  }

  void _openDocument(DocumentSummary document) {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) return;
    Navigator.of(context).pushNamed(
      AppRoutes.viewer,
      arguments: ViewerArgs(
        pdfPath: workspace.docPdf(document.id),
        title: document.title,
        pageCount: document.pageCount,
        docId: document.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents =
        ref.watch(documentsStreamProvider).asData?.value ??
        const <DocumentSummary>[];

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: appText(context, '제목으로 검색'),
                  border: InputBorder.none,
                ),
                onChanged: _updateSearch,
              )
            : Text(
                _selectionMode ? appCount(context, '{count}개 선택', _selectedDocumentIds.length) : appText(context, '내 문서'),
              ),
        leading: _searching
            ? IconButton(
                onPressed: _stopSearch,
                icon: const Icon(Icons.arrow_back),
              )
            : _selectionMode
            ? TextButton(onPressed: _cancelSelection, child: Text(appText(context, '취소')))
            : null,
        actions: _searching
            ? const []
            : _selectionMode
            ? [
                TextButton(
                  onPressed: documents.isEmpty
                      ? null
                      : () => _toggleSelectAll(documents),
                  child: Text(
                    _selectedDocumentIds.length == documents.length
                        ? appText(context, '전체 해제')
                        : appText(context, '전체 선택'),
                  ),
                ),
                TextButton(
                  onPressed: () => _shareSelected(documents),
                  child: Text(appText(context, '공유')),
                ),
                TextButton(
                  onPressed: () => _deleteSelected(documents),
                  child: Text(appText(context, '삭제')),
                ),
              ]
            : [
                IconButton(
                  onPressed: _startSearch,
                  icon: const Icon(Icons.search),
                ),
                TextButton(
                  onPressed: documents.isEmpty
                      ? null
                      : () => _startSelection(documents.first.id),
                  child: Text(appText(context, '선택')),
                ),
              ],
      ),
      body: _searching
          ? _buildSearchResults()
          : _buildSections(documents),
      bottomNavigationBar: const BannerHost(slot: BannerSlot.documents),
    );
  }

  /// 검색 중(§4.1): 내 문서의 필터 결과만 보여준다. 결과 0건이면 빈 상태 일러스트 없이 한 줄 문구만 낸다.
  Widget _buildSearchResults() {
    final stream = _searchStream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<DocumentSummary>>(
      stream: stream,
      builder: (context, snapshot) {
        final results = snapshot.data ?? const <DocumentSummary>[];
        if (results.isEmpty) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 20),
            child: Text(appText(context, '검색 결과가 없습니다')),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final document in results)
              _DocumentRow(
                document: document,
                selected: false,
                selectionMode: false,
                onOpen: () => _openDocument(document),
                onSelect: () {},
                onShare: () {
                  final workspace = ref.read(workspaceProvider);
                  if (workspace == null) return;
                  shareDocument(
                    context: context,
                    ref: ref,
                    pdfPath: workspace.docPdf(document.id),
                    title: document.title,
                  );
                },
                onDelete: () => _deleteDocument(document),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSections(List<DocumentSummary> documents) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionTitle(
          title: appText(context, '내 문서'),
          description: appText(context, '앱에서 만든 문서입니다. 삭제하면 앱 안의 문서와 원본이 삭제됩니다.'),
        ),
        if (documents.isEmpty)
          _EmptyRow(appText(context, '저장된 문서가 없습니다.'))
        else
          for (final document in documents)
            _DocumentRow(
              document: document,
              selected: _selectedDocumentIds.contains(document.id),
              selectionMode: _selectionMode,
              onOpen: () => _openDocument(document),
              onSelect: () => _selectionMode
                  ? _toggleSelection(document.id)
                  : _startSelection(document.id),
              onShare: () {
                final workspace = ref.read(workspaceProvider);
                if (workspace == null) return;
                shareDocument(
                  context: context,
                  ref: ref,
                  pdfPath: workspace.docPdf(document.id),
                  title: document.title,
                );
              },
              onDelete: () => _deleteDocument(document),
            ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    child: Text(message),
  );
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onSelect,
    required this.onShare,
    required this.onDelete,
  });

  final DocumentSummary document;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onSelect;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectionMode)
                  Checkbox(value: selected, onChanged: (_) => onSelect()),
                Expanded(
                  child: Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: selectionMode ? 48 : 0),
              child: Text(
                appCount(context, '{count}쪽 · {size} · {date}', document.pageCount).replaceAll('{size}', _formatBytes(document.fileSize)).replaceAll('{date}', _formatDate(document.updatedAt)),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!selectionMode) const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: selectionMode
                  ? const []
                  : [
                      TextButton(onPressed: onOpen, child: Text(appText(context, '열기'))),
                      TextButton(onPressed: onShare, child: Text(appText(context, '공유'))),
                      TextButton(onPressed: onDelete, child: Text(appText(context, '삭제'))),
                    ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}.${twoDigits(value.month)}.${twoDigits(value.day)} ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String _failureMessage(BuildContext context, PdfFailure failure) => switch (failure) {
  SourceMissing() => appText(context, '파일을 찾을 수 없습니다.'),
  _ => appText(context, '문서를 처리할 수 없습니다.'),
};
