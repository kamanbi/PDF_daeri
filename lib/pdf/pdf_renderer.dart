/// 페이지 렌더·썸네일 (UI 전용). §2.4.
///
/// 이 클래스의 출력은 **어떤 경우에도 저장 경로로 흘러가지 않는다**. 반환 타입이 파일 경로가
/// 아니라 메모리 바이트인 이유가 그것이다(§3.2). `pdf_engine.dart`·`data/repository/**`는
/// import하지 않는다 — 렌더 결과가 저장 경로로 새어 들어가는 문법적 경로 자체가 없다.
///
/// `dart:ui`는 여기서만 허용된다: PDFium이 만든 원시 픽셀(BGRA)을 PNG로 인코딩하는 용도이며,
/// PDF 콘텐츠를 편집·저장하는 데 쓰이지 않는다.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../core/app_error.dart';
import '../core/cancel_token.dart';
import 'page_ref.dart';

abstract interface class PdfRenderer {
  Future<PdfResult<int>> openPageCount(String pdfPath, {String? password});

  /// 페이지 1장을 화면 표시용 비트맵으로 렌더한다.
  /// 반환은 PNG 인코딩된 메모리 바이트. 파일로 쓰지 않는다.
  Future<PdfResult<Uint8List>> renderPage({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
    CancelToken? cancelToken,
  });

  /// 문서 대표 썸네일(목록용). `thumbs/<docId>.jpg`로 쓰는 주체는 Repository다.
  Future<PdfResult<Uint8List>> renderThumbnail({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
  });

  /// 편집 화면 그리드용 지연 로딩 썸네일. cache/ 캐시 키를 함께 반환한다.
  Future<PdfResult<Uint8List>> renderPageThumbnail({
    required PageRef page,
    required int targetWidthPx,
    CancelToken? cancelToken,
  });

  void evictCache();

  /// 문서의 모든 페이지 기하 정보를 한 번에 얻는다. **픽셀을 만들지 않는다** —
  /// 페이지 dict의 MediaBox/Rotate만 읽으므로 대용량 문서에서도 렌더 없이 끝난다.
  ///
  /// 뷰어가 페이지를 렌더하기 **전에** 종횡비를 알아 자리를 잡기 위한 것이다.
  ///
  /// 반환의 [PdfPageGeometry.sizes] 길이는 항상 [PdfPageGeometry.pageCount]와 같다.
  Future<PdfResult<PdfPageGeometry>> pageGeometry(String pdfPath, {String? password});

  /// 특정 문서의 핸들만 닫는다. [password]까지 일치해야 같은 핸들로 취급한다
  /// (구현의 캐시 키가 `path|password`이므로).
  ///
  /// 뷰어 이탈 시 호출한다. **`evictCache()`를 뷰어에서 호출하지 않는다** —
  /// 그것은 열린 문서를 전부 닫아 홈 그리드의 썸네일 생성까지 무효화한다.
  void evictDocument(String pdfPath, {String? password});

  /// 페이지 [pageIndex](0-base)의 텍스트와 글자별 사각형.
  /// 좌표는 **페이지 좌상단 원점, 포인트 단위, y 아래로 증가**로 정규화해 돌려준다
  /// (PDFium의 좌하단 원점 좌표계 변환은 이 메서드 구현 안에서만 한다).
  /// 텍스트가 없는 페이지(순수 이미지 스캔, OCR 전)는 `text == ''`인 `PdfOk`를 반환한다.
  ///
  /// **읽기 전용** — 문서를 수정하거나 저장하지 않는다. 이 결과가 저장 경로
  /// (`pdf_engine.dart`)로 흘러가는 코드 경로는 존재하지 않는다.
  Future<PdfResult<PdfPageTextData>> pageText({
    required String pdfPath,
    required int pageIndex,
    String? password,
    CancelToken? cancelToken,
  });
}

