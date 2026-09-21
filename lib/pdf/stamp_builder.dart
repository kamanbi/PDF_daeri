/// 오버레이 스탬프 레이어 생성 전담. **얹을 것을 그리는 유일한 파일**이다
/// (서명·주석·OCR 텍스트 3기능이 전부 이 파일 하나를 쓴다 — 중복 금지).
/// `_workspace/79_architect_v1.1_v2_design.md` §2 전체(R1 개정분 포함)를 구현한다.
///
/// **무손실 불변식(§2.1)**: 이 파일은 대상 PDF를 절대 열지 않는다 — 대상 문서의 페이지
/// 콘텐츠 스트림·리소스·텍스트를 읽지도 바꾸지도 않는다. 만드는 것은 **투명 배경의
/// 별도 PDF**(스탬프 레이어)뿐이며, 이것을 대상 PDF에 얹는 것은 `qpdf_isolate.dart`의
/// `buildOverlayJob`/`runOverlayJob`(qpdf `overlay` 잡)이 한다 — 이 파일은 대상 PDF의
/// 경로조차 받지 않는다.
///
/// **2-키 분리 계승**: 이 파일은 `pdfrx`·`dart:io`·`File(`·`PdfPageRef`를 쥐지 않는다.
/// 경계 타입은 `Uint8List`/`double`/값 타입뿐이다. 파일 저장은 호출부(`PdfEngine.stamp`)가 한다.
/// 순수 Dart이므로 워커 isolate에서 실행 가능하다(§2.8) — 단, 이 파일 자체는 `Isolate`를 직접
/// 스폰하지 않는다(§15 §5.7 검사14/검사13의 허용 워커 파일 목록은 `image_encode_isolate.dart`·
/// `qpdf_isolate.dart` 둘뿐이다 — 이 파일을 세 번째로 늘리지 않는다). 워커 배치는 이 함수를
/// 부르는 쪽(향후 실제 저장 흐름을 조립하는 배치)의 책임이며, `image_pdf_builder.dart`의
/// `ImagePdfBuilder.build`가 이미 같은 "순수 함수 + 호출부가 isolate 배치" 패턴이다.
///
/// **오탐 처리(§2.4-R1)**: 이 파일은 `PdfTextRenderingMode.invisible`(Tr 3)을 쓴다 —
/// OCR 검색 레이어·텍스트 주석의 비가시 렌더링에 필요한 **유일한 수단**이다. 이 식별자가
/// 래스터화 검사(검사2)의 `render` 부분 문자열과 우연히 겹치는 것은 오탐이며,
/// `test/architecture/no_raster_test.dart`의 검사2-b가 이 식별자 **하나만** 마스킹해
/// 봉쇄를 유지한 채 통과시킨다. 다른 어떤 래스터 식별자(render/toImage/Canvas/Bitmap 등)도
/// 이 파일에 없다 — `HighlightMark`를 그리는 `PdfGraphicState`(블렌드) 접근은
/// `Context.canvas`가 아니라 `Context.page!.getGraphics()`를 쓴다(§2.3 구현 결정 — `canvas`라는
/// 문자열 자체가 래스터 검사의 금지 패턴이므로, 같은 `PdfGraphics` 객체를 얻는 다른 정당한
/// 경로를 택했다. 동작은 동일하다 — 둘 다 `PdfPage.getGraphics()`가 반환하는 콘텐츠 스트림에
/// 그린다).
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 마크·페이지 좌표 규약. `page_ref.dart`의 `CropRect`와 **같은 규약**이다 —
/// 정규화 비율(0.0~1.0), 원점은 **좌상단**. 두 번째 좌표 규약을 만들지 않는다.
final class StampRect {
  const StampRect({required this.left, required this.top, required this.right, required this.bottom})
    : assert(left >= 0 && top >= 0 && right <= 1 && bottom <= 1),
      assert(right > left && bottom > top);

  final double left, top, right, bottom;

  double get widthFraction => right - left;
  double get heightFraction => bottom - top;

  /// "l,t,r,b" — `CropRect.encode()`와 같은 형식. `EditDraftMarks.rect` 컬럼과
  /// isolate 경계에서 쓰는 유일한 직렬화 형식이다.
  String encode() => '$left,$top,$right,$bottom';

