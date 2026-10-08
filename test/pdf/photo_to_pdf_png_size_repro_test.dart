// 재현: 사진→PDF 저장에 PNG 소스를 넣으면 encodeForEmbed가 "비 JPEG → 원본 그대로"를 반환하고,
// `package:pdf`가 PNG를 디코드해 원시 픽셀(Flate)로 다시 싣기 때문에 결과 PDF가 원본 PNG 바이트
// 합계 × mergeRatio(SizeGuard 한도)를 넘는다 — 실기기 QA(v1.1.22) "저장 중단" 증상.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/image_pdf_builder.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';

void main() {
  Future<int> buildSize(Uint8List src, ImageQualityProfile q) async {
    final embed = ImagePdfBuilder.encodeForEmbed(
      src,
      longEdgeMaxPx: q.longEdgeMaxPx,
      jpegQuality: q.jpegQuality,
    );
    final pdf = await ImagePdfBuilder.build(jpegPages: [embed], title: null);
    return pdf.length;
  }

  for (final q in [ImageQualityProfile.high, ImageQualityProfile.standard, ImageQualityProfile.min]) {
    test('QA 자산 PNG(website/assets/1.png) 사진→PDF 결과가 merge 한도 이내 — ${q.longEdgeMaxPx}px', () async {
      final src = File('website/assets/1.png').readAsBytesSync();
      final size = await buildSize(src, q);
      final guard = SizeGuard.check(
        input: GuardInput(op: SaveOp.merge, baselineBytes: src.length),
        resultBytes: size,
      );
      expect(guard, isA<GuardPass>(), reason: 'src=${src.length} result=$size');
    });
  }

  test('합성 PNG(사진형 그라디언트+노이즈)도 한도 이내', () async {
    final image = img.Image(width: 900, height: 1600);
    var seed = 7;
    for (final p in image) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final n = seed % 24;
      p.setRgb((p.x * 255 ~/ 900 + n) % 256, (p.y * 255 ~/ 1600 + n) % 256, (n * 7) % 256);
    }
    final src = Uint8List.fromList(img.encodePng(image));
    final q = ImageQualityProfile.min;
    final size = await buildSize(src, q);
    final guard = SizeGuard.check(
      input: GuardInput(op: SaveOp.merge, baselineBytes: src.length),
      resultBytes: size,
    );
    expect(guard, isA<GuardPass>(), reason: 'src=${src.length} result=$size');
  });
}
