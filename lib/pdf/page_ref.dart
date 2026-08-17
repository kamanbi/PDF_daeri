/// `PageRef` — 문서를 구성하는 한 페이지의 출처. 이원화(이미지 | 기존 PDF 페이지)로
/// 무손실 파이프라인 전체가 분기한다(§5 소비 지점 전수 목록 참조).
///
/// 무손실 보장: 이 타입 자체는 데이터만 들고 있으며 렌더링·재인코딩을 하지 않는다.
/// [PdfPageRef]는 저장 시 원본 PDF에서 페이지 객체를 그대로 import하는 데 쓰인다
/// (`pdf_engine_isolate.dart`가 유일한 소비처, §5-1).
library;

sealed class PageRef {
  const PageRef({required this.rotation})
    : assert(rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270);

  /// 0/90/270/180. 원본 회전에 **더해지는** 상대 회전이다.
  final int rotation;

  Map<String, Object?> toMap();

  static PageRef fromMap(Map<String, Object?> m) => switch (m['kind'] as String) {
    'image' => ImagePageRef(imagePath: m['imagePath']! as String, rotation: m['rotation']! as int),
    'pdf' => PdfPageRef(
      sourcePath: m['sourcePath']! as String,
      sourceIndex: m['sourceIndex']! as int,
      rotation: m['rotation']! as int,
    ),
    _ => throw StateError('unknown PageRef kind'),
  };
}

final class ImagePageRef extends PageRef {
  const ImagePageRef({required this.imagePath, required super.rotation});

  /// `docs/<docId>/sources/pages/NNN.jpg` 만 허용. §3.3 경로 화이트리스트 참조.
  final String imagePath;

  @override
  Map<String, Object?> toMap() => {'kind': 'image', 'imagePath': imagePath, 'rotation': rotation};
}

final class PdfPageRef extends PageRef {
  const PdfPageRef({required this.sourcePath, required this.sourceIndex, required super.rotation});

  /// `docs/<docId>/sources/src_N.pdf` 또는 `recent/<uuid>.pdf`
  final String sourcePath;

  /// 원본 PDF에서의 0-base 페이지 번호
  final int sourceIndex;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'pdf',
    'sourcePath': sourcePath,
    'sourceIndex': sourceIndex,
    'rotation': rotation,
  };
}