/// 페이지 텍스트 + 글자별 사각형의 직렬화 가능한 순수 값 객체(향후 isolate 이동 대비).
/// `pdfrx` 타입(`PdfPageText`, `PdfRect`)을 담지 않는다 — 라이브러리 교체 가능성 유지(§3.2 타입 봉쇄와 동일 원칙).
class PdfPageTextData {
  const PdfPageTextData({required this.pageIndex, required this.text, required this.charRects});

  final int pageIndex;
  final String text;

  /// `text.length`와 같은 길이. 각 원소는 페이지 좌상단 원점, y 아래로 증가하는 포인트 좌표.
  final List<ui.Rect> charRects;

  /// [start, end) 범위(`text` 기준, end 미포함)를 줄 단위로 병합한 사각형 목록(하이라이트용).
  /// 세로 위치가 겹치는 글자들을 같은 줄로 묶어 각 줄을 하나의 사각형으로 합친다.
  List<ui.Rect> rectsFor(int start, int end) {
    final s = start.clamp(0, charRects.length);
    final e = end.clamp(0, charRects.length);
    if (s >= e) return const [];

    final result = <ui.Rect>[];
    ui.Rect? lineRect;
    for (var i = s; i < e; i++) {
      final r = charRects[i];
      if (r.isEmpty) continue;
      if (lineRect == null) {
        lineRect = r;
        continue;
      }
      // 세로 범위가 겹치면(대략 같은 줄) 확장, 아니면 줄바꿈으로 보고 새 줄 시작.
      final overlaps = r.top < lineRect.bottom && r.bottom > lineRect.top;
      if (overlaps) {
        lineRect = lineRect.expandToInclude(r);
      } else {
        result.add(lineRect);
        lineRect = r;
      }
    }
    if (lineRect != null) result.add(lineRect);
    return result;
  }

  /// 포인트 좌표 [p]에 가장 가까운 글자 인덱스. 텍스트가 없거나 [slopPt] 이내에 글자가 없으면 null.
  int? hitTest(ui.Offset p, {double slopPt = 6}) {
    int? bestIndex;
    double bestDistanceSq = double.infinity;
    for (var i = 0; i < charRects.length; i++) {
      final r = charRects[i];
      if (r.isEmpty) continue;
      if (r.contains(p)) return i;
      final dx = p.dx < r.left ? (r.left - p.dx) : (p.dx > r.right ? (p.dx - r.right) : 0.0);
      final dy = p.dy < r.top ? (r.top - p.dy) : (p.dy > r.bottom ? (p.dy - r.bottom) : 0.0);
      final distanceSq = dx * dx + dy * dy;
      if (distanceSq < bestDistanceSq) {
        bestDistanceSq = distanceSq;
        bestIndex = i;
      }
    }
    if (bestIndex == null || bestDistanceSq > slopPt * slopPt) return null;
    return bestIndex;
  }
}

/// 페이지 기하 정보. 픽셀이 아니라 **치수만** 담는다 — 이 타입에 바이트가 들어가는
/// 순간 저장 경로로 새어 나갈 표면이 생긴다(§3.2 타입 봉쇄).
class PdfPageGeometry {
  const PdfPageGeometry({required this.pageCount, required this.sizes});
  final int pageCount;
  final List<PdfPageSize> sizes; // 0-base, 길이 == pageCount
}

class PdfPageSize {
  const PdfPageSize({required this.widthPt, required this.heightPt});

  /// **표시 기준** 치수(pt). 원본 `/Rotate`가 이미 반영된 값이다 —
  /// 90/270도 회전 페이지는 폭·높이가 뒤바뀐 상태로 들어온다.
  final double widthPt;
  final double heightPt;

  /// 0 이하면 1.0으로 대체한다(방어). 뷰어가 0으로 나누지 않게 한다.
  double get aspectRatio => (widthPt <= 0 || heightPt <= 0) ? 1.0 : widthPt / heightPt;
}

