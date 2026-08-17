/// S2 스캔. `screens.md` S2 그대로: ML Kit 문서 스캐너 플로우를 호출하고
/// **결과만 수신**한다. 자체 카메라·크롭·필터 UI는 만들지 않는다(절대 규칙 5).
///
/// Play 서비스 실패(`EngineUnsupported`)·`isAvailable() == false` 시 "사진 → PDF"로
/// 유도한다(작업 지시서 명시 요구사항). 이 화면에는 배너를 넣지 않는다(`ads.md`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../data/repository/document_repository.dart';
import 'photo_to_pdf_screen.dart';
import 'save_images_flow.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanState { checking, scanning, unsupported, failed }

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _ScanState _state = _ScanState.checking;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    final scanSource = ref.read(scanSourceProvider);

    setState(() => _state = _ScanState.checking);
    final available = await scanSource.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() => _state = _ScanState.unsupported);
      return;
    }

    setState(() => _state = _ScanState.scanning);
    final result = await scanSource.scan();
    if (!mounted) return;

    switch (result) {
      case PdfOk<List<String>>():
        final images = result.value;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SaveImagesScreen(
              imagePaths: images,
              origin: DocOrigin.scan,
              suggestedTitle: _suggestedTitle(),
            ),
          ),
        );
      case PdfErr<List<String>>():
        final failure = result.failure;
        if (failure is Cancelled) {
          // 사용자가 스캔 없이 뒤로 나감 — 정상 취소, 홈으로 복귀.
          Navigator.of(context).pop();
          return;
        }
        if (failure is EngineUnsupported) {
          setState(() => _state = _ScanState.unsupported);
          return;
        }
        setState(() {
          _state = _ScanState.failed;
          _errorMessage = _describeFailure(failure);
        });
    }
  }

  String _suggestedTitle() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '스캔 ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}${two(now.minute)}';
  }

  String _describeFailure(PdfFailure failure) => switch (failure) {
        SourceMissing() => '원본을 찾을 수 없습니다.',
        SourceCorrupted() => '스캔 결과를 읽을 수 없습니다.',
        SourceEncrypted() => '스캔 결과에 접근할 수 없습니다.',
        OutOfSpace() => '저장 공간이 부족합니다.',
        PermissionDenied() => '카메라 권한이 필요합니다.',
        Cancelled() => '취소되었습니다.',
        SizeGuardViolation() => '용량 검증에 실패했습니다.',
        EngineUnsupported() => '이 기기에서 스캔을 사용할 수 없습니다.',
        UnknownFailure(:final message) => '스캔 중 오류가 발생했습니다: $message',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스캔')),
      body: Center(
        child: switch (_state) {
          _ScanState.checking || _ScanState.scanning => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('스캐너를 여는 중…'),
              ],
            ),
          _ScanState.unsupported => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    '이 기기에서는 스캔 기능을 사용할 수 없습니다.\n대신 사진으로 PDF를 만들 수 있습니다.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('사진 → PDF로 계속하기'),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const PhotoToPdfScreen()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('홈으로'),
                  ),
                ],
              ),
            ),
          _ScanState.failed => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(_errorMessage ?? '알 수 없는 오류', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _startScan, child: const Text('다시 시도')),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('홈으로'),
                  ),
                ],
              ),
            ),
        },
      ),
    );
  }
}
