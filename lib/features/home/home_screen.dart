/// S1 홈 — 1주차 최소 버전. `screens.md` S1의 **하단 3진입점만** 구현한다.
/// 문서 목록·최근 파일 그리드·정렬·`⋮` 메뉴는 2주차 이후 범위다(작업 지시서 참조).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../scan/photo_to_pdf_screen.dart';
import '../scan/scan_screen.dart';
import '../settings/settings_screen.dart';
import '../viewer/open_pdf_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(documentRepositoryProvider);
    final workspace = ref.watch(workspaceProvider);
    final issues = ref.watch(bootIssuesProvider);

    // 스캔/사진→PDF는 DocumentRepository가 있어야 저장할 수 있다.
    // PDF 열기(S2-b)는 Workspace만 있으면 된다(DB 기록 없이 복사·표시만).
    final canCreateDocuments = repository != null;
    final canOpenPdf = workspace != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF 대리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (issues.isNotEmpty)
            MaterialBanner(
              content: Text(issues.join('\n')),
              leading: const Icon(Icons.warning_amber_rounded),
              actions: [
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).clearMaterialBanners(),
                  child: const Text('확인'),
                ),
              ],
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('스캔'),
                      onPressed: canCreateDocuments
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ScanScreen()),
                              )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('PDF 열기'),
                      onPressed: canOpenPdf
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const OpenPdfScreen()),
                              )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('사진 → PDF'),
                      onPressed: canCreateDocuments
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const PhotoToPdfScreen()),
                              )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
