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

  // appBusyProvider(§4.4·26번 문서 §6 미해결 항목): 스캔 화면이 떠 있는 동안
  // 인텐트 소비가 가로채지 않도록 진입 시 true, 이탈 시 false로 되돌린다.
  // `SaveImagesScreen`/`PhotoToPdfScreen`으로 pushReplacement하는 경우는 그
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
    final result = await scanSource.scan();
    if (!mounted) return;

    switch (result) {
      case PdfOk<List<String>>():
        final images = result.value;
        _busyHandedOff = true;
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
                    onPressed: () {
                      _busyHandedOff = true;
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const PhotoToPdfScreen()),
                      );
                    },
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