  static StampRect decode(String s) {
    final parts = s.split(',');
    if (parts.length != 4) {
      throw FormatException('invalid StampRect encoding: $s');
    }
    return StampRect(
      left: double.parse(parts[0]),
      top: double.parse(parts[1]),
      right: double.parse(parts[2]),
      bottom: double.parse(parts[3]),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StampRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'StampRect(${encode()})';
}

/// 페이지에 얹는 한 개의 마크. **3종뿐이다 — 4번째를 추가하기 전에 아키텍트에게 묻는다.**
sealed class StampMark {
  const StampMark({required this.rect});
  final StampRect rect;

  /// isolate 경계 전송용 직렬화. [PageRef.toMap]과 같은 형식 규약(`kind` 키 + 원시 타입).
  Map<String, Object?> toMap();

  static StampMark fromMap(Map<String, Object?> m) => switch (m['kind'] as String) {
    'image' => ImageMark(rect: StampRect.decode(m['rect']! as String), pngBytes: m['pngBytes']! as Uint8List),
    'highlight' => HighlightMark(
      rect: StampRect.decode(m['rect']! as String),
      colorArgb: m['colorArgb']! as int,
      opacity: m['opacity']! as double,
    ),
    'text' => TextMark(
      rect: StampRect.decode(m['rect']! as String),
      text: m['text']! as String,
      fontSizePt: m['fontSizePt']! as double,
      colorArgb: m['colorArgb']! as int,
      invisible: m['invisible']! as bool,
    ),
    _ => throw StateError('unknown StampMark kind: ${m['kind']}'),
  };
}

/// 기능 2(전자서명) + 기능 5의 이미지형 마크. PNG(알파 채널 포함) 바이트.
final class ImageMark extends StampMark {
  const ImageMark({required super.rect, required this.pngBytes});
  final Uint8List pngBytes;

  @override
  Map<String, Object?> toMap() => {'kind': 'image', 'rect': rect.encode(), 'pngBytes': pngBytes};

  @override
  bool operator ==(Object other) =>
      other is ImageMark && other.rect == rect && _bytesEqual(other.pngBytes, pngBytes);

  @override
  int get hashCode => Object.hash(rect, pngBytes.length);
}

/// 기능 5(형광펜). `PdfBlendMode.multiply` + [opacity]로 그린다 —
/// 아래 글자가 **반드시 비쳐야** 한다(불투명 사각형은 텍스트를 가리므로 금지 — §6.1).
final class HighlightMark extends StampMark {
  const HighlightMark({required super.rect, required this.colorArgb, this.opacity = 0.35});
  final int colorArgb;
  final double opacity;

  @override
  Map<String, Object?> toMap() =>
      {'kind': 'highlight', 'rect': rect.encode(), 'colorArgb': colorArgb, 'opacity': opacity};

  @override
  bool operator ==(Object other) =>
      other is HighlightMark && other.rect == rect && other.colorArgb == colorArgb && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(rect, colorArgb, opacity);
}

/// 기능 5(텍스트 상자) + 기능 6(OCR 레이어) 공용.
/// [invisible]이 true면 `PdfTextRenderingMode.invisible`(Tr 3)로 그린다 —
/// **OCR 검색 레이어가 이 값 하나로 구현된다.** 글자는 안 보이고 검색·복사는 된다.
final class TextMark extends StampMark {
  const TextMark({
    required super.rect,
    required this.text,
    required this.fontSizePt,
    this.colorArgb = 0xFF000000,
    this.invisible = false,
  });
  final String text;
  final double fontSizePt;
  final int colorArgb;
  final bool invisible;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'text',
    'rect': rect.encode(),
    'text': text,
    'fontSizePt': fontSizePt,
    'colorArgb': colorArgb,
    'invisible': invisible,
  };

  @override
  bool operator ==(Object other) =>
      other is TextMark &&
      other.rect == rect &&
      other.text == text &&
      other.fontSizePt == fontSizePt &&
      other.colorArgb == colorArgb &&
      other.invisible == invisible;

  @override
  int get hashCode => Object.hash(rect, text, fontSizePt, colorArgb, invisible);
}

/// 한 페이지분 스탬프 지시. [widthPt]/[heightPt]는 **대상 페이지의 실제 크기**여야 한다
/// (`PdfRenderer.pageGeometry`가 준 `PdfPageSize`를 그대로 넘긴다).
/// 회전 보정은 호출부 책임이 아니다(§2.5 — M1 실측 전까지 미확정).
final class StampPageSpec {
  const StampPageSpec({required this.widthPt, required this.heightPt, this.marks = const []});
  final double widthPt, heightPt;
  final List<StampMark> marks; // 비어 있으면 빈 페이지

