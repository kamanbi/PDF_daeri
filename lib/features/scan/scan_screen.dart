/// S2 스캔. Google Play 서비스 문서 스캐너가 보정한 결과를 받고, 기존 사진
/// 편집·PDF 생성 흐름으로 넘긴다. 이 화면에는 배너를 넣지 않는다(`ads.md`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import 'photo_to_pdf_screen.dart';
import 'single_scan_save_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanState { checking, scanning, unsupported, failed }

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _ScanState _state = _ScanState.checking;
  String? _errorMessage;

  // appBusyProvider(§4.4·26번 문서 §6 미해결 항목): 스캔 화면이 떠 있는 동안
  // 인텐트 소비가 가로채지 않도록 진입 시 true, 이탈 시 false로 되돌린다.
  // `PhotoEditScreen`/`PhotoToPdfScreen`으로 pushReplacement하는 경우는 그
  // 다음 화면이 busy를 이어받으므로(각 화면도 자신의 initState에서 true를
  // 세팅한다) 여기서 false로 되돌리지 않는다 — `_busyHandedOff`로 표시한다.
  // (pushReplacement 전환 애니메이션 중 새 화면이 이미 true를 세팅한 뒤에
  // 이 화면의 dispose가 뒤늦게 호출되어 잘못 false로 되돌리는 것을 막는다.)
  late final StateController<bool> _busyNotifier;
  bool _busyHandedOff = false;

  @override
  void initState() {
    super.initState();
    _busyNotifier = ref.read(appBusyProvider.notifier);
    // Riverpod은 위젯 생명주기(빌드·initState·dispose 등) 중 프로바이더 상태
    // 동기 수정을 금지한다("Tried to modify a provider while the widget tree
    // was building") — Riverpod이 권고하는 대로 `Future(() {...})`로 미룬다.
    // `mounted`(StateController가 노출하는 것, 위젯의 mounted가 아니다) 가드는
    // 미루는 동안 컨테이너가 먼저 dispose된 경우(위젯 테스트 종료 등)를 방어한다.
    Future.microtask(() {
      if (_busyNotifier.mounted) _busyNotifier.state = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
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
    final result = await scanSource.scan(context);
    if (!mounted) return;

    switch (result) {
      case PdfOk<List<String>>():
        _openSingleScanSave(result.value.single);
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

  String _suggestedTitle(String prefix) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '$prefix ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}${two(now.minute)}';
  }

  void _openSingleScanSave(String imagePath) {
    _busyHandedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SingleScanSaveScreen(
          imagePath: imagePath,
          suggestedTitle: _suggestedTitle('스캔'),
        ),
      ),
    );
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
    ScannerUnavailable(:final message) => message,
    UnknownFailure(:final message) => '스캔 중 오류가 발생했습니다: $message',
  };

  void _continueWithPhotos() {
    _busyHandedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PhotoToPdfScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스캔')),
      body: Center(
        child: switch (_state) {
          _ScanState.checking || _ScanState.scanning => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('스캐너를 여는 중…'),
            ],
          ),
          _ScanState.unsupported => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '이 기기에서 문서 스캐너를 사용할 수 없습니다.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _continueWithPhotos,
                  child: const Text('사진 → PDF로 계속하기'),
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
                Text(_errorMessage ?? '알 수 없는 오류', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: _startScan, child: const Text('다시 시도')),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _continueWithPhotos,
                  child: const Text('사진 → PDF로 계속하기'),
                ),
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
