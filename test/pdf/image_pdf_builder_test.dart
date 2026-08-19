// N1 회귀 방어 — 07_spec-guardian_report_r2.md 실측: `encodeForEmbed`의 `return jpegBytes;`
// (A-4 스킵 분기)를 지워도 이 테스트가 생기기 전까지는 83개 테스트가 전부 통과했다.
// 여기서는 A-4/A-5/프리셋/Q-B(A4 내접)를 검증하고, 각 테스트가 실제로 로직 손상을 잡는지
// "훼손 → 실패 확인 → 원복" 절차로 확인한다(별도 기록, 이 파일 자체는 정상 상태만 담는다).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_daeri/pdf/image_pdf_builder.dart';

/// 단색에 가까운(=매우 잘 압축되는) 테스트 JPEG.
Uint8List _solidJpeg(int width, int height, {int quality = 85}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, 120, 140, 160);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// 부드러운 그라디언트 JPEG. 단색 이미지와 달리 실제 AC 계수가 존재해서 JPEG 품질(quantization)
/// 차이가 파일 크기에 실제로 영향을 준다 -- 단색 이미지로는 이 성질이 없어(모든 AC 계수가 이미
/// 0이라 quality를 낮춰도 바이트 수가 전혀 안 바뀐다) A-4 스킵 회귀 테스트가 무력화됐었다(실측).
Uint8List _gradientJpeg(int width, int height, {int quality = 85}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (x * 255 / width).floor() & 0xFF;
      final g = (y * 255 / height).floor() & 0xFF;
      final b = ((x + y) * 255 / (width + height)).floor() & 0xFF;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// 노이즈로 채운(=압축이 잘 안 되는) 테스트 JPEG. 저품질로 인코딩하면 매우 작고,
/// 같은 크기를 고품질로 재인코딩하면 훨씬 커진다 -- A-5(역효과 방지)를 결정적으로 유도한다.
Uint8List _noiseJpeg(int width, int height, {required int quality}) {
  final rand = Random(42);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, rand.nextInt(256), rand.nextInt(256), rand.nextInt(256));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

void main() {
  group('A-4 무손실 우선 스킵', () {
    // 주의: 단순히 "상한 이하 입력 -> 원본과 동일 반환"만 확인하면 부족하다. A-5(역효과 방지)도
    // 결과가 원본보다 나쁘면 원본을 반환하므로, "디코드를 건너뛴 것"과 "디코드했지만 결과가
    // 나빠 버린 것"이 겉으로 구별되지 않는다(실측: A-4 스킵 분기를 지워도 이 구분이 없으면
    // 통과해버린다). 또한 **단색 이미지는 이 구분에 부적합하다** — 실측 결과 단색 이미지는
    // AC 계수가 전부 0이라 quality를 95->10으로 낮춰도 인코딩 바이트 수가 전혀 안 바뀌어서
    // A-4가 깨져도(=재인코딩이 실제로 실행돼도) 원본과 결과가 우연히 같은 크기가 되어
    // 이 테스트가 무력화됐다(실측으로 확인). 그래서 실제 AC 계수가 존재하는 그라디언트
    // 이미지를 쓰고, 원본은 고품질(95)/목표는 저품질(10)로 크게 벌려서 A-4가 깨지면
    // 반드시 결과가 원본보다 작아지게(=원본과 달라지게) 만든다.
    test('긴 변이 상한 이하면 디코드 없이 원본 바이트를 그대로(동일 객체로) 반환한다', () {
      // longEdgeMaxPx를 원본보다 딱 1px만 크게 둔다 -- 마진을 최소화해서, 만약 A-4 스킵이
      // 깨져 "업스케일 후 재인코딩" 경로를 타게 되면 그 업스케일 폭이 무시할 수준이라
      // 저품질(10) 재인코딩이 고품질(95) 원본보다 반드시 작아지게 만든다(경계 테스트와 동일 원리).
      final original = _gradientJpeg(1000, 700, quality: 95);
      final result = ImagePdfBuilder.encodeForEmbed(original, longEdgeMaxPx: 1001, jpegQuality: 10);
      expect(
        identical(result, original),
        isTrue,
        reason: '상한 이하이면 jpegQuality 파라미터를 아예 쳐다보지 않고 원본 객체를 그대로 반환해야 한다',
      );
    });

    test('긴 변이 상한과 정확히 같아도 스킵된다(경계값)', () {
      final original = _gradientJpeg(500, 300, quality: 95);
      final result = ImagePdfBuilder.encodeForEmbed(original, longEdgeMaxPx: 500, jpegQuality: 10);
      expect(identical(result, original), isTrue);
    });

    test('긴 변이 상한을 넘으면 스킵되지 않고 실제로 리사이즈된다', () {
      // 단색 이미지는 리사이즈해도 파일 크기가 거의 안 줄어(이미 압축이 극한이라) A-5(역효과
      // 방지)가 원본을 그대로 돌려줄 수 있어 이 경계 테스트에 부적합하다(실측으로 확인함).
      // 픽셀 수에 비례해 크기가 늘어나는 노이즈 이미지로 리사이즈가 실제로 바이트를 줄이는
      // 상황을 확실히 만든다.
      final original = _noiseJpeg(2000, 1200, quality: 85);
      final result = ImagePdfBuilder.encodeForEmbed(original, longEdgeMaxPx: 1000, jpegQuality: 85);
      expect(identical(result, original), isFalse, reason: '상한을 크게 넘으면 재인코딩 경로를 타야 한다');
      final decoded = img.decodeJpg(result)!;
      expect(max(decoded.width, decoded.height), 1000, reason: '리사이즈 후 긴 변은 정확히 longEdgeMaxPx여야 한다');
    });
  });

  group('A-5 역효과 방지', () {
    test('재인코딩 결과가 원본보다 커지면 원본을 그대로 반환한다', () {
      // 노이즈 이미지를 초저품질로 인코딩한 원본은 매우 작다. 같은 이미지를 1px만 줄이고
      // 최고 품질로 재인코딩하면 노이즈 특성상 원본보다 훨씬 커진다 -- A-5가 발동해야 한다.
      const w = 400, h = 300;
      final tinyOriginal = _noiseJpeg(w, h, quality: 1);
      final result = ImagePdfBuilder.encodeForEmbed(tinyOriginal, longEdgeMaxPx: w - 1, jpegQuality: 100);
      expect(result.length, lessThanOrEqualTo(tinyOriginal.length), reason: 'A-5: 결과가 원본보다 크면 원본을 반환해야 한다');
      expect(identical(result, tinyOriginal), isTrue, reason: 'A-5가 발동하면 원본 객체를 그대로 반환한다(새로 만든 바이트가 아니다)');
    });

    test('재인코딩 결과가 원본보다 작아지면 재인코딩 결과를 쓴다(A-5가 항상 원본을 강제하지 않는다)', () {
      final large = _solidJpeg(3000, 2000, quality: 95);
      final result = ImagePdfBuilder.encodeForEmbed(large, longEdgeMaxPx: 2480, jpegQuality: 85);
      expect(result.length, lessThan(large.length));
      expect(identical(result, large), isFalse);
    });
  });

  group('프리셋 3종 — 긴 변·품질이 실제로 적용된다', () {
    final presets = {
      'high': (ImagePdfBuilder.highLongEdgeMaxPx, ImagePdfBuilder.highJpegQuality),
      'standard': (ImagePdfBuilder.standardLongEdgeMaxPx, ImagePdfBuilder.standardJpegQuality),
      'min': (ImagePdfBuilder.minLongEdgeMaxPx, ImagePdfBuilder.minJpegQuality),
    };

    for (final entry in presets.entries) {
      test('${entry.key} 프리셋: 3500px 원본이 긴 변 ${entry.value.$1}px로 리사이즈된다', () {
        final oversized = _solidJpeg(3500, 2000);
        final (longEdgeMaxPx, jpegQuality) = entry.value;
        final result = ImagePdfBuilder.encodeForEmbed(oversized, longEdgeMaxPx: longEdgeMaxPx, jpegQuality: jpegQuality);
        final decoded = img.decodeJpg(result)!;
        expect(max(decoded.width, decoded.height), longEdgeMaxPx, reason: '${entry.key} 프리셋의 longEdgeMaxPx가 적용되지 않았다');
      });
    }

    test('세 프리셋의 longEdgeMaxPx는 서로 달라 실제로 구분된다(high > standard > min)', () {
      expect(ImagePdfBuilder.highLongEdgeMaxPx, greaterThan(ImagePdfBuilder.standardLongEdgeMaxPx));
      expect(ImagePdfBuilder.standardLongEdgeMaxPx, greaterThan(ImagePdfBuilder.minLongEdgeMaxPx));
    });
  });

  group('Q-B: pageBoxFor — A4 박스 내접, 비율 보존', () {
    // A4 포인트 상수(§Q-B 판정). 이 파일 전용으로 여기서만 재선언해 결과를 검증한다.
    const a4Short = 595.276;
    const a4Long = 841.890;
    const tolerance = 0.01;

    test('가로가 긴 이미지(landscape)는 A4 가로 박스에 내접한다', () {
      final jpeg = _solidJpeg(3000, 2000); // 3:2
      final box = ImagePdfBuilder.pageBoxFor(jpeg);
      expect(box.$1, closeTo(a4Long, tolerance), reason: '가로가 긴 이미지는 A4 가로(긴 변)를 꽉 채워야 한다');
      expect(box.$2, lessThanOrEqualTo(a4Short + tolerance));
      expect(box.$1 / box.$2, closeTo(3000 / 2000, 0.001), reason: '원본 종횡비가 보존되어야 한다');
    });

    test('세로가 긴 이미지(portrait)는 A4 세로 박스에 내접한다', () {
      final jpeg = _solidJpeg(2000, 3000); // 2:3
      final box = ImagePdfBuilder.pageBoxFor(jpeg);
      expect(box.$2, closeTo(a4Long, tolerance));
      expect(box.$1, lessThanOrEqualTo(a4Short + tolerance));
      expect(box.$2 / box.$1, closeTo(3000 / 2000, 0.001));
    });

    test('정사각 이미지는 A4 세로 박스 폭에 내접한다(hPx >= wPx 규칙이 정사각을 세로로 취급)', () {
      final jpeg = _solidJpeg(1000, 1000);
      final box = ImagePdfBuilder.pageBoxFor(jpeg);
      expect(box.$1, closeTo(box.$2, tolerance), reason: '정사각 입력은 정사각 결과를 내야 한다');
      expect(box.$1, closeTo(a4Short, tolerance), reason: '정사각은 짧은 변(폭)에 맞춰 내접해야 한다');
    });

    test('A4보다 훨씬 큰 이미지도 A4 박스 안에 들어간다(축소)', () {
      final jpeg = _solidJpeg(8000, 6000);
      final box = ImagePdfBuilder.pageBoxFor(jpeg);
      expect(box.$1, lessThanOrEqualTo(a4Long + tolerance));
      expect(box.$2, lessThanOrEqualTo(a4Long + tolerance));
    });

    test('A4보다 작은 이미지는 A4 박스까지 확대된다(Q-B 공식 그대로 -- C-c 관찰과 일치)', () {
      final jpeg = _solidJpeg(300, 200);
      final box = ImagePdfBuilder.pageBoxFor(jpeg);
      // 300x200(3:2)을 A4 가로(841.89 x 595.276, 약 1.414:1)에 내접시키면 폭이 꽉 찬다.
      expect(box.$1, closeTo(a4Long, tolerance));
      expect(box.$1 / box.$2, closeTo(300 / 200, 0.001));
    });

    test('극단적 종횡비(파노라마)도 비율을 보존하며 내접한다', () {
      final jpeg = _solidJpeg(6000, 400); // 15:1
      final box = ImagePdfBuilder.pageBoxFor(jpeg);
      expect(box.$1, closeTo(a4Long, tolerance));
      expect(box.$1 / box.$2, closeTo(6000 / 400, 0.001));
      expect(box.$2, lessThan(a4Short));
    });

    test('비-JPEG 입력은 예외 없이 A4 세로 기본값을 반환한다', () {
      final notJpeg = Uint8List.fromList([0, 1, 2, 3, 4]);
      final box = ImagePdfBuilder.pageBoxFor(notJpeg);
      expect(box.$1, closeTo(a4Short, tolerance));
      expect(box.$2, closeTo(a4Long, tolerance));
    });
  });

  group('M-E4: jpegPixelSize(공개) — 폭·높이·성분 수', () {
    test('컬러(numChannels=3) 입력 -> SOF 성분 수 3', () {
      final jpeg = _solidJpeg(120, 80);
      final result = ImagePdfBuilder.jpegPixelSize(jpeg);
      expect(result, isNotNull);
      expect(result!.$1, 120);
      expect(result.$2, 80);
      expect(result.$3, 3, reason: '컬러 입력은 3성분(YCbCr)으로 인코딩된다');
    });

    // R2(§31 R2, §7 미검증 항목) 실측: package:image의 encodeJpg가 그레이스케일(numChannels=1)
    // 입력에서 몇 성분을 내는지. 이 버전(image ^4.9.1)의 JpegEncoder(`_writeSOF0`/`_writeSOS`)는
    // 입력 채널 수와 무관하게 항상 3성분(Y/Cb/Cr, nrofcomponents 하드코딩)으로 인코딩한다 --
    // 소스 검토(jpeg_encoder.dart `_writeSOF0`)로 확인했고, 아래는 실제 인코딩 결과로 재확인한다.
    // 결론: encodeJpg 왕복을 거친 이미지는 원본이 그레이스케일 JPEG(1성분)이었더라도 재인코딩
    // 결과는 3성분이 된다 -- L2-ext(pdf_compressor.dart)의 성분 수 비교(§2.3 규칙5/R2 대응)는
    // "재인코딩 결과 성분 수(항상 3)"와 "원본 성분 수"를 비교해야 하며, 원본이 1성분
    // (/DeviceGray)이면 재인코딩 결과(3성분)와 반드시 불일치하므로 그 이미지는 통째로 스킵된다
    // (색공간을 추측해 고쳐 쓰지 않는다는 §2.3/절대 규칙과 일치하는 안전한 귀결).
    test('그레이스케일(numChannels=1) 입력 -> SOF 성분 수도 3이다(실측, package:image 4.9.1)', () {
      final gray = img.Image(width: 64, height: 48, numChannels: 1);
      for (var y = 0; y < gray.height; y++) {
        for (var x = 0; x < gray.width; x++) {
          gray.setPixelRgb(x, y, 128, 128, 128);
        }
      }
      final grayJpeg = Uint8List.fromList(img.encodeJpg(gray, quality: 90));
      final result = ImagePdfBuilder.jpegPixelSize(grayJpeg);
      expect(result, isNotNull);
      expect(result!.$1, 64);
      expect(result.$2, 48);
      expect(result.$3, 3, reason: 'encodeJpg는 그레이스케일 입력에서도 3성분 JPEG을 낸다(실측 확정) -- 1성분을 기대하는 로직을 만들지 말 것');
    });

    test('비-JPEG 입력은 null', () {
      expect(ImagePdfBuilder.jpegPixelSize(Uint8List.fromList([0, 1, 2, 3])), isNull);
    });
  });

  group('A-3: 인코딩은 순수 함수다(입력 바이트 이외의 숨은 상태가 없다)', () {
    test('같은 입력을 반복 적용해도 결과가 항상 같다(세대 누적/시간 의존성 없음)', () {
      final master = _solidJpeg(3000, 2000);
      final first = ImagePdfBuilder.encodeForEmbed(master, longEdgeMaxPx: 2480, jpegQuality: 85);
      final second = ImagePdfBuilder.encodeForEmbed(master, longEdgeMaxPx: 2480, jpegQuality: 85);
      expect(first, equals(second), reason: '항상 마스터 바이트에서 다시 인코딩하면 매번 동일한 결과가 나와야 한다(누적 열화 없음의 전제 조건)');
    });

    test('입력 바이트를 변형하지 않는다(원본 마스터 보존)', () {
      final master = _solidJpeg(3000, 2000);
      final masterCopy = Uint8List.fromList(master);
      ImagePdfBuilder.encodeForEmbed(master, longEdgeMaxPx: 2480, jpegQuality: 85);
      expect(master, equals(masterCopy), reason: 'encodeForEmbed 호출이 입력 Uint8List를 제자리 수정하면 안 된다(마스터 파일 보존 전제)');
    });
  });
}
