/// 사진 → PDF. 스캔 폴백의 도착지이자 홈의 독립 진입점이다.
/// `file_picker`로 이미지를 선택해 `SaveImagesScreen`(→ `PdfEngine` 경유)으로 넘긴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../data/repository/document_repository.dart';
import 'save_images_flow.dart';

class PhotoToPdfScreen extends ConsumerStatefulWidget {
  const PhotoToPdfScreen({super.key});

  @override
  ConsumerState<PhotoToPdfScreen> createState() => _PhotoToPdfScreenState();
}

enum _PickState { idle, picking, failed }

class _PhotoToPdfScreenState extends ConsumerState<PhotoToPdfScreen> {
  _PickState _state = _PickState.idle;
  String? _errorMessage;

  Future<void> _pick() async {
    final photoSource = ref.read(photoSourceProvider);
    setState(() => _state = _PickState.picking);

    final result = await photoSource.pickImages();
    if (!mounted) return;

    switch (result) {
      case PdfOk<List<String>>():
        final images = result.value;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SaveImagesScreen(
              imagePaths: images,
              origin: DocOrigin.photo,
              suggestedTitle: _suggestedTitle(),
            ),
          ),
        );
      case PdfErr<List<String>>():
        final failure = result.failure;
        if (failure is Cancelled) {
          setState(() => _state = _PickState.idle);
          return;
        }
        setState(() {
          _state = _PickState.failed;
          _errorMessage = failure is UnknownFailure ? failure.message : '사진을 선택하지 못했습니다.';
        });
    }
  }

  String _suggestedTitle() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '사진 ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}${two(now.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사진 → PDF')),
      body: Center(
        child: switch (_state) {
          _PickState.idle => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 40),
                  const SizedBox(height: 12),
                  const Text('PDF로 만들 사진을 선택하세요.', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _pick, child: const Text('사진 선택')),
                ],
              ),
            ),
          _PickState.picking => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('사진을 선택하는 중…'),
              ],
            ),
          _PickState.failed => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(_errorMessage ?? '알 수 없는 오류', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _pick, child: const Text('다시 시도')),
                ],
              ),
            ),
        },
      ),
    );
  }
}
