// EditController 단위 테스트 -- 설계 §7.2(T3 표): 순서·회전·삭제·실행취소·toPageRefs 각각.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/features/edit/edit_controller.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';

const _pdfPath = 'recent/doc.pdf';

List<PageRef> _threePdfPages() => [
  const PdfPageRef(sourcePath: _pdfPath, sourceIndex: 0, rotation: 0),
  const PdfPageRef(sourcePath: _pdfPath, sourceIndex: 1, rotation: 0),
  const PdfPageRef(sourcePath: _pdfPath, sourceIndex: 2, rotation: 0),
];

void main() {
  group('초기 상태', () {
    test('initial로 넘긴 PageRef 순서대로 EditPage가 만들어진다', () {
      final controller = EditController(initial: _threePdfPages());
      expect(controller.state.pages.map((p) => p.ref), _threePdfPages());
      expect(controller.state.pages.every((p) => p.origin == EditPageOrigin.existing), isTrue);
      expect(controller.state.mode, EditMode.arrange);
      expect(controller.state.dirty, isFalse);
      expect(controller.state.selected, isEmpty);
    });

    test('id는 0부터 단조 증가한다', () {
      final controller = EditController(initial: _threePdfPages());
      expect(controller.state.pages.map((p) => p.id), [0, 1, 2]);
    });
  });

  group('reorder — 순서 변경', () {
    test('앞에서 뒤로 이동(oldIndex < newIndex)', () {
      final controller = EditController(initial: _threePdfPages());
      controller.reorder(0, 2); // ReorderableList 규약: 제거 전 인덱스 기준
      final indices = controller.state.pages.map((p) => (p.ref as PdfPageRef).sourceIndex).toList();
      expect(indices, [1, 0, 2]);
      expect(controller.state.dirty, isTrue);
    });

    test('뒤에서 앞으로 이동(oldIndex > newIndex)', () {
      final controller = EditController(initial: _threePdfPages());
      controller.reorder(2, 0);
      final indices = controller.state.pages.map((p) => (p.ref as PdfPageRef).sourceIndex).toList();
      expect(indices, [2, 0, 1]);
    });

    test('id는 순서 변경 후에도 페이지를 따라간다(안정 키)', () {
      final controller = EditController(initial: _threePdfPages());
      final idOfPage0 = controller.state.pages[0].id;
      controller.reorder(0, 3);
      expect(controller.state.pages.last.id, idOfPage0);
    });
  });

  group('rotateSelected — 회전', () {
    test('선택된 페이지만 90도 회전한다', () {
      final controller = EditController(initial: _threePdfPages());
      final id0 = controller.state.pages[0].id;
      controller.toggleSelect(id0);
      controller.rotateSelected();
      expect(controller.state.pages[0].ref.rotation, 90);
      expect(controller.state.pages[1].ref.rotation, 0);
      expect(controller.state.pages[2].ref.rotation, 0);
      expect(controller.state.dirty, isTrue);
    });

    test('선택이 비어 있으면 아무 일도 하지 않는다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.rotateSelected();
      expect(controller.state.pages.every((p) => p.ref.rotation == 0), isTrue);
      expect(controller.state.dirty, isFalse);
    });

    test('360도에서 다시 0으로 랩어라운드한다', () {
      final controller = EditController(initial: _threePdfPages());
      final id0 = controller.state.pages[0].id;
      controller.toggleSelect(id0);
      for (var i = 0; i < 4; i++) {
        controller.rotateSelected();
      }
      expect(controller.state.pages[0].ref.rotation, 0);
    });

    test('selectAll 후 회전하면 전체 회전과 동일하다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.selectAll();
      controller.rotateSelected();
      expect(controller.state.pages.every((p) => p.ref.rotation == 90), isTrue);
    });
  });

  group('deleteSelected / undoDelete — 삭제와 실행취소', () {
    test('선택된 페이지를 즉시 제거한다', () {
      final controller = EditController(initial: _threePdfPages());
      final id1 = controller.state.pages[1].id;
      controller.toggleSelect(id1);
      final removed = controller.deleteSelected();

      expect(controller.state.pages.length, 2);
      expect(controller.state.pages.any((p) => p.id == id1), isFalse);
      expect(controller.state.selected, isEmpty);
      expect(controller.state.dirty, isTrue);
      expect(removed.length, 1);
      expect(removed.single.index, 1);
      expect(removed.single.page.id, id1);
    });

    test('선택이 비어 있으면 아무것도 지우지 않고 빈 목록을 반환한다', () {
      final controller = EditController(initial: _threePdfPages());
      final removed = controller.deleteSelected();
      expect(removed, isEmpty);
      expect(controller.state.pages.length, 3);
    });

    test('undoDelete는 원래 위치로 복구한다', () {
      final controller = EditController(initial: _threePdfPages());
      final id1 = controller.state.pages[1].id;
      controller.toggleSelect(id1);
      final removed = controller.deleteSelected();

      controller.undoDelete(removed);

      expect(controller.state.pages.length, 3);
      expect(controller.state.pages.map((p) => p.id), [0, id1, 2]);
      expect(controller.state.dirty, isFalse);
    });

    test('여러 장 삭제 후 undoDelete는 각각 원래 인덱스로 복구한다', () {
      final controller = EditController(initial: _threePdfPages());
      final id0 = controller.state.pages[0].id;
      final id2 = controller.state.pages[2].id;
      controller.toggleSelect(id0);
      controller.toggleSelect(id2);
      final removed = controller.deleteSelected();

      expect(controller.state.pages.length, 1);

      controller.undoDelete(removed);

      expect(controller.state.pages.map((p) => p.id), [id0, 1, id2]);
    });
  });

  group('insertImages — 페이지 추가', () {
    test('at을 지정하지 않으면 끝에 추가된다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.insertImages(['/tmp/a.jpg', '/tmp/b.jpg']);
      expect(controller.state.pages.length, 5);
      expect(controller.state.pages[3].ref, isA<ImagePageRef>());
      expect((controller.state.pages[3].ref as ImagePageRef).imagePath, '/tmp/a.jpg');
      expect(controller.state.pages[3].origin, EditPageOrigin.added);
      expect(controller.state.dirty, isTrue);
    });

    test('at을 지정하면 그 위치에 삽입된다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.insertImages(['/tmp/a.jpg'], at: 1);
      expect(controller.state.pages.length, 4);
      expect(controller.state.pages[1].ref, isA<ImagePageRef>());
    });

    test('빈 목록을 넘기면 아무 일도 일어나지 않는다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.insertImages(const []);
      expect(controller.state.pages.length, 3);
      expect(controller.state.dirty, isFalse);
    });

    test('새로 추가된 페이지는 기존 id와 겹치지 않는다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.insertImages(['/tmp/a.jpg']);
      final ids = controller.state.pages.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('선택 상태', () {
    test('enterSelectMode는 선택 모드로 전환하고 해당 id 하나만 선택한다', () {
      final controller = EditController(initial: _threePdfPages());
      final id1 = controller.state.pages[1].id;
      controller.enterSelectMode(id1);
      expect(controller.state.mode, EditMode.select);
      expect(controller.state.selected, {id1});
    });

    test('toggleSelect는 선택을 켜고 끈다', () {
      final controller = EditController(initial: _threePdfPages());
      final id0 = controller.state.pages[0].id;
      controller.toggleSelect(id0);
      expect(controller.state.selected, {id0});
      controller.toggleSelect(id0);
      expect(controller.state.selected, isEmpty);
    });

    test('clearSelection은 선택을 비우고 arrange 모드로 되돌린다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.selectAll();
      controller.clearSelection();
      expect(controller.state.selected, isEmpty);
      expect(controller.state.mode, EditMode.arrange);
    });

    test('selectAll은 모든 페이지 id를 선택한다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.selectAll();
      expect(controller.state.selected, controller.state.pages.map((p) => p.id).toSet());
    });
  });

  group('toPageRefs', () {
    test('현재 화면 순서 그대로 PageRef 목록을 반환한다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.reorder(0, 2);
      final refs = controller.toPageRefs();
      expect(refs, [
        const PdfPageRef(sourcePath: _pdfPath, sourceIndex: 1, rotation: 0),
        const PdfPageRef(sourcePath: _pdfPath, sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: _pdfPath, sourceIndex: 2, rotation: 0),
      ]);
    });

    test('회전 적용 결과가 반영된다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.selectAll();
      controller.rotateSelected();
      expect(controller.toPageRefs().every((r) => r.rotation == 90), isTrue);
    });

    test('삭제 후에는 남은 페이지만 반환된다', () {
      final controller = EditController(initial: _threePdfPages());
      final id0 = controller.state.pages[0].id;
      controller.toggleSelect(id0);
      controller.deleteSelected();
      expect(controller.toPageRefs().length, 2);
    });

    test('ImagePageRef의 crop 필드가 그대로 보존된다', () {
      const crop = CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9);
      final controller = EditController(initial: const [ImagePageRef(imagePath: '/tmp/a.jpg', rotation: 0, crop: crop)]);
      final refs = controller.toPageRefs();
      expect((refs.single as ImagePageRef).crop, crop);
    });

    test('추가된 이미지 페이지도 포함된다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.insertImages(['/tmp/a.jpg'], at: 0);
      final refs = controller.toPageRefs();
      expect(refs.first, isA<ImagePageRef>());
      expect(refs.length, 4);
    });
  });

  group('classify — SizeGuard.classify 배선', () {
    test('변경이 없으면 reorderOrRotate로 판정한다(엄격한 쪽 · deletePages/compose 아님)', () {
      final controller = EditController(initial: _threePdfPages());
      expect(controller.classify(), SaveOp.reorderOrRotate);
    });

    test('삭제가 있으면 순서가 함께 바뀌어도 deletePages다', () {
      final controller = EditController(initial: _threePdfPages());
      final id0 = controller.state.pages[0].id;
      controller.toggleSelect(id0);
      controller.deleteSelected();
      controller.reorder(0, 2);
      expect(controller.classify(), SaveOp.deletePages);
    });

    test('원본에 없던 ImagePageRef가 추가되면 compose다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.insertImages(['/tmp/new.jpg']);
      expect(controller.classify(), SaveOp.compose);
    });

    test('intent가 split이면 다른 변경과 무관하게 split이다', () {
      final controller = EditController(initial: _threePdfPages());
      expect(controller.classify(intent: EditIntent.split), SaveOp.split);
    });

    test('순서/회전만 바뀌면 reorderOrRotate다', () {
      final controller = EditController(initial: _threePdfPages());
      controller.selectAll();
      controller.rotateSelected();
      expect(controller.classify(), SaveOp.reorderOrRotate);
    });
  });
}
