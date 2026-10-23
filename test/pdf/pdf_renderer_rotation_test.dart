// 페이지 편집 그리드 썸네일이 회전을 반영하는지 확인한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pdfpkg;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';

void main() {
  late Directory root;
  late PdfxRenderer renderer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_daeri_rotation_');
    renderer = PdfxRenderer();
  });

  tearDown(() {
    renderer.evictCache();
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {
      // Windows에서 pdfium이 파일을 잡고 있으면 임시 폴더 삭제가 실패할 수 있다.
    }
  });

  Future<img.Image> render(PageRef page) async {
    final result = await renderer.renderPageThumbnail(page: page, targetWidthPx: 120);
    expect(result, isA<PdfOk>(), reason: '렌더 실패: $result');
    return img.decodePng((result as PdfOk).value as dynamic)!;
  }

  test('PDF 페이지: 90도 회전하면 세로 페이지가 가로로 나온다', () async {
    final doc = pw.Document()
      ..addPage(pw.Page(pageFormat: pdfpkg.PdfPageFormat.a4, build: (_) => pw.Center(child: pw.Text('A'))));
    final path = '${root.path}/a4.pdf';
    await File(path).writeAsBytes(await doc.save());

    final r0 = await render(PdfPageRef(sourcePath: path, sourceIndex: 0, rotation: 0));
    final r90 = await render(PdfPageRef(sourcePath: path, sourceIndex: 0, rotation: 90));

    expect(r0.height, greaterThan(r0.width));
    expect(r90.width, greaterThan(r90.height), reason: '회전이 썸네일에 반영되지 않음');
  });

  test('사진 페이지: 90도 회전하면 세로 사진이 가로로 나온다', () async {
    // 위쪽 절반은 빨강, 아래쪽 절반은 파랑 -- 시계방향 90도면 빨강이 오른쪽으로 간다.
    final src = img.Image(width: 200, height: 400);
    img.fill(src, color: img.ColorRgb8(30, 30, 200));
    img.fillRect(src, x1: 0, y1: 0, x2: 199, y2: 199, color: img.ColorRgb8(200, 30, 30));
    final path = '${root.path}/tall.png';
    await File(path).writeAsBytes(img.encodePng(src));

    final r0 = await render(ImagePageRef(imagePath: path, rotation: 0));
    final r90 = await render(ImagePageRef(imagePath: path, rotation: 90));

    expect(r0.height, greaterThan(r0.width));
    expect(r90.width, greaterThan(r90.height), reason: '사진 썸네일에 회전이 반영되지 않음');
    final right = r90.getPixel(r90.width - 10, r90.height ~/ 2);
    final left = r90.getPixel(10, r90.height ~/ 2);
    expect(right.r, greaterThan(right.b), reason: '시계방향이면 위쪽(빨강)이 오른쪽에 와야 한다');
    expect(left.b, greaterThan(left.r));

    final r180 = await render(ImagePageRef(imagePath: path, rotation: 180));
    expect(r180.height, greaterThan(r180.width));
    final top = r180.getPixel(r180.width ~/ 2, 10);
    expect(top.b, greaterThan(top.r), reason: '180도면 아래쪽(파랑)이 위로 와야 한다');
  });
}
