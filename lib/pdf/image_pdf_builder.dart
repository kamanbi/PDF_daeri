/// 이미지 인코딩 전담. `package:pdf`·`package:image` 사용 지점 유일(§1.2 파일 소유표).
///
/// 2-키 분리(아키텍트 판정 05_architect_decisions.md Q-A): 이 파일은 PDF 문서·페이지 객체를
/// 쥐지 않는다(`pdfrx*` import 금지) — 이미지 디코드/인코드만 한다. 파일 접근(`dart:io`)도 하지
/// 않는다. 경계 타입은 `Uint8List`/`int`/숫자쌍뿐이다.
///
/// v1은 이미지만 배치한다. **텍스트를 그리지 않는다**(§9.3 결론). 텍스트를 그리는 코드를
/// 추가하는 순간부터는 반드시 [koreanFontBytes]로 등록한 폰트를 써야 하며, 기본 폰트
/// (Helvetica 등 base14)로 한글을 그리는 코드는 작성하지 않는다.
///
/// 순수 Dart라 isolate에서 안전하게 실행 가능하다(§8.1). 폰트 바이트는 인자로만 받는다 —
/// `rootBundle`은 워커 isolate에서 못 쓰므로 이 파일이 직접 에셋을 읽지 않는다(§8.2, §9.2).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'page_ref.dart' show CropRect;

abstract final class ImagePdfBuilder {
  // 저장 경로 프리셋(A-1 유일 소유). `pdf_engine.dart`는 이 상수를 참조만 한다(§3.4 검사 9).
  static const int highLongEdgeMaxPx = 2480;
  static const int highJpegQuality = 85;
  static const int standardLongEdgeMaxPx = 1754;
  static const int standardJpegQuality = 75;
  static const int minLongEdgeMaxPx = 1240;
  static const int minJpegQuality = 60;

  // A4 포인트(1/72inch) 상수. Q-B 판정 — 이 파일 1곳에만 존재.
  static const double _a4ShortPt = 595.276;
  static const double _a4LongPt = 841.890;

  /// [jpegPages]는 이미 인코딩된 JPEG 바이트, 페이지 순서대로.
  ///
  /// [koreanFontBytes]는 v1에서 사용되지 않는다(텍스트를 그리지 않으므로). 향후 텍스트를
  /// 그릴 때를 대비해 시그니처에만 존재한다.
  ///
  /// [title]은 PDF Info 딕셔너리 `/Title`에 한글 원문 그대로 들어간다(§9.3 항목 2, 폰트 불필요).
  ///
  /// 페이지 물리 크기는 [pageBoxFor](A4 박스 내접)로 정한다 -- 워커의 `createFromJpegData`가
  /// 쓰는 것과 같은 함수다(Q-B).
  static Future<Uint8List> build({
    required List<Uint8List> jpegPages,
    required String? title,
    Uint8List? koreanFontBytes,
  }) async {
    final doc = pw.Document(title: title);

    for (final jpeg in jpegPages) {
      final image = pw.MemoryImage(jpeg);
      final box = pageBoxFor(jpeg);
      final format = PdfPageFormat(box.$1, box.$2, marginAll: 0);
      doc.addPage(pw.Page(pageFormat: format, build: (context) => pw.Image(image, fit: pw.BoxFit.fill)));
    }

    return doc.save();
  }

