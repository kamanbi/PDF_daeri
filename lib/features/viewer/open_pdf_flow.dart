/// S2-b의 **유일한** 임포트→검사→뷰어 이동 경로. (설계 §3.2, 2주차 신설)
///
/// 홈의 "PDF 열기" 버튼([PickedFileSource]), 외부 인텐트 수신([IntentUriSource]),
/// 홈 "최근 연 파일" 재열기([ExistingRecentSource]) 셋 다 이 함수 하나로 합류한다.
/// 이 함수가 없으면 진입점마다 실패 처리·라우팅이 갈라진다(§3.1).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/app_error.dart';
import '../../data/repository/recent_repository.dart';
import '../../pdf/pdf_engine.dart';
import '../common/failure_ui.dart';

/// 진입 종류. 케이스를 늘리는 것은 새 진입점을 만드는 것과 같다 — 늘리려면
/// 아키텍트를 경유한다(§3.2).
sealed class PdfOpenSource {
  const PdfOpenSource();
}

/// 홈의 "PDF 열기" → `file_picker` 결과.
final class PickedFileSource extends PdfOpenSource {
  const PickedFileSource({required this.localPath, required this.displayName});
  final String localPath;
  final String displayName;
}

/// 외부 인텐트 → `content://` URI.
final class IntentUriSource extends PdfOpenSource {
  const IntentUriSource(this.contentUri);
  final String contentUri;
}

/// 홈 "최근 연 파일" 행 탭 → 이미 복사되어 있는 것을 다시 여는 경우. 재복사하지
/// 않고 `touch(id)`만 한 뒤 inspect로 간다.
final class ExistingRecentSource extends PdfOpenSource {
  const ExistingRecentSource(this.recent);
  final RecentFile recent;
}

/// [source]를 임포트(또는 재사용)하고 `PdfEngine.inspect`로 검사한 뒤 성공하면
/// 뷰어로 이동한다. 실패·취소 시 `FailureUi`로 안내한다.
///
/// **이동 방식**: 설계 §3.2는 "뷰어로 pushReplacement"라고 못박았지만, 이는
/// S2-b가 "열기 진행 화면"을 이미 쌓은 상태를 전제한다. 인텐트로 홈에서 곧바로
/// 호출되는 경우(§4.4 "웜 스타트, 현재 홈: … 뷰어 push") 홈 라우트까지
/// pushReplacement하면 뷰어에서 뒤로 가기가 앱 종료로 이어진다 — 두 문서의
/// 요구가 충돌하는 지점이라 다음 기준으로 판단했다(근거를 여기 남긴다):
/// **현재 라우트가 pop 가능하면(=이미 뭔가 위에 쌓여 있으면) pushReplacement,
/// 아니면(=홈이 루트) push.** 이렇게 하면 "뷰어에서 뒤로 = 홈"(§3.2)과
/// "인텐트로 연 뷰어에서 뒤로 가면 앱이 사라지지 않아야 한다"(§4.4) 둘 다
/// 성립한다.
///
/// 성공 시 `true`를, 취소·실패로 끝나면 `false`를 반환한다.
Future<bool> openPdfAndGoToViewer({
  required BuildContext context,
  required WidgetRef ref,
  required PdfOpenSource source,
}) async {
  final recentRepo = ref.read(recentRepositoryProvider);
  final engine = ref.read(pdfEngineProvider);
  if (recentRepo == null || engine == null) {
    if (context.mounted) {
      await FailureUi.showDialog(
        context,
        const UnknownFailure('저장소를 사용할 수 없습니다. 앱을 다시 시작해 주세요.'),
      );
    }
    return false;
  }

  final busyNotifier = ref.read(appBusyProvider.notifier);
  busyNotifier.state = true;
  try {
    return await _run(context: context, ref: ref, source: source, recentRepo: recentRepo, engine: engine);
  } finally {
    busyNotifier.state = false;
  }
}

