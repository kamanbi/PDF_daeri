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

  // appBusyProvider(§4.4): 이 화면이 떠 있는 동안(스캔 폴백 진입이든 홈의 독립
  // 진입점이든) 인텐트 소비를 막는다. `SaveImagesScreen`으로 pushReplacement할
  // 때는 그 화면이 busy를 이어받으므로 dispose에서 false로 되돌리지 않는다
  // (scan_screen.dart와 동일한 handoff 패턴 — 전환 애니메이션 중 순서 역전 방지).
  late final StateController<bool> _busyNotifier;
  bool _busyHandedOff = false;

  @override
  void initState() {
    super.initState();
    _busyNotifier = ref.read(appBusyProvider.notifier);
    // Riverpod은 위젯 생명주기 중 프로바이더 상태 동기 수정을 금지한다 —
    // `Future(() {...})`로 미룬다(scan_screen.dart와 동일 이유). `mounted`
    // 가드는 미루는 동안 컨테이너가 먼저 dispose된 경우를 방어한다.
    Future.microtask(() {
      if (_busyNotifier.mounted) _busyNotifier.state = true;
    });
  }

  @override
  void dispose() {
    if (!_busyHandedOff) {
      final notifier = _busyNotifier;
      Future.microtask(() {
        if (notifier.mounted) notifier.state = false;
      });
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final photoSource = ref.read(photoSourceProvider);
    setState(() => _state = _PickState.picking);

    final result = await photoSource.pickImages();
    if (!mounted) return;

    switch (result) {
      case PdfOk<List<String>>():
        final images = result.value;
        _busyHandedOff = true;
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
