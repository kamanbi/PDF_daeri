/// S3 편집 화면과 사진→PDF 생성 편집이 공유하는 순수 상태 컨트롤러.
/// 설계: `_workspace/36_architect_week3_design.md` §1.2("페이지 목록 상태 관리").
///
/// 이 파일은 화면(그리드·드래그 위젯)을 갖지 않는다 — 상태 관리만 한다(다음 라운드에
/// `page_grid_editor.dart`가 이 컨트롤러를 소비한다). 저장은 항상 새 문서를 만드는
/// `DocumentRepository.createDocument` 경로를 통해서만 일어난다(§1.5) — 이 컨트롤러는
/// 원본 문서 파일을 직접 수정하는 코드를 갖지 않는다(파일 I/O를 전혀 하지 않는다).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/size_guard.dart';
import '../../pdf/page_ref.dart';

/// 이 페이지가 원본에서 온 것인지(`existing`), 이번 편집에서 추가된 것인지(`added`).
/// `SaveOp` 판정(§1.6)과 배지 표시에 쓴다.
enum EditPageOrigin { existing, added }

/// 편집 중인 페이지 1장. `PageRef`에 **UI 전용 안정 키**를 덧씌운 래퍼다.
/// 드래그 재정렬은 위젯 키가 안정적이어야 동작하는데, `PageRef`는 값 타입이라
/// 회전/순서가 바뀌면 동등성이 흔들린다. 그래서 `id`를 따로 둔다.
class EditPage {
  const EditPage({required this.id, required this.ref, required this.origin});

  /// 화면 생명주기 안에서만 유효한 단조 증가 정수. DB·파일에 저장하지 않는다.
  final int id;
  final PageRef ref;
  final EditPageOrigin origin;

  EditPage copyWith({PageRef? ref}) => EditPage(id: id, ref: ref ?? this.ref, origin: origin);
}

/// S3와 사진→PDF 생성 편집이 **공유하는** 편집 상태. 두 화면이 같은 컨트롤러를 쓴다(§2.1).
class EditState {
  const EditState({required this.pages, required this.selected, required this.mode, required this.dirty});

  final List<EditPage> pages; // 화면에 보이는 순서 = 저장 시 페이지 순서
  final Set<int> selected; // EditPage.id 집합
  final EditMode mode;
  final bool dirty; // 원본과 달라졌는가 (뒤로가기 확인 판단에만 쓴다)

  EditState copyWith({List<EditPage>? pages, Set<int>? selected, EditMode? mode, bool? dirty}) => EditState(
    pages: pages ?? this.pages,
    selected: selected ?? this.selected,
    mode: mode ?? this.mode,
    dirty: dirty ?? this.dirty,
  );
}

/// `EditArgs.initialMode`와 동일한 값 집합(설계 §1.1). 이 파일은 라우팅을 모르므로
/// 여기서도 선언해 `edit_controller.dart`가 `router.dart`에 의존하지 않게 한다.
enum EditMode { arrange, select }

class EditController extends StateNotifier<EditState> {
  EditController({required List<PageRef> initial})
    : original = List.unmodifiable(initial),
      _nextId = initial.length,
      super(
        EditState(
          pages: [
            for (var i = 0; i < initial.length; i++) EditPage(id: i, ref: initial[i], origin: EditPageOrigin.existing),
          ],
          selected: const {},
          mode: EditMode.arrange,
          dirty: false,
        ),
      );

  /// 원본 페이지 목록. `SaveOp` 판정(§1.6)의 `before`가 된다. 변경되지 않는다.
  final List<PageRef> original;

  int _nextId;

  // --- 순서 ---

  /// 드래그 재정렬. [newIndex]는 `ReorderableList` 계열 규약과 동일하게
  /// **제거 전 인덱스 기준**으로 받는다(구현이 보정한다).
  void reorder(int oldIndex, int newIndex) {
    final pages = List<EditPage>.of(state.pages);
    final page = pages.removeAt(oldIndex);
    var insertAt = newIndex;
    if (oldIndex < newIndex) insertAt -= 1;
    pages.insert(insertAt, page);
    _apply(pages);
  }

  // --- 회전 ---

  /// 선택된 페이지 전부를 시계방향 90° 돌린다. 선택이 비어 있으면 아무 일도 하지 않는다.
  /// `rotation = (rotation + 90) % 360`. 원본 회전에 더해지는 상대 회전이다(§2.2 계약 유지).
  void rotateSelected() {
    if (state.selected.isEmpty) return;
    final pages = [
      for (final page in state.pages)
        if (state.selected.contains(page.id)) page.copyWith(ref: _rotate90(page.ref)) else page,
    ];
    _apply(pages);
  }

  static PageRef _rotate90(PageRef ref) {
    final newRotation = (ref.rotation + 90) % 360;
    return switch (ref) {
      ImagePageRef(:final imagePath, :final crop) => ImagePageRef(imagePath: imagePath, rotation: newRotation, crop: crop),
      PdfPageRef(:final sourcePath, :final sourceIndex) => PdfPageRef(
        sourcePath: sourcePath,
        sourceIndex: sourceIndex,
        rotation: newRotation,
      ),
    };
  }