  /// 저장 경로 전용 이미지 재인코딩. 경계 타입은 `Uint8List`/`int`뿐이다 -- 파일을 열지 않는다.
  ///
  /// A-3(세대 손실 봉쇄): 호출자가 항상 `sources/pages/NNN.jpg` 마스터 바이트를 넘긴다는 전제다.
  /// 이 함수는 결과를 어디에도 쓰지 않고 반환만 한다.
  ///
  /// A-4(무손실 우선 스킵): 디코드 전에 JPEG 헤더만 읽어 픽셀 크기를 확인한다.
  /// `max(wPx,hPx) <= longEdgeMaxPx`면 디코드·재인코딩 없이 원본 바이트를 그대로 반환한다.
  /// 판정 기준은 픽셀 크기 하나뿐이다 -- JPEG 품질값 역산은 하지 않는다(부정확하므로).
  ///
  /// A-5(역효과 방지): 재인코딩 결과가 원본 이상이면 원본을 반환한다.
  ///
  /// [crop]이 non-null이면(설계 §1.3/§2.4) **디코드 → 크롭 → 축소 → 인코딩을 한 패스**로 수행한다.
  /// 이 경우 A-4(무손실 스킵)와 A-5(역효과 방지)는 **적용하지 않는다** -- 크롭이 있으면 원본
  /// 바이트를 그대로 쓸 수도, 폴백할 수도 없다(자르지 않은 그림이 들어가거나 크롭이 사라진다).
  /// 세대는 여전히 2세대다(A-3 불변식 유지) -- 입력은 항상 마스터 바이트이고, 크롭 결과는
  /// 어디에도 쓰지 않고 반환만 한다.
  static Uint8List encodeForEmbed(
    Uint8List jpegBytes, {
    required int longEdgeMaxPx,
    required int jpegQuality,
    CropRect? crop,
  }) {
    if (crop == null) {
      final dims = _jpegPixelSize(jpegBytes);
      if (dims == null) {
        // 헤더를 못 읽으면(비 JPEG 등) 원본을 그대로 반환 -- 이 함수는 실패를 던지지 않는다.
        return jpegBytes;
      }
      final longEdge = dims.$1 >= dims.$2 ? dims.$1 : dims.$2;
      if (longEdge <= longEdgeMaxPx) {
        return jpegBytes;
      }

      final decoded = img.decodeJpg(jpegBytes);
      if (decoded == null) return jpegBytes;

      final resized = dims.$1 >= dims.$2
          ? img.copyResize(decoded, width: longEdgeMaxPx)
          : img.copyResize(decoded, height: longEdgeMaxPx);
      final reencoded = Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));

