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

class PdfxRenderer implements PdfRenderer {
  PdfxRenderer();

  final Map<String, pdfrx.PdfDocument> _openDocs = {};

  Future<pdfrx.PdfDocument> _open(String path, {String? password}) async {
    final key = '$path|${password ?? ''}';
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
        return _renderImageFileToPng(page.imagePath, targetWidthPx: targetWidthPx);
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

  Future<PdfResult<Uint8List>> _renderImageFileToPng(String imagePath, {required int targetWidthPx}) async {
    try {
      final file = await ui.ImmutableBuffer.fromFilePath(imagePath);
      final descriptor = await ui.ImageDescriptor.encoded(file);
      final codec = await descriptor.instantiateCodec(targetWidth: targetWidthPx);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      file.dispose();
      if (byteData == null) return PdfErr(const UnknownFailure('png encode failed'));
      return PdfOk(byteData.buffer.asUint8List());
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
    final key = '$pdfPath|${password ?? ''}';
    final doc = _openDocs.remove(key);
    doc?.dispose();
  }
}
