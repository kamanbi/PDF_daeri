// M-E6 테스트 전용 헬퍼(_test.dart 접미사 없음 -- `flutter test`가 별도 스위트로 수집하지 않는다).
//
// `ImagePdfBuilder.build`/`package:pdf`는 항상 `/DCTDecode` + `/DeviceRGB|/DeviceGray`만 만들어내서
// 명시적 제외 색공간(JPXDecode/CCITTFaxDecode 등)을 담은 픽스처를 만들 수 없다. qpdf가 읽을 수 있는
// 최소 유효 PDF(카탈로그/페이지트리/이미지 XObject/xref/trailer)를 직접 조립해 임의의 `/Filter`·
// `/ColorSpace`·`/BitsPerComponent`·`/ImageMask` 조합을 픽스처로 만든다. 스트림 바이트 자체는
// 실제 JP2/CCITT 코덱 데이터가 아니어도 된다 -- qpdf isolate는 적격 규칙(딕셔너리 키)만 보고
// 부적격이면 스트림을 열어보지도(get_stream_data) 않는다(§2.3).
import 'dart:convert';
import 'dart:typed_data';

/// 오브젝트를 순서대로 쌓고 xref/trailer를 자동 계산하는 최소 PDF 빌더.
class RawPdfBuilder {
  final List<int> _ids = [];
  final Map<int, List<int>> _bodies = {};
  int _autoId = 1;

  int allocId() => _autoId++;

  /// `<< dictBody >>` 형태의 비-스트림 오브젝트.
  int addDict(String dictBody) {
    final id = allocId();
    _ids.add(id);
    _bodies[id] = utf8.encode('$id 0 obj\n<< $dictBody >>\nendobj\n');
    return id;
  }

  /// 스트림 오브젝트. [dictEntries]는 `/Length`를 뺀 나머지 키만 준다(길이는 자동 계산).
  int addStream(String dictEntries, List<int> streamBytes) {
    final id = allocId();
    _ids.add(id);
    final header = utf8.encode('$id 0 obj\n<< $dictEntries /Length ${streamBytes.length} >>\nstream\n');
    final footer = utf8.encode('\nendstream\nendobj\n');
    _bodies[id] = [...header, ...streamBytes, ...footer];
    return id;
  }

  Uint8List build({required int rootId}) {
    final buf = BytesBuilder();
    buf.add(utf8.encode('%PDF-1.4\n'));
    final offsets = <int, int>{};
    for (final id in _ids) {
      offsets[id] = buf.length;
      buf.add(_bodies[id]!);
    }
    final maxId = _ids.reduce((a, b) => a > b ? a : b);
    final xrefOffset = buf.length;
    final xref = StringBuffer()
      ..write('xref\n0 ${maxId + 1}\n')
      ..write('0000000000 65535 f \n');
    for (var i = 1; i <= maxId; i++) {
      final off = offsets[i];
      if (off != null) {
        xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
      } else {
        xref.write('0000000000 00000 f \n');
      }
    }
    buf.add(utf8.encode(xref.toString()));
    buf.add(utf8.encode('trailer\n<< /Size ${maxId + 1} /Root $rootId 0 R >>\nstartxref\n$xrefOffset\n%%EOF'));
    return buf.toBytes();
  }
}

const _emptyContent = 'q Q'; // 콘텐츠 스트림은 비어 있어도 된다 -- 이미지는 Resources/XObject로만 발견된다.

/// 이미지 XObject가 전혀 없는 최소 1페이지 PDF("텍스트 PDF" 픽스처 -- 후보 0개 확인용).
Uint8List buildTextOnlyPdf() {
  final b = RawPdfBuilder();
  final contentId = b.addStream('', utf8.encode(_emptyContent));
  final pageId = b.addDict('/Type /Page /Parent 0 0 R /MediaBox [0 0 200 200] /Contents $contentId 0 R');
  final pagesId = b.addDict('/Type /Pages /Kids [$pageId 0 R] /Count 1');
  final catalogId = b.addDict('/Type /Catalog /Pages $pagesId 0 R');
  return _fixPageParentAndBuild(b, pageId: pageId, pagesId: pagesId, catalogId: catalogId);
}

