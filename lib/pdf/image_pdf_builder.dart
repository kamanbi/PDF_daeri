/// 이미지 → PDF 생성. `package:pdf` 사용 지점 유일(§1.2 파일 소유표).
///
/// v1은 이미지만 배치한다. **텍스트를 그리지 않는다**(§9.3 결론). 텍스트를 그리는 코드를
/// 추가하는 순간부터는 반드시 [koreanFontBytes]로 등록한 폰트를 써야 하며, 기본 폰트
/// (Helvetica 등 base14)로 한글을 그리는 코드는 작성하지 않는다.
///
/// 순수 Dart(`package:pdf`, `package:image`)라 isolate에서 안전하게 실행 가능하다(§8.1).
/// 폰트 바이트는 인자로만 받는다 — `rootBundle`은 워커 isolate에서 못 쓰므로 이 파일이
/// 직접 에셋을 읽지 않는다(§8.2, §9.2).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

abstract final class ImagePdfBuilder {
  /// [jpegPages]는 이미 인코딩된 JPEG 바이트, 페이지 순서대로.
  ///
  /// [koreanFontBytes]는 v1에서 사용되지 않는다(텍스트를 그리지 않으므로). 향후 텍스트를
  /// 그릴 때를 대비해 시그니처에만 존재한다 — 이 파일이 직접 폰트 파일을 읽지 않는다는
  /// 제약을 지키기 위해 항상 인자로 받는다.
  ///
  /// [title]은 PDF Info 딕셔너리 `/Title`에 한글 원문 그대로 들어간다(§9.3 항목 2, 폰트 불필요).
  ///
  /// 이미지 픽셀 크기를 그대로 PDF 포인트(1/72inch)로 사용한다(1px = 1pt 가정).
  /// [실측 필요]: 스캔 실제 물리 크기 대비 이 가정이 적절한지는 미확정 — 설계 질의 참조.
  static Future<Uint8List> build({
    required List<Uint8List> jpegPages,
    required String? title,
    Uint8List? koreanFontBytes,
  }) async {
    final doc = pw.Document(title: title);

    for (final jpeg in jpegPages) {
      final decoded = img.decodeJpg(jpeg);
      if (decoded == null) {
        throw ArgumentError('jpegPages contains bytes that are not a valid JPEG');
      }
      final image = pw.MemoryImage(jpeg);
      final format = PdfPageFormat(decoded.width.toDouble(), decoded.height.toDouble(), marginAll: 0);
      doc.addPage(pw.Page(pageFormat: format, build: (context) => pw.Image(image, fit: pw.BoxFit.fill)));
    }

    return doc.save();
  }
}
