/// `DraftRepository` 계약 테스트. (`_workspace/76_architect_design.md` §7 T7/T8/T9)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/db/app_database.dart';
import 'package:pdf_daeri/data/repository/draft_repository.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';
import 'package:pdf_daeri/features/edit/edit_controller.dart' show EditPageOrigin;
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/stamp_builder.dart';

void main() {
  late Directory tempRoot;
  late AppWorkspace workspace;
  late AppDatabase db;
  late DriftDraftRepository repo;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_draft_test_');
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

  test('T7: 저장 → pending() 왕복 시 origin이 정확히 복원되고 SaveOp 판정이 보존된다', () async {
    final docId = await makeMyDocument();

    final original = [
      PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 0, rotation: 0),
      PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 1, rotation: 0),
    ];
    // 편집: 기존 페이지 순서 변경 없이 이미지 1장 추가 → compose로 판정돼야 한다.
    final edited = [
      DraftPageEntry(ref: original[0], origin: EditPageOrigin.existing),
      DraftPageEntry(ref: original[1], origin: EditPageOrigin.existing),
      DraftPageEntry(
        ref: ImagePageRef(imagePath: workspace.draftImage('draft-1', 0), rotation: 0),
        origin: EditPageOrigin.added,
      ),
    ];

    await repo.save(
      draftId: 'draft-1',
      source: EditSourceDescriptor.myDocument(docId),
      title: '테스트 문서',
      pages: edited,
    );

    final snapshot = await repo.pending();
    expect(snapshot, isNotNull);
    expect(snapshot!.draftId, 'draft-1');
    expect(snapshot.title, '테스트 문서');
    // source가 정확히 복원됐는지는 파일 존재 판정을 통해 간접 확인한다 — pending()이
    // null이 아니라는 것 자체가 my_document 소스가 `docId`로 올바르게 복원되고
    // `workspace.docPdf(docId)` 존재 확인을 통과했다는 뜻이다(source 하위 타입은
    // 라이브러리 비공개라 테스트에서 직접 패턴매치할 수 없다).

    // origin 왕복 검증
    expect(snapshot.pages.length, edited.length);
    for (var i = 0; i < edited.length; i++) {
      expect(snapshot.pages[i].origin, edited[i].origin);
      expect(snapshot.pages[i].ref.toMap(), equals(edited[i].ref.toMap()));
    }

    // SaveOp 판정 보존: 복구된 스냅샷에서 origin==existing만 골라 before를 재구성하고,
    // 전체를 after로 삼아 원래 세션과 동일한 SaveOp가 나오는지 확인한다.
    final restoredBefore = [
      for (final entry in snapshot.pages)
        if (entry.origin == EditPageOrigin.existing) entry.ref,
    ];
    final restoredAfter = [for (final entry in snapshot.pages) entry.ref];
    final restoredOp = SizeGuard.classify(
      before: restoredBefore,
      after: restoredAfter,
      intent: EditIntent.edit,
    );
    final expectedOp = SizeGuard.classify(
      before: original,
      after: [for (final e in edited) e.ref],
      intent: EditIntent.edit,
    );
    expect(restoredOp, expectedOp);
    expect(restoredOp, SaveOp.compose);
  });

  test('T8: adoptImages 후 임시 디렉터리를 통째로 지워도 pending()의 이미지가 살아있다', () async {
    final docId = await makeMyDocument();

    final tempDir = await Directory.systemTemp.createTemp('pdf_daeri_draft_src_');
    final temp1 = p.join(tempDir.path, 'a.jpg');
    final temp2 = p.join(tempDir.path, 'b.jpg');
    await File(temp1).writeAsBytes(List.filled(5, 1));
    await File(temp2).writeAsBytes(List.filled(5, 2));

    final adopted = await repo.adoptImages('draft-2', [temp1, temp2]);
    expect(adopted.length, 2);
    for (final path in adopted) {
      expect(await File(path).exists(), isTrue);
    }

    await repo.save(
      draftId: 'draft-2',
      source: EditSourceDescriptor.myDocument(docId),
      title: '스캔 문서',
      pages: [
        for (final path in adopted)
          DraftPageEntry(
            ref: ImagePageRef(imagePath: path, rotation: 0),
            origin: EditPageOrigin.added,
          ),
      ],
    );

    // 임시(캐시) 디렉터리를 통째로 삭제 — 부팅 시 캐시 정리를 흉내낸다.
    await tempDir.delete(recursive: true);

    final snapshot = await repo.pending();
    expect(snapshot, isNotNull);
    expect(snapshot!.pages.length, 2);
    for (final entry in snapshot.pages) {
      final imagePath = (entry.ref as ImagePageRef).imagePath;
      expect(await File(imagePath).exists(), isTrue, reason: '$imagePath 는 drafts/ 사본이라 살아있어야 한다');
      // 임시 경로가 아니라 drafts/ 아래로 복사됐는지도 확인한다.
      expect(imagePath, contains(p.join('drafts', 'draft-2')));
    }
  });

  test('T9a: DB 행 없는 drafts/x/ 디렉터리가 reconcile()로 사라진다', () async {
    await workspace.beginDraft('orphan-1');
    expect(await Directory(workspace.draftDir('orphan-1')).exists(), isTrue);

    await repo.reconcile();

    expect(await Directory(workspace.draftDir('orphan-1')).exists(), isFalse);
  });

  test('T9b: 소스 문서가 사라진 드래프트는 pending()이 null + 폐기된다', () async {
    final tempDir = await Directory.systemTemp.createTemp('pdf_daeri_draft_ext_');
    final externalPdf = p.join(tempDir.path, 'external.pdf');
    await File(externalPdf).writeAsBytes(List.filled(20, 0xEE));

    await repo.save(
      draftId: 'draft-3',
      source: EditSourceDescriptor.externalPdf(pdfPath: externalPdf, title: '외부 PDF'),
      title: '외부 PDF',
      pages: [
        DraftPageEntry(
          ref: PdfPageRef(sourcePath: externalPdf, sourceIndex: 0, rotation: 0),
          origin: EditPageOrigin.existing,
        ),
      ],
    );

    // 소스 파일 삭제(원본이 사라진 상황을 흉내낸다).
    await File(externalPdf).delete();

    final snapshot = await repo.pending();
    expect(snapshot, isNull);

    // 폐기됐는지 DB에서도 확인한다.
    final rows = await db.select(db.editDrafts).get();
    expect(rows, isEmpty);

    await tempDir.delete(recursive: true);
  });

  test(
    'T14: 저장(save) 후 pending()에서 마크(형광펜·텍스트·이미지)가 원본 값 그대로 복원된다',
    () async {
      final docId = await makeMyDocument();

      final markBytes = Uint8List.fromList(List.filled(8, 0x42));
      final pages = [
        DraftPageEntry(
          ref: PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 0, rotation: 0),
          origin: EditPageOrigin.existing,
          marks: [
            const HighlightMark(
              rect: StampRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2),
              colorArgb: 0xFFFFFF00,
              opacity: 0.35,
            ),
            const TextMark(
              rect: StampRect(left: 0.1, top: 0.3, right: 0.9, bottom: 0.4),
              text: '2026년 8월 보고서 (최종)',
              fontSizePt: 14,
            ),
            ImageMark(
              rect: const StampRect(left: 0.6, top: 0.6, right: 0.9, bottom: 0.9),
              pngBytes: markBytes,
            ),
          ],
        ),
      ];

      await repo.save(
        draftId: 'draft-marks-1',
        source: EditSourceDescriptor.myDocument(docId),
        title: '주석 테스트',
        pages: pages,
      );

      final snapshot = await repo.pending();
      expect(snapshot, isNotNull);
      expect(snapshot!.pages, hasLength(1));
      final marks = snapshot.pages.single.marks;
      expect(marks, hasLength(3));

      final highlight = marks.whereType<HighlightMark>().single;
      expect(highlight.colorArgb, 0xFFFFFF00);
      expect(highlight.opacity, 0.35);
      expect(highlight.rect, const StampRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.2));

      final text = marks.whereType<TextMark>().single;
      expect(text.text, '2026년 8월 보고서 (최종)');
      expect(text.fontSizePt, 14);

      final image = marks.whereType<ImageMark>().single;
      expect(image.pngBytes, markBytes);
    },
  );

  test(
    'T14: adoptMarkAssets가 쓴 파일은 원본 bytes 참조를 버려도(GC 대상이 돼도) '
    'drafts/<id>/marks/ 아래 내구 사본으로 살아있다',
    () async {
      final adopted = await repo.adoptMarkAssets('draft-marks-2', [
        Uint8List.fromList(List.filled(4, 0x11)),
        Uint8List.fromList(List.filled(4, 0x22)),
      ]);

      expect(adopted, hasLength(2));
      for (final path in adopted) {
        expect(await File(path).exists(), isTrue);
        expect(path, contains(p.join('drafts', 'draft-marks-2', 'marks')));
      }
    },
  );

  test('T14: 드래프트가 폐기되면 drafts/<id>/marks/ 를 포함한 디렉터리 전체가 사라진다', () async {
    final docId = await makeMyDocument();

    await repo.save(
      draftId: 'draft-marks-3',
      source: EditSourceDescriptor.myDocument(docId),
      title: '주석 폐기 테스트',
      pages: [
        DraftPageEntry(
          ref: PdfPageRef(sourcePath: workspace.docPdf(docId), sourceIndex: 0, rotation: 0),
          origin: EditPageOrigin.existing,
          marks: [
            ImageMark(
              rect: const StampRect(left: 0.1, top: 0.1, right: 0.3, bottom: 0.3),
              pngBytes: Uint8List.fromList(List.filled(4, 0x33)),
            ),
          ],
        ),
      ],
    );

    expect(await Directory(p.join(workspace.draftDir('draft-marks-3'), 'marks')).exists(), isTrue);

    // 굽기(stamp 저장) 성공 후와 동일하게 드래프트 전체가 정리되는 경로를 흉내낸다
    // (실제 커밋 경로 `document_repository.dart`의 `stampToNewDocument`는 이번
    // 라운드 범위 밖이다 — 여기서는 `DraftRepository.discard`가 `drafts/<id>/`를
    // 통째로 지우는 것으로 동일한 정리 보장을 확인한다).
    await repo.discard('draft-marks-3');

    expect(await Directory(workspace.draftDir('draft-marks-3')).exists(), isFalse);
  });

  test('결정 3: 새 드래프트를 저장하면 기존 드래프트가 전부 제거된다', () async {
    final docId = await makeMyDocument();

    await repo.save(
      draftId: 'draft-old',
      source: EditSourceDescriptor.myDocument(docId),
      title: '이전 드래프트',
      pages: const [],
    );
    await workspace.beginDraft('draft-old');

    await repo.save(
      draftId: 'draft-new',
      source: EditSourceDescriptor.myDocument(docId),
      title: '새 드래프트',
      pages: const [],
    );

    final rows = await db.select(db.editDrafts).get();
    expect(rows.map((r) => r.id), ['draft-new']);
    expect(await Directory(workspace.draftDir('draft-old')).exists(), isFalse);
  });
}