      return reencoded.length < jpegBytes.length ? reencoded : jpegBytes;
    }

    // 크롭 경로: A-4/A-5 둘 다 적용하지 않는다(§2.4). 디코드 실패 시에만 원본을 반환한다
    // (이 함수는 실패를 던지지 않는다는 기존 계약을 유지) -- 그 외에는 항상 재인코딩 결과를 쓴다.
    final decoded = img.decodeJpg(jpegBytes);
    if (decoded == null) return jpegBytes;

    final cropped = _applyCrop(decoded, crop);
    final longEdge = cropped.width >= cropped.height ? cropped.width : cropped.height;
    final resized = longEdge > longEdgeMaxPx
        ? (cropped.width >= cropped.height
              ? img.copyResize(cropped, width: longEdgeMaxPx)
              : img.copyResize(cropped, height: longEdgeMaxPx))
        : cropped;

    return Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
  }

  /// [crop] 정규화 비율(0..1)을 원본 픽셀 좌표로 변환해 잘라낸다. 결과 폭·높이는 최소 1px로
  /// 클램프한다(반올림으로 0px가 되는 극단적인 크롭 방지).
  static img.Image _applyCrop(img.Image image, CropRect crop) {
    final w = image.width;
    final h = image.height;
    final x = (crop.left * w).round().clamp(0, w - 1);
    final y = (crop.top * h).round().clamp(0, h - 1);
    final cw = (crop.widthFraction * w).round().clamp(1, w - x);
    final ch = (crop.heightFraction * h).round().clamp(1, h - y);
    return img.copyCrop(image, x: x, y: y, width: cw, height: ch);
  }

  /// JPEG 픽셀 크기를 A4 박스(내접, 비율 보존) 안의 PDF 포인트(1/72inch) 크기로 변환한다(Q-B).
  /// JFIF density(DPI)는 읽지 않는다 -- 신뢰할 수 없는 메타데이터보다 고정 규칙이 안전하다.
  /// 헤더를 못 읽으면 A4 세로(포트레이트)를 그대로 반환한다.
  ///
  /// [crop]이 있으면 **크롭 후** 픽셀 크기로 내접 계산한다(§2.4) -- 크롭 전 크기로 계산하면
  /// 잘라낸 그림이 원래 종횡비의 박스에 늘어나 들어간다.
  static (double, double) pageBoxFor(Uint8List jpegBytes, {CropRect? crop}) {
    final dims = _jpegPixelSize(jpegBytes);
    if (dims == null) return (_a4ShortPt, _a4LongPt);

    final wPx = crop == null ? dims.$1.toDouble() : dims.$1 * crop.widthFraction;
    final hPx = crop == null ? dims.$2.toDouble() : dims.$2 * crop.heightFraction;
    final portrait = hPx >= wPx;
    final boxW = portrait ? _a4ShortPt : _a4LongPt;
    final boxH = portrait ? _a4LongPt : _a4ShortPt;
    final scaleW = boxW / wPx;
    final scaleH = boxH / hPx;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    return (wPx * scale, hPx * scale);
  }

  /// **공개화(M-E4, `_workspace/31_architect_external_compress_l2.md` §2.6).** JPEG SOF 세그먼트에서
  /// 폭·높이·성분 수(`Nf`, 폭·높이 바로 다음 1바이트)를 함께 읽는다. [_jpegPixelSize]와 같은
  /// 파싱 로직을 그대로 재사용한다 -- 새 파싱 로직이 아니라 이미 읽고 있는 세그먼트에서 1바이트를
  /// 더 반환하는 것뿐이다(§2.6). 계산의 단일 소유는 이 파일 그대로다(중복 없음).
  ///
  /// L2-ext(qpdf 임베디드 이미지 치환, `pdf_compressor.dart`)가 재인코딩 결과의 성분 수를 원본과
  /// 대조해 색공간 불일치(R2)를 걸러내는 데 쓴다. 헤더를 못 읽으면(비 JPEG 등) null.
  static (int width, int height, int components)? jpegPixelSize(Uint8List bytes) => _jpegPixelSizeAndComponents(bytes);

  /// JPEG SOF 마커에서 픽셀 폭·높이를 읽는다. `package:image` 전체 디코드 없이 헤더만 파싱한다
  /// (A-4 스킵 판정이 디코드를 하지 않아야 하므로). 이 파일이 이 계산의 유일한 소유자다
  /// -- `pdf_engine_isolate.dart`에 있던 같은 계산은 중복 금지 위반이라 제거하고 여기로 통합했다.
  /// 기존 호출부(`encodeForEmbed`/`pageBoxFor`)는 그대로 두기 위해 시그니처를 바꾸지 않았다 --
  /// [_jpegPixelSizeAndComponents]에 위임하고 성분 수만 잘라낸다.
  static (int, int)? _jpegPixelSize(Uint8List bytes) {
    final full = _jpegPixelSizeAndComponents(bytes);
    if (full == null) return null;
    return (full.$1, full.$2);
  }

  /// [_jpegPixelSize]/[jpegPixelSize]가 공유하는 실제 파싱 로직. SOF 세그먼트 레이아웃(마커 뒤
  /// `length(2) precision(1) height(2) width(2) Nf(1)`) 중 `height`/`width` 다음 바이트가 `Nf`
  /// (성분 수)다 -- 마커·바이트 오프셋 전부 기존 로직과 동일, 반환 튜플에 항목 하나만 늘었다.
  static (int, int, int)? _jpegPixelSizeAndComponents(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      // SOF0..SOF15, DHT(0xC4)/JPG(0xC8)/DAC(0xCC) 제외.
      final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isSof) {
        final height = (bytes[i + 5] << 8) | bytes[i + 6];
        final width = (bytes[i + 7] << 8) | bytes[i + 8];
        final components = bytes[i + 9];
        return (width, height, components);
      }
      final segmentLength = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + segmentLength;
    }
    return null;
  }
}