/// 이미지 XObject 1개를 참조하는 단일 페이지 PDF. 색공간/필터/BitsPerComponent/ImageMask를
/// 자유롭게 조합해 적격 규칙 화이트리스트가 각 유형을 올바르게 통과·거부시키는지 검증한다(§2.3).
Uint8List buildSinglePageImagePdf({
  required List<int> streamBytes,
  required int width,
  required int height,
  required String filter, // 예: '/DCTDecode', '/JPXDecode', '/CCITTFaxDecode'
  String? colorSpace, // 예: '/DeviceRGB', '/DeviceGray' -- imageMask면 null로 둔다.
  int bitsPerComponent = 8,
  bool imageMask = false,
  double mediaBoxW = 200,
  double mediaBoxH = 200,
}) {
  final b = RawPdfBuilder();
  final imgId = b.allocId();
  final contentBytes = utf8.encode(_emptyContent);
  final contentId = b.addStream('', contentBytes);
  final csEntry = colorSpace != null ? ' /ColorSpace $colorSpace' : '';
  final maskEntry = imageMask ? ' /ImageMask true' : '';
  b._ids.add(imgId);
  final header = utf8.encode(
    '$imgId 0 obj\n<< /Type /XObject /Subtype /Image /Width $width /Height $height '
    '/BitsPerComponent $bitsPerComponent$csEntry /Filter $filter$maskEntry '
    '/Length ${streamBytes.length} >>\nstream\n',
  );
  b._bodies[imgId] = [...header, ...streamBytes, ...utf8.encode('\nendstream\nendobj\n')];
  final pageId = b.addDict(
    '/Type /Page /Parent 0 0 R /MediaBox [0 0 $mediaBoxW $mediaBoxH] '
    '/Resources << /XObject << /Im0 $imgId 0 R >> >> /Contents $contentId 0 R',
  );
  final pagesId = b.addDict('/Type /Pages /Kids [$pageId 0 R] /Count 1');
  final catalogId = b.addDict('/Type /Catalog /Pages $pagesId 0 R');
  // /Parent는 순환 조립 순서상 pagesId를 미리 알 수 없으므로 페이지 오브젝트를 다시 써야 한다 --
  // addDict가 이미 문자열을 확정해버렸으니, 대신 pagesId를 먼저 예약해 페이지에 정확한 참조를 준다.
  return _fixPageParentAndBuild(b, pageId: pageId, pagesId: pagesId, catalogId: catalogId);
}

/// 같은 이미지 오브젝트를 2개 페이지가 함께 참조하는 PDF(§2.3 dedup 검증: "반복 참조되는 같은
/// 이미지 오브젝트는 1회만 처리").
Uint8List buildTwoPageSharedImagePdf({required List<int> jpegBytes, required int width, required int height}) {
  final b = RawPdfBuilder();
  final imgId = b.addStream(
    '/Type /XObject /Subtype /Image /Width $width /Height $height '
    '/BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode',
    jpegBytes,
  );
  final c1 = b.addStream('', utf8.encode(_emptyContent));
  final c2 = b.addStream('', utf8.encode(_emptyContent));
  final page1 = b.addDict(
    '/Type /Page /Parent 0 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /Im0 $imgId 0 R >> >> /Contents $c1 0 R',
  );
  final page2 = b.addDict(
    '/Type /Page /Parent 0 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /Im0 $imgId 0 R >> >> /Contents $c2 0 R',
  );
  final pagesId = b.addDict('/Type /Pages /Kids [$page1 0 R $page2 0 R] /Count 2');
  final catalogId = b.addDict('/Type /Catalog /Pages $pagesId 0 R');
  return _fixPageParentAndBuild(b, pageId: page1, pagesId: pagesId, catalogId: catalogId, extraPageId: page2);
}

