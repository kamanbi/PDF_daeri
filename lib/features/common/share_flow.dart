/// 시스템 공유 실행의 단일 진입점(화면 쪽). `shareExportProvider`
/// (`lib/app/providers.dart:47`)를 읽어 `sharePdf`를 호출하고 실패를 `FailureUi`로
/// 처리한다 — `compress_sheet.dart`·홈 `⋮` 메뉴·뷰어가 전부 이 함수 하나만 호출한다
/// (설계 §2.6, `providers.dart:41` "화면마다 SharePlusExport를 새로 만들지 않는다").
///
/// [W4-T1] 3주차 잔여 배선. `shareExportProvider`의 소비처를 이 함수로 통일한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_gate.dart';
import '../../app/providers.dart';
import '../../core/app_error.dart';
import 'failure_ui.dart';

/// [pdfPath]를 [title] 기반 파일명으로 공유 시트에 띄운다. 저장소 미가동
/// (`workspaceProvider == null`)·복사 실패·시스템 공유 실패는 전부 `FailureUi`
/// 다이얼로그로 알린다. 사용자가 시트를 취소한 경우도 `share_plus`는 예외 없이
/// 반환하므로(§ `share_export.dart`) 여기서는 실패로 취급하지 않는다.
Future<void> shareDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String pdfPath,
  required String title,
}) async {
  final export = ref.read(shareExportProvider);
  if (export == null) {
    await FailureUi.showDialog(
      context,
      const UnknownFailure('공유 기능을 사용할 수 없습니다.'),
    );
    return;
  }

  final result = await export.sharePdf(pdfPath: pdfPath, title: title);
  if (!context.mounted) return;

  switch (result) {
    case PdfOk<void>():
      // 공유 시트가 열렸을 때만 다음 앱 화면 전환용 광고 대기를 등록한다.
      // 실제 광고는 여기서 띄우지 않아 공유 작업을 끊지 않는다.
      unawaited(ref.read(adGateProvider).registerCompletedTask());
    case PdfErr<void>(:final failure):
      await FailureUi.showDialog(context, failure);
  }
}

/// 선택한 내 문서를 하나의 시스템 공유 시트에 넣는다.
Future<void> shareDocuments({
  required BuildContext context,
  required WidgetRef ref,
  required List<({String pdfPath, String title})> documents,
}) async {
  if (documents.isEmpty) return;
  final export = ref.read(shareExportProvider);
  if (export == null) {
    await FailureUi.showDialog(
      context,
      const UnknownFailure('공유 기능을 사용할 수 없습니다.'),
    );
    return;
  }

  final result = await export.sharePdfs(documents);
  if (!context.mounted) return;
  switch (result) {
    case PdfOk<void>():
      unawaited(ref.read(adGateProvider).registerCompletedTask());
    case PdfErr<void>(:final failure):
      await FailureUi.showDialog(context, failure);
  }
}
