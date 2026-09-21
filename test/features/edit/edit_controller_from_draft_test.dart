/// T7 (`_workspace/76_architect_design.md` §7): 드래프트 저장 → `pending()` →
/// `EditController.fromDraft` → `classify()`가 원본 세션과 동일한 `SaveOp`를
/// 반환하는지 검증한다.
///
/// `test/data/draft_repository_test.dart`의 T7은 `SizeGuard.classify`를 직접
/// 불러 저장소 계층만 검증한다. 이 파일은 한 단계 더 나아가 실제 소비자인
/// `EditController.fromDraft`를 거쳐 컨트롤러의 `classify()`가 같은 결과를
/// 내는지 확인한다(설계 §4.7 "복구 후 SaveOp 판정이 보존되는지 검증").
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/db/app_database.dart';
import 'package:pdf_daeri/data/repository/draft_repository.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';
import 'package:pdf_daeri/features/edit/edit_controller.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';

void main() {
  late Directory tempRoot;
  late AppWorkspace workspace;
  late AppDatabase db;
  late DriftDraftRepository repo;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_ctrl_draft_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDraftRepository(db: db, workspace: workspace);
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<String> makeMyDocument() async {
    const docId = 'doc-1';
    final pdf = File(workspace.docPdf(docId));
    await pdf.create(recursive: true);
    await pdf.writeAsBytes(List.filled(10, 0xAB));
    return docId;
  }

  test('T7: 저장 → pending() → EditController.fromDraft → classify()가 원본과 동일한 SaveOp', () async {
    final docId = await makeMyDocument();

    final original = [
      PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 0, rotation: 0),
      PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 1, rotation: 0),
    ];

    // 원본 세션: EditController로 편집을 진행하다가(이미지 1장 추가) 크래시된
    // 상황을 흉내낸다. 원 세션의 classify() 결과를 기준값으로 삼는다.
    final originalController = EditController(initial: original);
    final addedImagePath = workspace.draftImage('draft-1', 0);
    originalController.insertImages([addedImagePath]);
    final expectedOp = originalController.classify();
    expect(expectedOp, SaveOp.compose);

    // 드래프트로 저장(§4.6) — EditPage → DraftPageEntry 변환은 화면(§4.7)의 책임이지만
    // 테스트에서는 직접 조립한다.
    final draftPages = [
      for (final page in originalController.current.pages)
        DraftPageEntry(ref: page.ref, origin: page.origin),
    ];
    await repo.save(
      draftId: 'draft-1',
      source: EditSourceDescriptor.myDocument(docId),
      title: '테스트 문서',
      pages: draftPages,
    );

    // 재부팅 후 복구: pending() → EditController.fromDraft.
    final snapshot = await repo.pending();
    expect(snapshot, isNotNull);

    final restoredController = EditController.fromDraft(snapshot!);
    final restoredOp = restoredController.classify();

    expect(restoredOp, expectedOp);
    expect(restoredOp, SaveOp.compose);

    // existing 페이지의 경로는 절대 바뀌지 않는다(§4.7) — original과 정확히 동일해야 한다.
    final restoredExisting = [
      for (final page in restoredController.current.pages)
        if (page.origin == EditPageOrigin.existing) page.ref,
    ];
    expect(restoredExisting.map((r) => r.toMap()), original.map((r) => r.toMap()));

    // added 페이지는 drafts/ 경로를 가리킨다.
    final restoredAdded = restoredController.current.pages
        .where((p) => p.origin == EditPageOrigin.added)
        .toList();
    expect(restoredAdded, hasLength(1));
    expect((restoredAdded.single.ref as ImagePageRef).imagePath, addedImagePath);

    // id 충돌 없이 이어 붙었는지 확인 — 다음 삽입이 기존 id와 겹치지 않아야 한다.
    final idsBefore = restoredController.current.pages.map((p) => p.id).toSet();
    restoredController.insertImages([workspace.draftImage('draft-1', 1)]);
    final newPage = restoredController.current.pages.last;
    expect(idsBefore.contains(newPage.id), isFalse);
  });

  test('T7b: 편집 없이 그대로 복구되면 dirty가 false다(원본과 완전히 동일)', () async {
    final docId = await makeMyDocument();
    final original = [
      PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 0, rotation: 0),
    ];

    await repo.save(
      draftId: 'draft-2',
      source: EditSourceDescriptor.myDocument(docId),
      title: '변경 없음',
      pages: [
        for (final ref in original) DraftPageEntry(ref: ref, origin: EditPageOrigin.existing),
      ],
    );

    final snapshot = await repo.pending();
    final controller = EditController.fromDraft(snapshot!);

    // 변경이 전혀 없으면 `classify()`는 `reorderOrRotate`로 판정된다(§`size_guard.dart`
    // `classify` — before==after일 때도 이 분기를 탄다. 별도 noop 값은 없다).
    expect(controller.classify(), SaveOp.reorderOrRotate);
    expect(controller.current.dirty, isFalse);
  });
}