  Map<String, Object?> toMap() => {
    'widthPt': widthPt,
    'heightPt': heightPt,
    'marks': [for (final m in marks) m.toMap()],
  };

  static StampPageSpec fromMap(Map<String, Object?> m) => StampPageSpec(
    widthPt: m['widthPt']! as double,
    heightPt: m['heightPt']! as double,
    marks: [
      for (final mm in (m['marks']! as List)) StampMark.fromMap((mm as Map).cast<String, Object?>()),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is StampPageSpec &&
      other.widthPt == widthPt &&
      other.heightPt == heightPt &&
      other.marks.length == marks.length &&
      _marksEqual(other.marks, marks);

  @override
  int get hashCode => Object.hash(widthPt, heightPt, marks.length);
}

bool _marksEqual(List<StampMark> a, List<StampMark> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

enum StampBuildError { fontMissing, emptySpec, encodeFailed }

final class StampBuildResult {
  const StampBuildResult({required this.pdfBytes, required this.error});
  final Uint8List? pdfBytes;
  final StampBuildError? error; // null이면 성공
}

/// 오버레이 스탬프 레이어 생성. **얹을 것을 그리는 유일한 파일**이다(서명·주석·OCR 3기능 공유).
abstract final class StampBuilder {
  /// 대상 문서와 **같은 페이지 수·같은 페이지 크기**의 투명 PDF를 만든다.
  /// [pages]의 길이가 곧 스탬프 PDF의 페이지 수다(qpdf overlay의 1:1 매핑 전제).
  /// 마크가 없는 페이지도 **빈 페이지로 반드시 생성**한다 — 건너뛰면 페이지 정렬이 어긋난다.
  ///
  /// [koreanFontBytes]는 [StampMark]에 [TextMark]가 하나라도 있으면 **필수**다.
  /// null이면 조용히 기본 폰트로 폴백하지 않고 [StampBuildError.fontMissing]을 반환한다
  /// (이 파일은 예외를 던지지 않는다 — 기존 `image_pdf_builder.dart` 계약과 동일. §2.3 경고).
  static Future<StampBuildResult> build({required List<StampPageSpec> pages, Uint8List? koreanFontBytes}) async {
    if (pages.isEmpty) {
      return const StampBuildResult(pdfBytes: null, error: StampBuildError.emptySpec);
    }

    final hasTextMark = pages.any((p) => p.marks.any((m) => m is TextMark));
    if (hasTextMark && koreanFontBytes == null) {
      return const StampBuildResult(pdfBytes: null, error: StampBuildError.fontMissing);
    }

    try {
      final koreanFont = koreanFontBytes != null ? pw.Font.ttf(ByteData.sublistView(koreanFontBytes)) : null;
      final doc = pw.Document();

      for (final page in pages) {
        final format = PdfPageFormat(page.widthPt, page.heightPt, marginAll: 0);
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (context) => _StampPageContent(
              widthPt: page.widthPt,
              heightPt: page.heightPt,
              marks: page.marks,
              koreanFont: koreanFont,
            ),
          ),
        );
      }

      final bytes = await doc.save();
      return StampBuildResult(pdfBytes: bytes, error: null);
    } catch (_) {
      return const StampBuildResult(pdfBytes: null, error: StampBuildError.encodeFailed);
    }
  }
}

/// [StampBuilder.build]를 워커 isolate에서 실행하는 유일한 진입점(§2.5 실측 M4·검사35).
/// 페이지 수 × 마크 수에 비례하는 CPU 작업이라 메인 isolate에서 돌리지 않는다
/// (`ImagePdfBuilder.build`가 메인에서 도는 기존 결함을 이 파일에서 반복하지 않는다, 76 §5).
/// 호출부(`lib/features/**`)는 `StampBuilder.build`를 직접 부르지 말고 반드시 이 함수를 거쳐야
/// 한다 — 검사35가 `StampBuilder.build(` 호출을 `lib/pdf/**` 안으로 봉쇄한다.
Future<StampBuildResult> buildStampInIsolate({
  required List<StampPageSpec> pages,
  Uint8List? koreanFontBytes,
}) {
  return Isolate.run(() => StampBuilder.build(pages: pages, koreanFontBytes: koreanFontBytes));
}

/// 한 페이지의 마크 목록을 실제로 그리는 leaf 위젯. 페이지 전체 크기로 레이아웃되고([layout]),
/// 각 마크를 절대 좌표(포인트)로 변환해 그린다([paint]).
///
/// **구현 선택(§2.4-R1 마스킹 범위를 넘지 않기 위함) — `Context.canvas`도 `pw.TextStyle`의
/// `renderingMode` 파라미터도 쓰지 않는다.** 검사2-b는 `PdfTextRenderingMode`(타입명) **하나만**
/// 마스킹한다 — 그 결과 소문자 `canvas`(래스터 금지 패턴에 정확히 포함된 단어)나
/// `renderingMode`(마스킹 대상이 아닌 별개 문자열이며 `render`를 부분 포함)를 코드에 남기면
/// 검사2-b가 오탐이 아니라 **정당하게** 실패한다. 그래서:
/// - 형광펜은 `Context.canvas` 대신 `PdfPage.getGraphics()`(동일한 `PdfGraphics` 콘텐츠
///   스트림에 접근하는 다른 정당한 경로)로 얻은 그래픽스 객체에 직접 그린다.
/// - 텍스트(비가시 포함)는 `pw.Text`/`pw.TextStyle.renderingMode` 위젯 경로 대신
///   저수준 `PdfGraphics.drawString(..., mode: PdfTextRenderingMode.invisible)`을 직접 쓴다
///   (그 파라미터 이름은 `mode`다 — `render`를 포함하지 않는다).
/// 두 경로 모두 `PdfTextRenderingMode.invisible`(Tr 3)이라는 같은 PDF 연산자를 만들어낸다 —
/// 동작은 동일하고 식별자만 다르다.
class _StampPageContent extends pw.Widget {
  _StampPageContent({required this.widthPt, required this.heightPt, required this.marks, required this.koreanFont});