/// 비밀번호 원문 대신 캐시·프로바이더 키에 쓰는 64비트 토큰(FNV-1a 변형 2개를 이어 붙임).
/// 새 의존성(crypto) 없이 32비트 `hashCode` 단독 사용 대비 충돌 확률을 2^-64 수준으로 낮춘다.
/// 암호학적 해시는 아니다 — 키 충돌 방지용이며 비밀번호 복원 방어 용도가 아니다.
String pdfPasswordToken(String? password) {
  if (password == null) return '';
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193 ^ 0x5bd1e995;
  for (final unit in password.codeUnits) {
    h1 = ((h1 ^ unit) * 0x01000193) & 0xffffffff;
    h2 = ((h2 ^ (unit + 0x9e37)) * 0x85ebca6b) & 0xffffffff;
  }
  return '${h1.toRadixString(16)}-${h2.toRadixString(16)}-${password.length}';
}

class PdfxRenderer implements PdfRenderer {
  PdfxRenderer();

  final Map<String, pdfrx.PdfDocument> _openDocs = {};

  /// 캐시 키에 비밀번호 원문을 담지 않는다(재감사 M-2) — 이 캐시는 앱 전체 수명 동안
  /// 메모리에 남으므로 원문 대신 64비트 결정적 해시 토큰을 쓴다([pdfPasswordToken]).
  String _passwordCacheToken(String? password) => pdfPasswordToken(password);

  /// `pageText` 결과 캐시. 키는 `path|passwordHash|pageIndex`(비밀번호 원문을 키에 담지 않는다 —
  /// 재감사 M-2). `evictDocument`에서 문서별로 함께 제거하고, 앱 전체 수명 캐시라 무제한 증가를
  /// 막기 위해 [_pageTextCacheLimit] 건을 넘으면 가장 오래된 항목부터 제거한다(삽입 순서 기반
  /// 근사 FIFO — `LinkedHashMap`인 `Map` 리터럴의 반복 순서를 그대로 쓴다).
  final Map<String, PdfPageTextData> _pageTextCache = {};
  static const int _pageTextCacheLimit = 200;

  Future<pdfrx.PdfDocument> _open(String path, {String? password}) async {
    final key = '$path|${_passwordCacheToken(password)}';
    final cached = _openDocs[key];
    if (cached != null) return cached;
    final doc = await pdfrx.PdfDocument.openFile(
      path,
      passwordProvider: password == null ? null : pdfrx.createSimplePasswordProvider(password),
    );
    _openDocs[key] = doc;
    return doc;
  }

