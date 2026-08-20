// T2 크롭 지원 검증 -- `_workspace/36_architect_week3_design.md` §1.2~§1.3(encodeForEmbed/pageBoxFor
// 크롭), §2.4(A-4/A-5 조건부 개정), §2.5(ImageEncodeItem/_saveCompose 배선),
// `renderPageThumbnail` 크롭 반영.
//
// 3계층으로 나눈다:
//   1. `ImagePdfBuilder.encodeForEmbed`/`pageBoxFor` 순수 함수 단위 테스트 (크롭 좌표 -> 픽셀 변환,
//      A-4/A-5 우회 확인) -- FFI 불필요.
//   2. `QpdfPdfEngine.save` RO 테스트: 크롭된 `ImagePageRef`를 실제로 저장하고 재오픈해
//      **크롭 영역만** 보이는지 확인 -- 이미지 전용(qpdf 미사용) 경로와 혼합(qpdf compose) 경로
//      둘 다 커버. Windows `test/native/qpdf30.dll` 필요.
//   3. `PdfxRenderer.renderPageThumbnail`이 `ImagePageRef.crop`을 반영해 크롭된 영역만 그리는지.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/image_pdf_builder.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => '${Directory.current.path}/$_dllRelPath';
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();
final _ffiSkip = !_canRunFfi ? 'Windows qpdf30.dll 필요' : false;

/// 2x2 사분면을 서로 다른 뚜렷한 색으로 채운 JPEG. 사분면 경계가 크롭 경계와 겹치게 해
/// "크롭이 실제로 다른 사분면 색을 섞어 넣었는지"를 픽셀 색으로 판정할 수 있게 한다.
/// 순서: 좌상 TL, 우상 TR, 좌하 BL, 우하 BR.
const _tl = (230, 25, 75); // 빨강 계열
const _tr = (60, 180, 75); // 초록 계열
const _bl = (0, 130, 200); // 파랑 계열
const _br = (245, 130, 48); // 주황 계열

