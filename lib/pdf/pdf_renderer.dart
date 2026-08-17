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
}
