// 스캔 분석·추천 엔진 테스트 — 합성 RGBA 버퍼만 사용(Flutter 바인딩 불필요).
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/app/locale_scan_edit.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';
import 'package:pdf_daeri/pdf/scan_quality_advisor.dart';

const _w = 400, _h = 520;

/// 단색 바탕 + 가로줄(두께 [thick]px, 간격 [period]px).
Uint8List _stripes({
  required int period,
  int thick = 2,
  List<int> bg = const [255, 255, 255],
  List<int> ink = const [0, 0, 0],
}) {
  final out = Uint8List(_w * _h * 4);
  for (var y = 0; y < _h; y++) {
    final c = (y % period) < thick ? ink : bg;
    for (var x = 0; x < _w; x++) {
      final p = (y * _w + x) * 4;
      out[p] = c[0];
      out[p + 1] = c[1];
      out[p + 2] = c[2];
      out[p + 3] = 255;
    }
  }
  return out;
}

Uint8List _flat(int r, int g, int b) {
  final out = Uint8List(_w * _h * 4);
  for (var p = 0; p < out.length; p += 4) {
    out[p] = r;
    out[p + 1] = g;
    out[p + 2] = b;
    out[p + 3] = 255;
  }
  return out;
}

/// 5x5 박스 블러를 [passes]회 반복(가우시안 근사). 새 버퍼를 반환한다.
Uint8List _blur(Uint8List src, {int radius = 2, int passes = 3}) {
  var cur = Uint8List.fromList(src);
  for (var k = 0; k < passes; k++) {
    final next = Uint8List.fromList(cur);
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        for (var c = 0; c < 3; c++) {
          var s = 0, n = 0;
          for (var dy = -radius; dy <= radius; dy++) {
            for (var dx = -radius; dx <= radius; dx++) {
              final yy = y + dy, xx = x + dx;
              if (yy < 0 || yy >= _h || xx < 0 || xx >= _w) continue;
              s += cur[(yy * _w + xx) * 4 + c];
              n++;
            }
          }
          next[(y * _w + x) * 4 + c] = s ~/ n;
        }
      }
    }
    cur = next;
  }
  return cur;
}

ScanQualityMetrics _m(Uint8List px, {int src = 2000}) =>
    computeScanMetrics(px, _w, _h, srcLongEdgePx: src);