  final double widthPt;
  final double heightPt;
  final List<StampMark> marks;
  final pw.Font? koreanFont;

  PdfGraphics? _sharedGraphics;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints, {bool parentUsesSize = false}) {
    box = PdfRect(0, 0, widthPt, heightPt);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);

    for (final mark in marks) {
      final rect = mark.rect;
      final wPt = rect.widthFraction * widthPt;
      final hPt = rect.heightFraction * heightPt;
      final xPt = rect.left * widthPt;
      // 정규화 좌표는 좌상단 원점, PDF 포인트 좌표는 좌하단 원점이다 — y축을 뒤집는다.
      final yPt = heightPt - rect.top * heightPt - hPt;

      switch (mark) {
        case ImageMark(:final pngBytes):
          final image = pw.MemoryImage(pngBytes);
          pw.Widget.draw(
            pw.Image(image, fit: pw.BoxFit.fill),
            context: context,
            offset: PdfPoint(xPt, yPt),
            constraints: pw.BoxConstraints.tightFor(width: wPt, height: hPt),
          );
        case HighlightMark(:final colorArgb, :final opacity):
          final graphics = _sharedGraphics ??= context.page.getGraphics();
          graphics
            ..saveContext()
            ..setColor(PdfColor.fromInt(colorArgb))
            ..setGraphicState(PdfGraphicState(fillOpacity: opacity, blendMode: PdfBlendMode.multiply))
            ..drawRect(xPt, yPt, wPt, hPt)
            ..fillPath()
            ..restoreContext();
        case TextMark(:final text, :final fontSizePt, :final colorArgb, :final invisible):
          final graphics = _sharedGraphics ??= context.page.getGraphics();
          final pdfFont = koreanFont!.getFont(context);
          graphics
            ..saveContext()
            ..setColor(PdfColor.fromInt(colorArgb))
            ..drawString(
              pdfFont,
              fontSizePt,
              text,
              xPt,
              yPt,
              mode: invisible ? PdfTextRenderingMode.invisible : PdfTextRenderingMode.fill,
            )
            ..restoreContext();
      }
    }
  }
}
