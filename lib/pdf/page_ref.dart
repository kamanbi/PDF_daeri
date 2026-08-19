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
    'image' => ImagePageRef(
      imagePath: m['imagePath']! as String,
      rotation: m['rotation']! as int,
      crop: CropRect.decode(m['crop'] as String?),
    ),
    'pdf' => PdfPageRef(
      sourcePath: m['sourcePath']! as String,
      sourceIndex: m['sourceIndex']! as int,
      rotation: m['rotation']! as int,
    ),
    _ => throw StateError('unknown PageRef kind'),
  };
}

/// 이미지 페이지의 크롭 영역. **원본 픽셀 크기에 대한 정규화 비율**(0.0~1.0)이다.
/// 픽셀 좌표를 쓰지 않는 이유: 마스터가 프리셋으로 축소돼도 같은 값이 그대로 유효하다.
/// 회전 **적용 전**(마스터 원본 방향) 좌표계다 — 회전은 PDF 페이지 속성이므로
/// 픽셀에 영향을 주지 않는다(설계 §2.3).
final class CropRect {
  const CropRect({required this.left, required this.top, required this.right, required this.bottom})
    : assert(left >= 0 && top >= 0 && right <= 1 && bottom <= 1),
      assert(right > left && bottom > top);

  final double left, top, right, bottom;

  double get widthFraction => right - left;
  double get heightFraction => bottom - top;

  /// 전체 영역인가(= 크롭이 없는 것과 같은가). 이 경우 `null`로 정규화해 저장한다
  /// (정규화 자체는 이 타입의 책임이 아니라 크롭 UI/호출부의 책임이다 — 이 클래스는 값 타입일 뿐).
  bool get isFull => left == 0 && top == 0 && right == 1 && bottom == 1;

  /// "l,t,r,b" — DB `pages.crop` 컬럼과 isolate 경계에서 쓰는 유일한 직렬화 형식.
  String encode() => '$left,$top,$right,$bottom';

  static CropRect? decode(String? s) {
    if (s == null) return null;
    final parts = s.split(',');
    if (parts.length != 4) throw FormatException('invalid CropRect encoding: $s');
    final left = double.parse(parts[0]);
    final top = double.parse(parts[1]);
    final right = double.parse(parts[2]);
    final bottom = double.parse(parts[3]);
    return CropRect(left: left, top: top, right: right, bottom: bottom);
  }

  @override
  bool operator ==(Object other) =>
      other is CropRect && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'CropRect(${encode()})';
}

final class ImagePageRef extends PageRef {
  const ImagePageRef({required this.imagePath, required super.rotation, this.crop});

  /// `docs/<docId>/sources/pages/NNN.jpg` 만 허용. §3.3 경로 화이트리스트 참조.
  final String imagePath;

  /// null = 크롭 없음(원본 전체). `PdfPageRef`는 크롭을 갖지 않는다(설계 §2.2 —
  /// 크롭은 사진→PDF 생성 흐름 전용이며 기존 PDF 페이지에는 적용하지 않는다).
  final CropRect? crop;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'image',
    'imagePath': imagePath,
    'rotation': rotation,
    'crop': crop?.encode(), // null 허용
  };
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
