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

  @override
  void dispose() {
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

  void _showFailureDialog(PdfFailure failure) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장하지 못했습니다'),
        content: Text(_failureMessage(failure)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('확인')),
        ],
      ),
    );
  }
}

/// `GuardBlocked`를 포함해 모든 실패 사유를 화면에 그대로 노출한다 — 삼키지 않는다.
String _failureMessage(PdfFailure failure) => switch (failure) {
      SourceMissing(:final path) => '원본 파일을 찾을 수 없습니다: $path',
      SourceCorrupted(:final path) => '손상된 파일입니다: $path',
      SourceEncrypted(:final path) => '암호로 보호된 파일입니다: $path',
      OutOfSpace(:final requiredBytes) =>
        '저장 공간이 부족합니다 (필요한 여유 공간 약 ${_formatBytes(requiredBytes)})',
      PermissionDenied(:final detail) => '접근 권한이 거부되었습니다: $detail',
      Cancelled() => '저장을 취소했습니다',
      SizeGuardViolation(:final blocked) =>
        '용량 검증 게이트에 막혀 저장을 중단했습니다 '
            '(결과 ${_formatBytes(blocked.resultBytes)} > 허용 한도 ${_formatBytes(blocked.limitBytes)})',
      EngineUnsupported(:final capability) => '이 기기에서 지원하지 않는 기능입니다: $capability',
      UnknownFailure(:final message) => '저장 중 오류가 발생했습니다: $message',
    };

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
