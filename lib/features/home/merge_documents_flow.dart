/// S1 홈 다중 선택 → 합치기 실행의 **유일한** 배선 지점. (설계 §3.1·§3.4)
///
/// `home_screen.dart`(담당 U)는 선택된 [DocumentSummary] 목록을 모아 이 함수 하나만
/// 부른다 — 화면이 `PdfEngine`이나 `PageRef` 조립 규칙을 직접 알 필요가 없다(레이어
/// 경계, `platform-integration.md` 역할 경계). `DocumentRepository.createDocument`
/// 외의 저장 경로를 만들지 않는다(§3.4 "저장 경로를 늘리지 않는다").
///
/// **[2026-08-25 · T4 완료 후 배선]** T4에서 `save_dialog.dart`가 완성되어, 임시
/// 확인 다이얼로그를 `showSaveDialog(spec: SaveRequestSpec(showQualityPicker: false,
/// ...))`로 교체했다(설계 §3.1 "확인 창 없이 곧바로 저장 다이얼로그" 그대로).
/// `PdfPageRef`만 조립하므로 화질 선택은 뜨지 않는다(§3.1, quality가 무의미).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../core/file_name.dart';
import '../../core/size_guard.dart';
import '../../data/repository/document_repository.dart';
import '../../pdf/page_ref.dart';
import '../edit/save_dialog.dart';
import '../common/failure_ui.dart';

/// [selected]를 화면에 보이는 순서(= `updated_at DESC`, 즉 호출자가 넘긴 리스트 순서
/// 그대로) 그 순서대로 이어 붙여 새 문서를 만든다. 2개 미만이면 아무 것도 하지 않고
/// `null`을 반환한다 — 버튼 활성화 조건(§3.1 "2개 이상")은 호출자가 이미 지키지만,
/// 이 함수도 방어적으로 재확인한다.
///
Future<DocumentSummary?> mergeDocumentsAndCreate({
  required BuildContext context,
  required WidgetRef ref,
  required List<DocumentSummary> selected,
}) async {
  if (selected.length < 2) return null;

  final repo = ref.read(documentRepositoryProvider);
  if (repo == null) {
    if (context.mounted) {
      await FailureUi.showDialog(
        context,
        const UnknownFailure('저장소를 사용할 수 없습니다. 앱을 다시 시작해 주세요.'),
      );
    }
    return null;
  }

  final workspace = ref.read(workspaceProvider);
  if (workspace == null) {
    if (context.mounted) {
      await FailureUi.showDialog(
        context,
        const UnknownFailure('저장소를 사용할 수 없습니다. 앱을 다시 시작해 주세요.'),
      );
    }
    return null;
  }

  final title = FileName.mergedTitle(selected.first.title, selected.length);

  // §3.4 표: "합치기 → 문서 i의 document.pdf를 소스로 PdfPageRef(sourcePath, sourceIndex: j) 전개".
  final pages = <PageRef>[
    for (final doc in selected)
      for (var i = 0; i < doc.pageCount; i++)
        PdfPageRef(sourcePath: workspace.docPdf(doc.id), sourceIndex: i, rotation: 0),
  ];

  final baselineBytes = selected.fold<int>(0, (sum, doc) => sum + doc.fileSize);

  if (!context.mounted) return null;
  final value = await showSaveDialog(
    context: context,
    ref: ref,
    spec: SaveRequestSpec(
      suggestedTitle: title,
      origin: selected.first.origin, // §3.1 "첫 문서의 origin을 승계한다"
      pages: pages,
      guardInput: assembleGuardInput(op: SaveOp.merge, baselineBytes: baselineBytes),
      showQualityPicker: false, // PdfPageRef만 조립하므로 quality가 무의미(§3.1)
    ),
  );

  if (value != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${value.title}"(으)로 합쳤습니다')));
  }
  return value;
}
