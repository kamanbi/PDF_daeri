/// S2-b PDF 열기 — 2주차: `file_picker`로 로컬 파일을 고른 뒤 그 결과 하나만
/// `openPdfAndGoToViewer`(`open_pdf_flow.dart`)에 위임한다. (설계 §3.2·§6.2)
///
/// 임포트·검사·실패 처리·뷰어 이동은 전부 `open_pdf_flow.dart`가 소유한다 —
/// 이 화면은 "피커를 연다"는 책임 하나만 남는다. 1주차의 로컬 `_describeFailure`는
/// `FailureUi`(단일 소유)로 승격되며 이 파일에서는 제거됐다.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_pdf_flow.dart';

class OpenPdfScreen extends ConsumerStatefulWidget {
  const OpenPdfScreen({super.key});

  @override
  ConsumerState<OpenPdfScreen> createState() => _OpenPdfScreenState();
}

class _OpenPdfScreenState extends ConsumerState<OpenPdfScreen> {
  bool _picking = false;
  String? _pickError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickAndOpen());
  }

  Future<void> _pickAndOpen() async {
    setState(() {
      _picking = true;
      _pickError = null;
    });

    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _pickError = '파일 선택기를 열지 못했습니다.';
      });
      return;
    }

    if (files.isEmpty) {
      // 사용자가 피커를 취소했다 — 홈으로 돌아간다.
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final picked = files.first;
    final sourcePath = picked.path;
    if (sourcePath == null) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _pickError = '선택한 파일의 경로를 확인할 수 없습니다.';
      });
      return;
    }

    if (!mounted) return;
    final ok = await openPdfAndGoToViewer(
      context: context,
      ref: ref,
      source: PickedFileSource(localPath: sourcePath, displayName: picked.name),
    );
    if (!mounted) return;
    if (!ok) {
      // 실패·취소는 FailureUi/비밀번호 다이얼로그가 이미 안내했다 — 홈으로 복귀.
      Navigator.of(context).pop();
    }
    // 성공 시 openPdfAndGoToViewer가 이미 뷰어로 이동시켰다(pushReplacement).
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF 열기')),
      body: Center(
        child: _picking
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('확인하는 중…')],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pickError != null) ...[
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(_pickError!, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                  ],
                  FilledButton(onPressed: _pickAndOpen, child: const Text('파일 선택')),
                ],
              ),
      ),
    );
  }
}
