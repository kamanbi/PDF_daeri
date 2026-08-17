/// S2-b PDF 열기 — 1주차 최소 버전. `SafImport`로 앱 작업공간(`recent/`)에 복사하고
/// 결과(표시명·페이지 수)만 보여준다. **뷰어는 2주차**(`screens.md` S2-b, S4).
///
/// 암호 PDF는 비밀번호를 물어 페이지 수까지 확인하되 **보기·공유만 허용**한다(사용자
/// 확정 Q10) — 이 화면에서 편집·합치기로 이어지는 진입점을 만들지 않는다.
/// 손상 파일은 앱이 죽지 않고 "열 수 없는 파일" 안내로 끝난다.
///
/// **설계 질의(노트 참조)**: 홈의 "PDF 열기" 버튼(외부 인텐트가 아니라 앱 안에서
/// 사용자가 직접 SAF 피커를 여는 경로)에 대해 `SafImporter`는 `content://` URI를
/// 이미 들고 있는 경우의 복사(`importToPath`)만 제공하고, 피커 자체를 여는 메서드가
/// 없다. `file_picker`(기존 의존성)로 피커를 열고 반환된 로컬 경로를 이 화면에서
/// 직접 복사한다 — `RecentRepository`(2주차 예정)가 아직 없어 이 책임을 넘길 곳이
/// 없기 때문이다. 외부 인텐트로 들어오는 경로(`takeInitialUri`/`onNewIntentUri`)는
/// `SafImporter.importToPath`를 그대로 쓴다.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../pdf/pdf_engine.dart';

class OpenPdfScreen extends ConsumerStatefulWidget {
  const OpenPdfScreen({super.key});

  @override
  ConsumerState<OpenPdfScreen> createState() => _OpenPdfScreenState();
}

enum _Step { idle, picking, inspecting, needsPassword, corrupted, error, result }

class _OpenPdfScreenState extends ConsumerState<OpenPdfScreen> {
  static const _uuid = Uuid();

  _Step _step = _Step.idle;
  String? _errorMessage;
  String? _copiedPath;
  String? _displayName;
  PdfDocInfo? _info;
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickAndCopy() async {
    setState(() => _step = _Step.picking);

    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = '파일 선택기를 열지 못했습니다: $e';
      });
      return;
    }
    if (files.isEmpty) {
      setState(() => _step = _Step.idle);
      return;
    }

    final picked = files.first;
    final sourcePath = picked.path;
    if (sourcePath == null) {
      setState(() {
        _step = _Step.error;
        _errorMessage = '선택한 파일의 경로를 확인할 수 없습니다.';
      });
      return;
    }

    final workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      setState(() {
        _step = _Step.error;
        _errorMessage = '작업공간을 사용할 수 없습니다. 앱을 다시 시작해 주세요.';
      });
      return;
    }

    final destPath = workspace.recentFile(_uuid.v4());
    try {
      await Directory(destPath).parent.create(recursive: true);
      await File(sourcePath).copy(destPath);
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = '파일을 복사하지 못했습니다: $e';
      });
      return;
    }

    _copiedPath = destPath;
    _displayName = picked.name;
    await _inspect(destPath);
  }

  Future<void> _inspect(String path, {String? password}) async {
    setState(() => _step = _Step.inspecting);
    final engine = ref.read(pdfEngineProvider);
    if (engine == null) {
      setState(() {
        _step = _Step.error;
        _errorMessage = 'PDF 엔진을 사용할 수 없습니다. 앱을 다시 시작해 주세요.';
      });
      return;
    }

    final result = await engine.inspect(path, password: password);
    if (!mounted) return;

    switch (result) {
      case PdfOk<PdfDocInfo>():
        setState(() {
          _info = result.value;
          _step = _Step.result;
        });
      case PdfErr<PdfDocInfo>():
        final failure = result.failure;
        if (failure is SourceEncrypted) {
          setState(() => _step = _Step.needsPassword);
        } else if (failure is SourceCorrupted) {
          setState(() => _step = _Step.corrupted);
        } else {
          setState(() {
            _step = _Step.error;
            _errorMessage = _describeFailure(failure);
          });
        }
    }
  }

  String _describeFailure(PdfFailure failure) => switch (failure) {
        SourceMissing() => '파일을 찾을 수 없습니다.',
        SourceCorrupted() => '손상된 파일이라 열 수 없습니다.',
        SourceEncrypted() => '암호로 보호된 파일입니다.',
        OutOfSpace() => '저장 공간이 부족합니다.',
        PermissionDenied() => '파일에 접근할 권한이 없습니다.',
        Cancelled() => '취소되었습니다.',
        SizeGuardViolation() => '용량 검증에 실패했습니다.',
        EngineUnsupported() => '이 파일 형식은 지원하지 않습니다.',
        UnknownFailure(:final message) => '열 수 없는 파일입니다: $message',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF 열기')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_step) {
      case _Step.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('열 PDF 파일을 선택하세요.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: _pickAndCopy, child: const Text('파일 선택')),
          ],
        );
      case _Step.picking:
      case _Step.inspecting:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('확인하는 중…')],
        );
      case _Step.needsPassword:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 12),
            Text('"${_displayName ?? ''}" 파일은 암호로 보호되어 있습니다.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final path = _copiedPath;
                if (path == null) return;
                _inspect(path, password: _passwordController.text);
              },
              child: const Text('확인'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
          ],
        );
      case _Step.corrupted:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('"${_displayName ?? ''}"은(는) 열 수 없는 파일입니다.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('홈으로')),
          ],
        );
      case _Step.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage ?? '알 수 없는 오류', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: _pickAndCopy, child: const Text('다시 시도')),
          ],
        );
      case _Step.result:
        final info = _info!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 40),
            const SizedBox(height: 12),
            Text(_displayName ?? '(이름 없음)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${info.pageCount}쪽 · ${_formatBytes(info.bytes)}'),
            if (info.isEncrypted) ...[
              const SizedBox(height: 8),
              const Text('암호로 보호된 문서입니다. 보기·공유만 가능합니다.', textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('홈으로')),
          ],
        );
    }
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