/// 이미지가 페이지의 `/Resources`가 아니라 Form XObject의 `/Resources`에 있는 PDF(§2.3 Form 재귀
/// 순회 검증). Form 자신도 스트림이므로 §8.3 딕셔너리 접근 규칙이 Form에도 적용된다.
Uint8List buildFormNestedImagePdf({required List<int> jpegBytes, required int width, required int height}) {
  final b = RawPdfBuilder();
  final imgId = b.addStream(
    '/Type /XObject /Subtype /Image /Width $width /Height $height '
    '/BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode',
    jpegBytes,
  );
  final formId = b.addStream(
    '/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /XObject << /Im0 $imgId 0 R >> >>',
    utf8.encode(_emptyContent),
  );
  final contentId = b.addStream('', utf8.encode(_emptyContent));
  final pageId = b.addDict(
    '/Type /Page /Parent 0 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /Fm0 $formId 0 R >> >> /Contents $contentId 0 R',
  );
  final pagesId = b.addDict('/Type /Pages /Kids [$pageId 0 R] /Count 1');
  final catalogId = b.addDict('/Type /Catalog /Pages $pagesId 0 R');
  return _fixPageParentAndBuild(b, pageId: pageId, pagesId: pagesId, catalogId: catalogId);
}

/// 서로 다른 이미지 객체를 각자 담은 N페이지 PDF("스캔 문서" 픽스처 -- 페이지 수 == 후보 수 정확
/// 일치 검증용).
Uint8List buildMultiPageImagePdf({required List<List<int>> jpegPagesBytes, required int width, required int height}) {
  final b = RawPdfBuilder();
  final pageIds = <int>[];
  for (final jpeg in jpegPagesBytes) {
    final imgId = b.addStream(
      '/Type /XObject /Subtype /Image /Width $width /Height $height '
      '/BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode',
      jpeg,
    );
    final contentId = b.addStream('', utf8.encode(_emptyContent));
    final pageId = b.addDict(
      '/Type /Page /Parent 0 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /Im0 $imgId 0 R >> >> /Contents $contentId 0 R',
    );
    pageIds.add(pageId);
  }
  final pagesId = b.addDict('/Type /Pages /Kids [${pageIds.map((p) => '$p 0 R').join(' ')}] /Count ${pageIds.length}');
  final catalogId = b.addDict('/Type /Catalog /Pages $pagesId 0 R');
  return _fixPageParentAndBuild(b, pageId: pageIds.first, pagesId: pagesId, catalogId: catalogId, allPageIds: pageIds);
}

/// `addDict`로 이미 확정된 페이지 오브젝트 문자열 속 `/Parent 0 0 R` 자리표시자를 실제 `/Parent
/// <pagesId> 0 R`로 바이트 치환한 뒤 최종 PDF를 조립한다(오브젝트를 조립 순서대로만 추가할 수
/// 있는 [RawPdfBuilder]의 단순함을 유지하기 위한 사후 치환 -- 페이지가 자신의 부모 ID를 알기
/// 전에 문자열이 확정되는 순서 문제를 피한다).
Uint8List _fixPageParentAndBuild(
  RawPdfBuilder b, {
  required int pageId,
  required int pagesId,
  required int catalogId,
  int? extraPageId,
  List<int>? allPageIds,
}) {
  final placeholder = utf8.encode('/Parent 0 0 R');
  final replacement = utf8.encode('/Parent $pagesId 0 R');
  final targets = allPageIds ?? [pageId, if (extraPageId != null) extraPageId];
  for (final id in targets) {
    final body = b._bodies[id]!;
    final idx = _indexOfBytes(body, placeholder);
    if (idx < 0) continue; // 이미 치환됐거나(공유 안 함) 해당 없음.
    b._bodies[id] = [...body.sublist(0, idx), ...replacement, ...body.sublist(idx + placeholder.length)];
  }
  return b.build(rootId: catalogId);
}

int _indexOfBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
