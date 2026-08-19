/// 스캔(S2)·사진→PDF 공통 저장 흐름. 이미지 목록을 받아 제목을 입력받고
/// `PdfEngine`을 경유하는 `DocumentRepository.createDocument`로 PDF를 만든다.
///
/// **설계 질의(노트 참조)**: `SizeGuard`의 `SaveOp` 4종(삭제/순서·회전/나누기/합치기)은
/// 전부 "이미 존재하는 원본 문서"를 전제한다. 스캔·사진처럼 원본 PDF 없이 이미지만으로
/// 신규 문서를 만드는 경우를 위한 op가 설계서(§4.2)에 없다. `compose`는 "혼합 문서(외부
/// PDF + 스캔 페이지 추가)" 전용이며 §14 Q6 승인 전까지 사용 금지라 이 경우에도 맞지
/// 않는다. 임시로 `SaveOp.merge` 의미("원본들의 합계 바이트 대비 1.05배")를 그대로
/// 가져와 `baselineBytes = 선택한 이미지 파일 크기 합계`로 적용한다 — merge의 정의와
/// 구조적으로 가장 가깝고(여러 원본을 하나로 합친다는 점), 게이트를 느슨하게 풀거나
/// 우회하지 않는 유일한 기존 옵션이기 때문이다. 아키텍트 확인이 오면 즉시 교체한다.
library;

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/cancel_token.dart';
import '../../core/progress.dart';
import '../../core/size_guard.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/page_ref.dart';
import '../../pdf/pdf_engine.dart';
import '../common/failure_ui.dart';

class SaveImagesScreen extends ConsumerStatefulWidget {
  const SaveImagesScreen({
    super.key,
    required this.imagePaths,
    required this.origin,
    required this.suggestedTitle,
  });

  final List<String> imagePaths;
  final DocOrigin origin;
  final String suggestedTitle;

  @override
  ConsumerState<SaveImagesScreen> createState() => _SaveImagesScreenState();
}

class _SaveImagesScreenState extends ConsumerState<SaveImagesScreen> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.suggestedTitle);

  bool _saving = false;
  PdfProgress? _progress;
  CancelToken? _cancelToken;

  // appBusyProvider(§4.4): 스캔·사진 선택 화면에서 이어받은 busy 신호를 이
  // 화면이 마지막으로 들고 있다가(제목 입력 + 실제 저장 구간 전부) 화면을
  // 벗어날 때 false로 되돌린다. 이 화면은 더 이상 다른 화면으로 handoff하지
  // 않는다(성공 시 popUntil(isFirst)로 홈까지 되돌아간다) — 항상 dispose에서
  // 되돌리면 된다.
  late final StateController<bool> _busyNotifier;

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
    final notifier = _busyNotifier;
    Future.microtask(() {
      if (notifier.mounted) notifier.state = false;
    });
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 저장 액션은 상단 앱바에 둔다(배너 오터치 방지 배치 원칙 — 이 화면엔 배너가
      // 없지만 규칙을 앱 전체에서 일관되게 유지한다).
      appBar: AppBar(
        title: Text('${widget.imagePaths.length}장 저장'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '저장',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('${widget.imagePaths.length}장의 이미지로 PDF를 만듭니다.'),
            const SizedBox(height: 24),
            if (_saving) ...[
              LinearProgressIndicator(value: _progress?.fraction),
              const SizedBox(height: 8),
              Text(_progress == null ? '준비 중…' : '저장 중… ${_progress!.done}/${_progress!.total}'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _cancelToken?.cancel(),
                child: const Text('취소'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final repository = ref.read(documentRepositoryProvider);
    if (repository == null) {
      _showError('문서 저장소를 사용할 수 없습니다. 앱을 다시 시작해 주세요.');
      return;
    }

    final title = _titleController.text.trim().isEmpty
        ? widget.suggestedTitle
        : _titleController.text.trim();

    final pages = widget.imagePaths
        .map((path) => ImagePageRef(imagePath: path, rotation: 0))
        .toList(growable: false);

    int baselineBytes;
    try {
      baselineBytes = 0;
      for (final path in widget.imagePaths) {
        baselineBytes += await File(path).length();
      }
    } catch (e) {
      _showError('이미지 파일을 읽을 수 없습니다: $e');
      return;
    }

    final cancelToken = CancelToken();
    setState(() {
      _saving = true;
      _progress = null;
      _cancelToken = cancelToken;
    });

    final result = await repository.createDocument(
      title: title,
      origin: widget.origin,
      pages: pages,
      quality: ImageQuality.standard, // 화질 선택 UI는 S3(3주차) 범위. 1주차는 기본값 고정.
      guardInput: GuardInput(op: SaveOp.merge, baselineBytes: baselineBytes),
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      cancelToken: cancelToken,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case PdfOk<DocumentSummary>():
        final summary = result.value;
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '새 파일로 저장됨 — "${summary.title}" (${summary.pageCount}쪽)',
            ),
          ),
        );
      case PdfErr<DocumentSummary>():
        final failure = result.failure;
        developer.log('이미지→PDF 저장 실패', name: 'SaveImagesFlow', error: failure);
        if (failure is Cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장을 취소했습니다')));
        } else {
          _showFailureDialog(failure);
        }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // 실패 매핑의 유일한 소유자는 FailureUi다(2주차 확정 패턴 · 설계 §6.3).
  // 여기서 두 번째 매핑을 만들지 않는다. UnknownFailure의 원본 예외 메시지는
  // FailureUi 내부에서 developer.log로만 남고 화면에는 노출되지 않는다.
  void _showFailureDialog(PdfFailure failure) {
    FailureUi.showDialog(context, failure);
  }
}