  @override
  Future<PdfResult<int>> openPageCount(String pdfPath, {String? password}) async {
    try {
      final doc = await _open(pdfPath, password: password);
      return PdfOk(doc.pages.length);
    } on pdfrx.PdfPasswordException {
      return PdfErr(SourceEncrypted(pdfPath));
    } on pdfrx.PdfException catch (e) {
      return PdfErr(SourceCorrupted(e.message));
    } catch (e) {
      return PdfErr(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<PdfResult<Uint8List>> renderPage({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
    CancelToken? cancelToken,
  }) async {
    try {
      final doc = await _open(pdfPath, password: password);
      if (pageIndex < 0 || pageIndex >= doc.pages.length) {
        return PdfErr(UnknownFailure('pageIndex out of range'));
      }
      final page = doc.pages[pageIndex];
      return await _renderPdfPageToPng(page, rotationDelta: 0, targetWidthPx: targetWidthPx);
    } on pdfrx.PdfPasswordException {
      return PdfErr(SourceEncrypted(pdfPath));
    } on pdfrx.PdfException catch (e) {
      return PdfErr(SourceCorrupted(e.message));
    } catch (e) {
      return PdfErr(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<PdfResult<Uint8List>> renderThumbnail({
    required String pdfPath,
    required int pageIndex,
    required int targetWidthPx,
    String? password,
  }) => renderPage(pdfPath: pdfPath, pageIndex: pageIndex, targetWidthPx: targetWidthPx, password: password);

  @override
  Future<PdfResult<Uint8List>> renderPageThumbnail({
    required PageRef page,
    required int targetWidthPx,
    CancelToken? cancelToken,
  }) async {
    switch (page) {
      case ImagePageRef():
        return _renderImageFileToPng(page.imagePath, targetWidthPx: targetWidthPx, crop: page.crop);
      case PdfPageRef():
        try {
          final doc = await _open(page.sourcePath);
          if (page.sourceIndex < 0 || page.sourceIndex >= doc.pages.length) {
            return PdfErr(UnknownFailure('sourceIndex out of range'));
          }
          final sourcePage = doc.pages[page.sourceIndex];
          return await _renderPdfPageToPng(sourcePage, rotationDelta: page.rotation, targetWidthPx: targetWidthPx);
        } on pdfrx.PdfPasswordException {
          return PdfErr(SourceEncrypted(page.sourcePath));
        } on pdfrx.PdfException catch (e) {
          return PdfErr(SourceCorrupted(e.message));
        } catch (e) {
          return PdfErr(UnknownFailure(e.toString()));
        }
    }
  }

  Future<PdfResult<Uint8List>> _renderPdfPageToPng(
    pdfrx.PdfPage page, {
    required int rotationDelta,
    required int targetWidthPx,
  }) async {
    final steps = rotationDelta ~/ 90;
    final swap = steps.isOdd;
    final baseW = swap ? page.height : page.width;
    final baseH = swap ? page.width : page.height;
    if (baseW <= 0) return PdfErr(const UnknownFailure('invalid page dimensions'));

    final fullWidth = targetWidthPx.toDouble();
    final fullHeight = (targetWidthPx * baseH / baseW);

    final effectiveRotation = pdfrx.PdfPageRotation.values[(page.rotation.index + steps) % 4];
    final image = await page.render(fullWidth: fullWidth, fullHeight: fullHeight, rotationOverride: effectiveRotation);
    if (image == null) return PdfErr(const UnknownFailure('render returned null'));
    try {
      return PdfOk(await _pixelsToPng(image.pixels, image.width, image.height));
    } finally {
      image.dispose();
    }
  }

  /// [crop]이 있으면(설계 §2.5) 원본 해상도로 디코드한 뒤 크롭 영역만 잘라 목표 폭으로
  /// 리사이즈한다 -- 저장 경로(`image_pdf_builder.dart`)와 달리 여기는 `dart:ui`만 쓴다
  /// (2-키 분리: `package:image`는 이 파일에 들어오지 않는다). 이 렌더 결과는 화면 표시용
  /// 메모리 바이트일 뿐 어디에도 쓰이지 않는다(§3.2 타입 봉쇄 -- 저장 경로에 영향 없음).
  Future<PdfResult<Uint8List>> _renderImageFileToPng(
    String imagePath, {
    required int targetWidthPx,
    CropRect? crop,
  }) async {
    try {
      final file = await ui.ImmutableBuffer.fromFilePath(imagePath);
      final descriptor = await ui.ImageDescriptor.encoded(file);

      if (crop == null) {
        final codec = await descriptor.instantiateCodec(targetWidth: targetWidthPx);
        final frame = await codec.getNextFrame();
        final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        descriptor.dispose();
        file.dispose();
        if (byteData == null) return PdfErr(const UnknownFailure('png encode failed'));
        return PdfOk(byteData.buffer.asUint8List());
      }

      final fullCodec = await descriptor.instantiateCodec();
      final fullFrame = await fullCodec.getNextFrame();
      final fullImage = fullFrame.image;
      try {
        final srcW = fullImage.width.toDouble();
        final srcH = fullImage.height.toDouble();
        final srcRect = ui.Rect.fromLTRB(
          crop.left * srcW,
          crop.top * srcH,
          crop.right * srcW,
          crop.bottom * srcH,
        );
        final dstW = targetWidthPx.toDouble();
        final dstH = srcRect.width <= 0 ? dstW : dstW * srcRect.height / srcRect.width;
        final dstWInt = dstW.round().clamp(1, 1 << 20);
        final dstHInt = dstH.round().clamp(1, 1 << 20);

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, dstWInt.toDouble(), dstHInt.toDouble()));
        canvas.drawImageRect(
          fullImage,
          srcRect,
          ui.Rect.fromLTWH(0, 0, dstWInt.toDouble(), dstHInt.toDouble()),
          ui.Paint(),
        );
        final picture = recorder.endRecording();
        final croppedImage = await picture.toImage(dstWInt, dstHInt);
        try {
          final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
          if (byteData == null) return PdfErr(const UnknownFailure('png encode failed'));
          return PdfOk(byteData.buffer.asUint8List());
        } finally {
          croppedImage.dispose();
          picture.dispose();
        }
      } finally {
        fullImage.dispose();
        fullCodec.dispose();
        descriptor.dispose();
        file.dispose();
      }
    } catch (e) {
      return PdfErr(SourceCorrupted('$imagePath: $e'));
    }
  }

  Future<Uint8List> _pixelsToPng(Uint8List bgraPixels, int width, int height) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bgraPixels, width, height, ui.PixelFormat.bgra8888, completer.complete);
    final uiImage = await completer.future;
    try {
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } finally {
      uiImage.dispose();
    }
  }

  @override
  void evictCache() {
    for (final doc in _openDocs.values) {
      doc.dispose();
    }
    _openDocs.clear();
  }

  @override
  Future<PdfResult<PdfPageGeometry>> pageGeometry(String pdfPath, {String? password}) async {
    try {
      final doc = await _open(pdfPath, password: password);
      final sizes = [for (final page in doc.pages) PdfPageSize(widthPt: page.width, heightPt: page.height)];
      return PdfOk(PdfPageGeometry(pageCount: doc.pages.length, sizes: sizes));
    } on pdfrx.PdfPasswordException {
      return PdfErr(SourceEncrypted(pdfPath));
    } on pdfrx.PdfException catch (e) {
      return PdfErr(SourceCorrupted(e.message));
    } catch (e) {
      return PdfErr(UnknownFailure(e.toString()));
    }
  }

  @override
  void evictDocument(String pdfPath, {String? password}) {
    final key = '$pdfPath|${_passwordCacheToken(password)}';
    final doc = _openDocs.remove(key);
    doc?.dispose();
    final textCachePrefix = '$key|';
    _pageTextCache.removeWhere((k, _) => k.startsWith(textCachePrefix));
  }

  @override
  Future<PdfResult<PdfPageTextData>> pageText({
    required String pdfPath,
    required int pageIndex,
    String? password,
    CancelToken? cancelToken,
  }) async {
    final cacheKey = '$pdfPath|${_passwordCacheToken(password)}|$pageIndex';
    final cached = _pageTextCache[cacheKey];
    if (cached != null) return PdfOk(cached);

    try {
      final doc = await _open(pdfPath, password: password);
      if (pageIndex < 0 || pageIndex >= doc.pages.length) {
        return PdfErr(UnknownFailure('pageIndex out of range'));
      }
      final page = doc.pages[pageIndex];
      final pageText = await page.loadStructuredText();

      // PDFium 좌표계(좌하단 원점, y 위로 증가) → 표시 좌표계(좌상단 원점, y 아래로 증가).
      // page.height는 표시 기준 치수(§ PdfPageGeometry 주석과 동일 원칙, `/Rotate` 반영됨).
      final charRects = [
        for (final r in pageText.charRects)
          ui.Rect.fromLTRB(r.left, page.height - r.top, r.right, page.height - r.bottom),
      ];

      final data = PdfPageTextData(pageIndex: pageIndex, text: pageText.fullText, charRects: charRects);
      if (_pageTextCache.length >= _pageTextCacheLimit) {
        _pageTextCache.remove(_pageTextCache.keys.first);
      }
      _pageTextCache[cacheKey] = data;
      return PdfOk(data);
    } on pdfrx.PdfPasswordException {
      return PdfErr(SourceEncrypted(pdfPath));
    } on pdfrx.PdfException catch (e) {
      return PdfErr(SourceCorrupted(e.message));
    } catch (e) {
      return PdfErr(UnknownFailure(e.toString()));
    }
  }
}