Future<bool> _run({
  required BuildContext context,
  required WidgetRef ref,
  required PdfOpenSource source,
  required RecentRepository recentRepo,
  required PdfEngine engine,
}) async {
  String copiedPath;
  String displayName;
  String? recentId;

  switch (source) {
    case PickedFileSource(localPath: final localPath, displayName: final pickedName):
      final r = await recentRepo.importFromLocalPath(sourcePath: localPath, displayName: pickedName);
      switch (r) {
        case PdfOk<RecentFile>(:final value):
          copiedPath = value.copiedPath;
          displayName = value.displayName;
          recentId = value.id;
        case PdfErr<RecentFile>(:final failure):
          if (context.mounted) await FailureUi.showDialog(context, failure);
          return false;
      }
    case IntentUriSource(:final contentUri):
      final r = await recentRepo.importFromUri(contentUri);
      switch (r) {
        case PdfOk<RecentFile>(:final value):
          copiedPath = value.copiedPath;
          displayName = value.displayName;
          recentId = value.id;
        case PdfErr<RecentFile>(:final failure):
          if (context.mounted) await FailureUi.showDialog(context, failure);
          return false;
      }
    case ExistingRecentSource(:final recent):
      if (!await File(recent.copiedPath).exists()) {
        if (context.mounted) {
          final action = await FailureUi.showDialog(context, SourceMissing(recent.copiedPath));
          if (action == FailureAction.removeFromList) {
            await recentRepo.removeFromList(recent.id);
          }
        }
        return false;
      }
      await recentRepo.touch(recent.id);
      copiedPath = recent.copiedPath;
      displayName = recent.displayName;
      recentId = recent.id;
  }

  // inspect → 필요 시 비밀번호 반복 입력.
  var result = await engine.inspect(copiedPath);
  String? password;
  var isEncrypted = false;

  if (result is PdfErr<PdfDocInfo> && result.failure is SourceEncrypted) {
    while (true) {
      if (!context.mounted) return false;
      final pw = await _promptPassword(context, displayName);
      if (pw == null) {
        // 사용자 취소: recent 행은 유지한다(§3.1 — 재시도 가능하도록).
        return false;
      }
      result = await engine.inspect(copiedPath, password: pw);
      if (result is PdfOk<PdfDocInfo>) {
        password = pw;
        isEncrypted = true;
        break;
      }
      final failure = (result as PdfErr<PdfDocInfo>).failure;
      if (failure is SourceEncrypted) {
        if (!context.mounted) return false;
        await _showWrongPassword(context);
        continue;
      }
      if (context.mounted) {
        final action = await FailureUi.showDialog(context, failure);
        if (action == FailureAction.removeFromList) {
          await recentRepo.removeFromList(recentId);
        }
      }
      return false;
    }
  } else if (result is PdfErr<PdfDocInfo>) {
    final failure = result.failure;
    if (context.mounted) {
      final action = await FailureUi.showDialog(context, failure);
      if (action == FailureAction.removeFromList) {
        await recentRepo.removeFromList(recentId);
      }
    }
    return false;
  }

  final info = (result as PdfOk<PdfDocInfo>).value;

  if (!context.mounted) return false;
  final navigator = Navigator.of(context);
  final args = ViewerArgs(
    pdfPath: copiedPath,
    title: displayName,
    pageCount: info.pageCount,
    password: password,
    isEncrypted: isEncrypted || info.isEncrypted,
    recentId: recentId,
  );
  if (navigator.canPop()) {
    navigator.pushReplacementNamed(AppRoutes.viewer, arguments: args);
  } else {
    navigator.pushNamed(AppRoutes.viewer, arguments: args);
  }
  return true;
}

Future<String?> _promptPassword(BuildContext context, String displayName) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('암호로 보호된 문서'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"$displayName" 파일은 암호로 보호되어 있습니다.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

Future<void> _showWrongPassword(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('암호로 보호된 문서'),
      content: const Text('비밀번호가 맞지 않습니다.'),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('확인'))],
    ),
  );
}