  // --- 삭제 ---

  /// 선택된 페이지를 목록에서 **즉시 제거**한다. 파일은 건드리지 않는다.
  /// 되돌리기용으로 제거된 항목과 원래 인덱스를 반환한다.
  List<({int index, EditPage page})> deleteSelected() {
    if (state.selected.isEmpty) return const [];
    final removed = <({int index, EditPage page})>[];
    final pages = <EditPage>[];
    for (var i = 0; i < state.pages.length; i++) {
      final page = state.pages[i];
      if (state.selected.contains(page.id)) {
        removed.add((index: i, page: page));
      } else {
        pages.add(page);
      }
    }
    state = state.copyWith(pages: pages, selected: const {});
    _recomputeDirty();
    return removed;
  }

  /// [deleteSelected]의 반환값을 그대로 넣어 원래 위치로 복구한다(스낵바 "실행취소").
  void undoDelete(List<({int index, EditPage page})> removed) {
    if (removed.isEmpty) return;
    final pages = List<EditPage>.of(state.pages);
    final ordered = List<({int index, EditPage page})>.of(removed)..sort((a, b) => a.index.compareTo(b.index));
    for (final entry in ordered) {
      final at = entry.index <= pages.length ? entry.index : pages.length;
      pages.insert(at, entry.page);
    }
    _apply(pages);
  }

  // --- 페이지 추가 ---

  /// 카메라(ML Kit)·사진 선택 결과 이미지 경로들을 [at] 위치에 삽입한다.
  /// 경로는 아직 `sources/` 밖의 임시 경로다 — 복사는 저장 시 Repository가 한다(§1.5).
  void insertImages(List<String> imagePaths, {int? at}) {
    if (imagePaths.isEmpty) return;
    final newPages = [for (final path in imagePaths) EditPage(id: _nextId++, ref: ImagePageRef(imagePath: path, rotation: 0), origin: EditPageOrigin.added)];
    final pages = List<EditPage>.of(state.pages);
    final requested = at ?? pages.length;
    final insertAt = requested < 0 ? 0 : (requested > pages.length ? pages.length : requested);
    pages.insertAll(insertAt, newPages);
    _apply(pages);
  }

  // --- 선택 ---

  void enterSelectMode(int id) {
    state = state.copyWith(mode: EditMode.select, selected: {id});
  }

  void toggleSelect(int id) {
    final selected = Set<int>.of(state.selected);
    if (!selected.remove(id)) selected.add(id);
    state = state.copyWith(selected: selected);
  }

  void clearSelection() {
    state = state.copyWith(mode: EditMode.arrange, selected: const {});
  }

  void selectAll() {
    state = state.copyWith(selected: {for (final page in state.pages) page.id});
  }

  /// 현재 목록을 저장 입력으로 변환한다. 화면 순서 그대로.
  List<PageRef> toPageRefs() => [for (final page in state.pages) page.ref];

  /// 현재 편집 상태가 저장 시 어느 `SaveOp`로 판정될지 미리 계산한다(설계 §1.6 배선).
  /// 화면·다이얼로그가 `SizeGuard.classify`를 직접 부르지 않고 이 메서드를 통해서만
  /// 판정을 얻는다 — 판정 로직이 컨트롤러와 화면 두 곳에 흩어지는 것을 막는다.
  /// [intent]는 "선택 페이지로 새 문서"(나누기) 흐름에서만 `EditIntent.split`을 넘긴다.
  SaveOp classify({EditIntent intent = EditIntent.edit}) =>
      SizeGuard.classify(before: original, after: toPageRefs(), intent: intent);

  void _apply(List<EditPage> pages) {
    state = state.copyWith(pages: pages);
    _recomputeDirty();
  }

  void _recomputeDirty() {
    state = state.copyWith(dirty: !_sameAsOriginal(state.pages));
  }

  bool _sameAsOriginal(List<EditPage> pages) {
    if (pages.length != original.length) return false;
    for (var i = 0; i < pages.length; i++) {
      if (_key(pages[i].ref) != _key(original[i])) return false;
    }
    return true;
  }

  /// `dirty` 판정 전용 키. `SizeGuard.classify`의 동일성 키(rotation 제외)와 달리
  /// 여기서는 rotation도 포함한다 — 회전만 바뀌어도 "저장하지 않고 나갈까요?"를 물어야 한다.
  static String _key(PageRef ref) => switch (ref) {
    ImagePageRef(:final imagePath, :final crop, :final rotation) => 'img|$imagePath|${crop?.encode() ?? ''}|$rotation',
    PdfPageRef(:final sourcePath, :final sourceIndex, :final rotation) => 'pdf|$sourcePath|$sourceIndex|$rotation',
  };
}