void main() {
  group('설계 §5 합성 케이스', () {
    test('1. 촘촘한 줄 -> edgeDensity > 0.12, 화질 high', () {
      final m = _m(_stripes(period: 6));
      expect(m.edgeDensity, greaterThan(0.12));
      final a = adviseScan(_m(_stripes(period: 12), src: 2000));
      expect(a.quality, ImageQuality.high);
    });

    test('2. 같은 패턴을 블러 -> sharpness 낮음, issues.first == blur', () {
      final sharp = _m(_stripes(period: 12));
      final blurred = _m(_blur(_stripes(period: 12)));
      expect(sharp.sharpness, greaterThan(ScanAdviceThresholds.blurSharpness));
      expect(blurred.sharpness, lessThan(ScanAdviceThresholds.blurSharpness));
      expect(blurred.edgeDensity, greaterThanOrEqualTo(0.02));
      final a = adviseScan(blurred);
      expect(a.issues.first, ScanIssue.blur);
      expect(adviseScan(sharp).issues, isNot(contains(ScanIssue.blur)));
    });

    test('3. 빈 흰 종이 -> blur 아님, standard', () {
      final m = _m(_flat(255, 255, 255));
      expect(m.edgeDensity, lessThan(0.02));
      final a = adviseScan(m);
      expect(a.issues, isEmpty);
      expect(a.needsRetake, isFalse);
      expect(a.quality, ImageQuality.standard);
    });

    test('4. 전체 휘도 40 -> dark', () {
      final a = adviseScan(_m(_flat(40, 40, 40)));
      expect(a.issues, contains(ScanIssue.dark));
      expect(a.issues.first, ScanIssue.dark);
    });

    test('5. 30% 픽셀 255 -> glare', () {
      final px = _flat(128, 128, 128);
      final n = _w * _h;
      for (var i = 0; i < (n * 0.3).round(); i++) {
        final p = i * 4;
        px[p] = px[p + 1] = px[p + 2] = 255;
      }
      final a = adviseScan(_m(px));
      expect(a.issues, contains(ScanIssue.glare));
    });

    test('6. 큰 고채도 색 블록 -> photo', () {
      final px = Uint8List(_w * _h * 4);
      const colors = [
        [255, 0, 0],
        [0, 200, 0],
        [0, 0, 255],
        [255, 220, 0],
      ];
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          final c = colors[(y ~/ 260) * 2 + (x ~/ 200)];
          final p = (y * _w + x) * 4;
          px[p] = c[0];
          px[p + 1] = c[1];
          px[p + 2] = c[2];
          px[p + 3] = 255;
        }
      }
      final a = adviseScan(_m(px));
      expect(a.format, ScanFormatAdvice.photo);
    });

    test('7. 컬러 배경 + 촘촘한 글자줄 -> pdf', () {
      final px = _stripes(
        period: 6,
        bg: [255, 200, 120],
        ink: [20, 20, 120],
      );
      final m = _m(px);
      expect(m.colorfulness, greaterThan(ScanAdviceThresholds.photoColorfulness));
      expect(adviseScan(m).format, ScanFormatAdvice.pdf);
    });

    test('8. 원본 긴 변 4000 + 매우 촘촘 -> original, 2000 -> high', () {
      final px = _stripes(period: 6);
      expect(adviseScan(_m(px, src: 4000)).quality, ImageQuality.original);
      expect(adviseScan(_m(px, src: 2000)).quality, ImageQuality.high);
    });

    test('9. 입력 버퍼 불변(계산 전후 바이트 동일)', () {
      final px = _stripes(period: 6, bg: [255, 200, 120], ink: [20, 20, 120]);
      final before = Uint8List.fromList(px);
      _m(px);
      expect(px, orderedEquals(before));
    });

    test('10. 모든 한국어 키가 scanEditEnglish에 있다', () {
      for (final key in kScanAdviceTextKeys) {
        expect(scanEditEnglish.containsKey(key), isTrue, reason: key);
      }
      for (final issue in ScanIssue.values) {
        expect(kScanAdviceTextKeys, contains(scanIssueMessage(issue)));
      }
      final a = adviseScan(_m(_flat(40, 40, 40)));
      expect(kScanAdviceTextKeys, contains(a.qualityReason));
      expect(kScanAdviceTextKeys, contains(a.formatReason));
    });
  });

  group('다중 페이지 결합', () {
    final sparse = _m(_flat(255, 255, 255));
    final dense = _m(_stripes(period: 6), src: 4000);
    final dark = _m(_flat(40, 40, 40));
    final photo = _m(
      _stripes(period: 400, thick: 200, bg: [255, 0, 0], ink: [0, 0, 255]),
    );

    test('빈 목록은 ArgumentError', () {
      expect(() => adviseScanPages(const []), throwsArgumentError);
    });

    test('문제는 가장 나쁜 페이지 기준 + 해당 페이지 인덱스', () {
      final a = adviseScanPages([sparse, dark, sparse, dark]);
      expect(a.issues, [ScanIssue.dark]);
      expect(a.issuePages[ScanIssue.dark], [1, 3]);
      expect(a.pageCount, 4);
      expect(a.metrics, same(dark));
    });

    test('화질은 가장 높은 요구 페이지 기준', () {
      expect(adviseScanPages([sparse, dense]).quality, ImageQuality.original);
      expect(adviseScanPages([sparse, sparse]).quality, ImageQuality.standard);
    });

    test('형식은 다수결, 동률은 pdf', () {
      expect(
        adviseScan(photo).format,
        ScanFormatAdvice.photo,
        reason: 'photo 샘플 전제',
      );
      expect(
        adviseScanPages([photo, photo, sparse]).format,
        ScanFormatAdvice.photo,
      );
      expect(
        adviseScanPages([photo, sparse]).format,
        ScanFormatAdvice.pdf,
      );
    });

    test('단일 페이지 결과는 adviseScan과 동일 구조', () {
      final a = adviseScanPages([dark]);
      final b = adviseScan(dark);
      expect(a.issues, b.issues);
      expect(a.issuePages[ScanIssue.dark], [0]);
    });

    test('isolate 경로: 입력 검증 + 결과 일치', () async {
      final px = _stripes(period: 6);
      final advice = await analyzeScanPagesInIsolate([
        ScanPixelsInput(
          rgba: TransferableTypedData.fromList([px]),
          width: _w,
          height: _h,
          srcLongEdgePx: 4000,
        ),
      ]);
      expect(advice.quality, ImageQuality.original);
      expect(
        () => computeScanMetrics(Uint8List(10), _w, _h, srcLongEdgePx: 1),
        throwsArgumentError,
      );
    });
  });
}