Uint8List _quadrantJpeg(int size) {
  final image = img.Image(width: size, height: size);
  final half = size ~/ 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final (r, g, b) = x < half ? (y < half ? _tl : _bl) : (y < half ? _tr : _br);
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// [decoded] 이미지의 중심 픽셀이 [expected]와 허용오차(±40, JPEG 재인코딩 손실 흡수) 이내인지.
void _expectCenterColor(img.Image decoded, (int, int, int) expected, {String? reason}) {
  final cx = decoded.width ~/ 2;
  final cy = decoded.height ~/ 2;
  final pixel = decoded.getPixel(cx, cy);
  const tolerance = 40;
  expect(pixel.r, closeTo(expected.$1, tolerance), reason: '$reason (R채널)');
  expect(pixel.g, closeTo(expected.$2, tolerance), reason: '$reason (G채널)');
  expect(pixel.b, closeTo(expected.$3, tolerance), reason: '$reason (B채널)');
}

Future<void> _expectPdfrxDominantColor(pdfrx.PdfPage page, (int, int, int) expected, {String? reason}) async {
  final rendered = await page.render(fullWidth: 32, fullHeight: 32);
  expect(rendered, isNotNull, reason: '렌더 실패: $reason');
  final image = rendered!;
  try {
    final pixels = image.pixels; // bgra8888
    final cx = image.width ~/ 2;
    final cy = image.height ~/ 2;
    final idx = (cy * image.width + cx) * 4;
    final b = pixels[idx];
    final g = pixels[idx + 1];
    final r = pixels[idx + 2];
    const tolerance = 40;
    expect(r, closeTo(expected.$1, tolerance), reason: '$reason (R채널)');
    expect(g, closeTo(expected.$2, tolerance), reason: '$reason (G채널)');
    expect(b, closeTo(expected.$3, tolerance), reason: '$reason (B채널)');
  } finally {
    image.dispose();
  }
}

void main() {
  group('1. encodeForEmbed(crop:) / pageBoxFor(crop:) 순수 함수', () {
    test('crop == null이면 기존 동작 그대로(A-4 스킵) -- 회귀 방어', () {
      final original = _quadrantJpeg(400);
      final result = ImagePdfBuilder.encodeForEmbed(original, longEdgeMaxPx: 1000, jpegQuality: 50);
      expect(identical(result, original), isTrue, reason: 'crop 없음 + 상한 이하는 A-4가 그대로 적용돼야 한다');
    });

    test('crop != null이면 크롭 영역만 남기고 나머지 사분면 색은 사라진다(디코드-크롭-축소-인코딩 한 패스)', () {
      final original = _quadrantJpeg(400);
      // 좌상단(TL) 사분면만 남긴다.
      const crop = CropRect(left: 0, top: 0, right: 0.5, bottom: 0.5);
      final result = ImagePdfBuilder.encodeForEmbed(original, longEdgeMaxPx: 1000, jpegQuality: 90, crop: crop);
      expect(identical(result, original), isFalse, reason: '크롭이 있으면 반드시 재인코딩해야 한다(원본을 그대로 반환하면 안 됨)');

      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 200, reason: '크롭 후 픽셀 폭은 원본의 절반이어야 한다(리사이즈 없음, 상한 이하)');
      expect(decoded.height, 200);
      _expectCenterColor(decoded, _tl, reason: '크롭 결과 중심 픽셀은 TL 사분면 색이어야 한다');
    });

    test('A-4는 crop != null이면 적용되지 않는다 -- 크롭 후 크기가 상한 이하여도 반드시 재인코딩된다', () {
      final original = _quadrantJpeg(400);
      const crop = CropRect(left: 0, top: 0, right: 0.5, bottom: 0.5); // 크롭 후 200x200, 상한(1000)보다 훨씬 작음
      final result = ImagePdfBuilder.encodeForEmbed(original, longEdgeMaxPx: 1000, jpegQuality: 90, crop: crop);
      expect(result.length, isNot(original.length), reason: 'A-4가 크롭 케이스에도 적용되면 원본과 같은 바이트가 나올 것이다');
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 200, reason: 'A-4 스킵이 잘못 적용되면 크롭 없이 원본 400px 그대로 나왔을 것이다');
    });

    test('A-5는 crop != null이면 적용되지 않는다 -- 재인코딩 결과가 커져도 원본(미크롭)으로 폴백하지 않는다', () {
      // 노이즈 이미지를 초저품질로 저장한 원본은 매우 작다. 크롭 후 고품질로 재인코딩하면
      // 노이즈 특성상 원본보다 커질 수 있다 -- A-5가 발동하면 안 된다는 것을 폭(크롭됐다는 사실)으로 확인한다.
      const size = 400;
      final rand = Random(7);
      final noiseImage = img.Image(width: size, height: size);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          noiseImage.setPixelRgb(x, y, rand.nextInt(256), rand.nextInt(256), rand.nextInt(256));
        }
      }
      final tinyOriginal = Uint8List.fromList(img.encodeJpg(noiseImage, quality: 1));
      const crop = CropRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75);
      final result = ImagePdfBuilder.encodeForEmbed(tinyOriginal, longEdgeMaxPx: 4000, jpegQuality: 100, crop: crop);

      // A-5가 잘못 적용됐다면 원본(미크롭, 400x400)이 그대로 반환됐을 것이다.
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 200, reason: 'A-5가 크롭 케이스에 잘못 적용되면 크롭 없는 원본이 반환돼 폭이 400이었을 것이다');
    });

    test('pageBoxFor(crop:)는 크롭 후 픽셀 크기로 A4 내접 계산한다', () {
      final jpeg = _quadrantJpeg(400); // 정사각 400x400
      const crop = CropRect(left: 0, top: 0, right: 1, bottom: 0.5); // 400 x 200 (가로가 긴 크롭)
      final boxNoCrop = ImagePdfBuilder.pageBoxFor(jpeg);
      final boxCropped = ImagePdfBuilder.pageBoxFor(jpeg, crop: crop);

      // 크롭 없음: 정사각 -> 세로 박스 폭에 내접(기존 규칙, 정사각형 결과).
      expect(boxNoCrop.$1, closeTo(boxNoCrop.$2, 0.01));

      // 크롭 있음: 2:1 가로가 긴 직사각형 -> 종횡비가 보존돼야 한다.
      expect(boxCropped.$1 / boxCropped.$2, closeTo(2.0, 0.01), reason: '크롭 후 종횡비(400:200=2:1)가 보존돼야 한다');
      expect(boxCropped.$1, isNot(closeTo(boxNoCrop.$1, 1)), reason: '크롭 전 크기로 계산했다면 정사각 박스가 나왔을 것이다');
    });
  });

  group('2. QpdfPdfEngine.save RO -- 크롭된 결과를 재오픈해 크롭 영역만 보이는지', () {
    late Directory root;
    late QpdfPdfEngine engine;

    setUp(() {
      root = Directory.systemTemp.createTempSync('pdf_daeri_crop_save_');
      engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _canRunFfi ? _dllPath : null);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    const generousGuard = GuardInput(op: SaveOp.compose, baselineBytes: 1 << 30);

    test('이미지 전용(qpdf 미사용 fast path) + 크롭 -- 결과 페이지는 크롭한 사분면 색만 보인다', () async {
      final stagingDir = Directory('${root.path}/docs/case1.tmp')..createSync(recursive: true);
      final outputPath = '${stagingDir.path}/document.pdf';
      final imagesDir = Directory('${stagingDir.path}/sources/pages')..createSync(recursive: true);
      final imgPath = '${imagesDir.path}/000.jpg';
      await File(imgPath).writeAsBytes(_quadrantJpeg(400));

      // 우하단(BR) 사분면만 남긴다.
      const crop = CropRect(left: 0.5, top: 0.5, right: 1, bottom: 1);
      final pages = [ImagePageRef(imagePath: imgPath, rotation: 0, crop: crop)];

      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.high,
        guardInput: generousGuard,
      );
      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, 1, reason: 'RO-1 페이지 수 불일치');
        await _expectPdfrxDominantColor(doc.pages[0], _br, reason: '크롭한 BR 사분면 색이어야 한다(다른 사분면이 섞이면 안 됨)');
      } finally {
        await doc.dispose();
      }
    }, skip: _ffiSkip);

    test('혼합(qpdf compose 경로) + 크롭 + 회전 동시 -- RO 원칙 유지', () async {
      final stagingDir = Directory('${root.path}/docs/case2.tmp')..createSync(recursive: true);
      final outputPath = '${stagingDir.path}/document.pdf';
      final imagesDir = Directory('${stagingDir.path}/sources/pages')..createSync(recursive: true);
      final imgPath = '${imagesDir.path}/000.jpg';
      await File(imgPath).writeAsBytes(_quadrantJpeg(400));

      final srcText = pw.Document()..addPage(pw.Page(build: (context) => pw.Center(child: pw.Text('TEXT_PAGE_END'))));
      final textBytes = await srcText.save();
      final srcTextPath = '${stagingDir.path}/text_src.pdf';
      await File(srcTextPath).writeAsBytes(textBytes);

      // 좌하단(BL) 사분면만 남기고, 회전을 섞어 anyRotation을 true로 만들어 qpdf compose
      // 경로(§5.2 표 행 4)를 강제로 태운다.
      const crop = CropRect(left: 0, top: 0.5, right: 0.5, bottom: 1);
      final pages = [
        ImagePageRef(imagePath: imgPath, rotation: 90, crop: crop),
        PdfPageRef(sourcePath: srcTextPath, sourceIndex: 0, rotation: 0),
      ];

      final result = await engine.save(
        pages: pages,
        outputPath: outputPath,
        quality: ImageQuality.high,
        guardInput: generousGuard,
      );
      expect(result, isA<PdfOk<SaveOutcome>>(), reason: '저장 자체가 실패함: $result');

      final doc = await pdfrx.PdfDocument.openFile(outputPath);
      try {
        expect(doc.pages.length, 2, reason: 'RO-1 페이지 수 불일치');
        expect(doc.pages[0].rotation.index * 90, 90, reason: 'RO-4 회전값 불일치');
        await _expectPdfrxDominantColor(doc.pages[0], _bl, reason: '크롭한 BL 사분면 색이어야 한다(회전이 섞여도 크롭 색은 유지)');
        final text = await doc.pages[1].loadText();
        expect(text?.fullText ?? '', contains('TEXT_PAGE_END'), reason: 'RO-2 텍스트 페이지 내용 불일치');
      } finally {
        await doc.dispose();
      }
    }, skip: _ffiSkip);
  });

  group('3. PdfxRenderer.renderPageThumbnail -- ImagePageRef.crop 반영', () {
    late Directory root;
    late PdfxRenderer renderer;

    setUp(() {
      root = Directory.systemTemp.createTempSync('pdf_daeri_crop_render_');
      renderer = PdfxRenderer();
    });

    tearDown(() {
      renderer.evictCache();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('crop이 있으면 크롭한 사분면만 렌더된다', () async {
      final imgPath = '${root.path}/quad.jpg';
      await File(imgPath).writeAsBytes(_quadrantJpeg(400));

      // 우상단(TR) 사분면만 남긴다.
      const crop = CropRect(left: 0.5, top: 0, right: 1, bottom: 0.5);
      final page = ImagePageRef(imagePath: imgPath, rotation: 0, crop: crop);

      final result = await renderer.renderPageThumbnail(page: page, targetWidthPx: 100);
      expect(result, isA<PdfOk<Uint8List>>(), reason: '렌더 실패: $result');
      final png = (result as PdfOk<Uint8List>).value;
      final decoded = img.decodePng(png)!;
      _expectCenterColor(decoded, _tr, reason: '크롭한 TR 사분면 색이어야 한다');
    });

    test('crop이 null이면 기존 동작 그대로 -- 전체 이미지가 렌더된다(회귀 방어)', () async {
      final imgPath = '${root.path}/quad_nocrop.jpg';
      await File(imgPath).writeAsBytes(_quadrantJpeg(400));

      final page = ImagePageRef(imagePath: imgPath, rotation: 0);
      final result = await renderer.renderPageThumbnail(page: page, targetWidthPx: 100);
      expect(result, isA<PdfOk<Uint8List>>(), reason: '렌더 실패: $result');
      final png = (result as PdfOk<Uint8List>).value;
      final decoded = img.decodePng(png)!;
      expect(decoded.width, 100, reason: 'crop 없음이면 targetWidthPx 그대로 디코드해야 한다(기존 경로 유지)');
    });
  });
}
