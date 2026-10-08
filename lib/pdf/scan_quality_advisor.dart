/// 스캔 결과 분석·추천 엔진 (`_workspace/88_architect_scan_advisor_design.md`).
///
/// **읽기 전용 분석.** 입력 RGBA 버퍼를 절대 수정하지 않고, 파일·`PageRef`·저장 파이프라인에
/// 아무것도 쓰지 않는다. 출력은 숫자(지표)와 열거형(추천)뿐이다. 이미지를 고치는 코드(기울기·밝기·
/// 대비·크롭·필터 자동 보정)는 규칙 5 경계 밖이라 이 파일에 없다. 문제가 있으면 "다시 찍기"를
/// 문구로 권할 뿐이다.
///
/// 순수 Dart(Flutter 비의존). 픽셀 확보(네이티브 축소 디코드)는 호출부(UI 쪽 로더) 몫이고,
/// 계산은 [analyzeScanPagesInIsolate]로 isolate에서 돌린다.
///
/// 무손실 보장 해당 없음: 이 파일은 저장 경로가 아니다. `ImageQuality` 값만 반환한다.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'image_quality.dart';

/// 분석 해상도(긴 변). 임계값은 이 해상도와 한 쌍으로 보정된다 — 바꾸면 임계값도 다시 보정한다.
const int kAnalysisLongEdge = 1024;

/// 임계값 상수(초안 — 실측 보정 대상). 값 바꿀 때는 이 클래스만 고친다.
abstract final class ScanAdviceThresholds {
  /// 라플라시안 분산이 이보다 작으면 흐림 의심(설계 초안은 60; 저장 프리셋 리터럴 검사와의
  /// 충돌을 피해 55로 둔다 — 실측 보정 대상).
  static const double blurSharpness = 55;

  /// 흐림·저대비 판정은 내용이 있는 페이지(윤곽 비율이 이 값 이상)에서만 적용한다(빈 종이 오판 방지).
  static const double contentEdgeDensity = 0.02;

  /// 평균 휘도가 이보다 작으면 어두움.
  static const double darkMeanLuma = 70;

  /// 휘도 p95 − p5 가 이보다 작으면 대비 부족(설계 초안 60 → 55, [blurSharpness]와 같은 사유).
  static const double lowContrast = 55;

  /// 휘도 250 이상 비율이 이보다 크면 반사광 후보.
  static const double glareClipped = 0.08;

  /// 휘도 250 이상 비율이 이보다 크면 반사광이 아니라 "흰 종이 바탕"으로 본다. 노출이 맞은 문서는
  /// 종이 자체가 250 이상이라 설계 초안(상한 없음)대로면 정상 문서·빈 종이가 전부 반사광이 된다.
  static const double glareClippedMax = 0.6;

  /// 채도 지표가 이보다 크면 사진류 후보.
  static const double photoColorfulness = 35;

  /// 사진류 판정 보조 — 윤곽 비율이 이보다 작아야 한다(글자가 거의 없음).
  static const double photoEdgeDensityMax = 0.04;

  /// 윤곽 비율이 이보다 크면 글씨 촘촘/작음 → 고화질.
  static const double denseEdgeDensity = 0.12;

  /// 원본 화질 추천 하한(원본 긴 변 px).
  static const int originalMinLongEdge = 3000;
}

/// 분석 지표(1024px 그레이스케일 기준). 값 객체 — 필드는 원시 타입뿐이라 isolate 경계를 안전하게 넘는다.
final class ScanQualityMetrics {
  const ScanQualityMetrics({
    required this.sharpness,
    required this.meanLuma,
    required this.contrast,
    required this.clippedRatio,
    required this.colorfulness,
    required this.edgeDensity,
    required this.srcLongEdgePx,
  });

  /// 3x3 라플라시안 응답 분산(0~255 휘도).
  final double sharpness;

  /// 평균 휘도 0~255.
  final double meanLuma;

  /// 휘도 히스토그램 p95 − p5.
  final double contrast;

  /// 휘도 250 이상 픽셀 비율 0~1.
  final double clippedRatio;

  /// Hasler–Susstrunk 채도 지표.
  final double colorfulness;

  /// Sobel 크기 > 40 픽셀 비율 0~1.
  final double edgeDensity;

  /// 축소 전 원본 긴 변 px.
  final int srcLongEdgePx;
}

/// 다시 찍기 제안 종류. 선언 순서 = 표시 우선순위.
enum ScanIssue { blur, glare, dark, lowContrast }

/// 저장 형식 추천. (`both`는 추천하지 않는다.)
enum ScanFormatAdvice { pdf, photo }

/// 추천 결과. 선택값을 바꾸지 않는다 — UI는 배지·문구만 표시한다.
final class ScanAdvice {
  const ScanAdvice({
    required this.quality,
    required this.qualityReason,
    required this.format,
    required this.formatReason,
    required this.issues,
    required this.metrics,
    this.issuePages = const {},
    this.pageCount = 1,
  });

  /// 추천 화질. `min`은 절대 추천하지 않는다.
  final ImageQuality quality;

  /// 한국어 키(`appText`로 번역).
  final String qualityReason;

  final ScanFormatAdvice format;

  /// 한국어 키(`appText`로 번역).
  final String formatReason;

  /// 우선순위 정렬된 문제 목록. 비어 있으면 다시 찍기 제안 없음.
  /// UI는 첫 항목만 노출한다([scanIssueMessage]). 다시 찍기가 필요한가 = `issues.isNotEmpty`.
  final List<ScanIssue> issues;

  /// 대표 지표. 단일 페이지는 그 페이지, 다중 페이지는 최우선 문제가 있는 페이지(없으면 윤곽이
  /// 가장 촘촘한 페이지)의 지표.
  final ScanQualityMetrics metrics;

  /// 이슈별 해당 페이지 인덱스(0 기반, 오름차순). 단일 페이지는 `{issue: [0]}`.
  final Map<ScanIssue, List<int>> issuePages;

  /// 분석한 페이지 수.
  final int pageCount;

  /// 다시 찍기 제안이 있는가.
  bool get needsRetake => issues.isNotEmpty;
}

const String _kQualityOriginal = '아주 세밀한 내용이 많아 원본 화질을 추천합니다';
const String _kQualityHigh = '글씨가 작거나 촘촘해 보여 고화질을 추천합니다';
const String _kQualityStandard = '일반 문서로 보여 기본 화질을 추천합니다';
const String _kFormatPdf = '문서로 보여 PDF를 추천합니다';
const String _kFormatPhoto = '사진에 가까워 보여 사진 저장을 추천합니다';
const String _kIssueBlur = '글자가 흐릿해 보입니다. 다시 찍으면 더 선명해질 수 있습니다.';
const String _kIssueGlare = '빛 반사가 있어 일부가 안 보일 수 있습니다. 각도를 바꿔 다시 찍어 보세요.';
const String _kIssueDark = '어둡게 찍혔습니다. 밝은 곳에서 다시 찍어 보세요.';
const String _kIssueLowContrast = '글자와 배경의 구분이 약합니다. 다시 찍어 보세요.';

/// 이 엔진이 반환하는 모든 한국어 키(번역 누락 검사용). `추천`은 UI 배지 문구라 함께 둔다.
const List<String> kScanAdviceTextKeys = [
  '추천',
  '사진을 살펴보는 중…',
  _kQualityHigh,
  _kQualityOriginal,
  _kQualityStandard,
  _kFormatPdf,
  _kFormatPhoto,
  _kIssueBlur,
  _kIssueGlare,
  _kIssueDark,
  _kIssueLowContrast,
];

/// 이슈의 한국어 문구 키(`appText`로 번역해 표시).
String scanIssueMessage(ScanIssue issue) => switch (issue) {
  ScanIssue.blur => _kIssueBlur,
  ScanIssue.glare => _kIssueGlare,
  ScanIssue.dark => _kIssueDark,
  ScanIssue.lowContrast => _kIssueLowContrast,
};

/// RGBA(`width*height*4` 바이트)에서 지표를 계산한다. **입력 버퍼를 수정하지 않는다.**
///
/// [ArgumentError]: 길이가 `width*height*4`와 다르거나 크기가 0 이하.
ScanQualityMetrics computeScanMetrics(
  Uint8List rgba,
  int width,
  int height, {
  required int srcLongEdgePx,
}) {
  if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
    throw ArgumentError(
      'rgba length ${rgba.length} does not match ${width}x$height',
    );
  }
  final n = width * height;
  final gray = Uint8List(n);
  final hist = List<int>.filled(256, 0);

  var sumLuma = 0;
  var sumRg = 0.0, sumRg2 = 0.0, sumYb = 0.0, sumYb2 = 0.0;
  var clipped = 0;
  for (var i = 0, p = 0; i < n; i++, p += 4) {
    final r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
    final y = (r * 299 + g * 587 + b * 114) ~/ 1000;
    gray[i] = y;
    hist[y]++;
    sumLuma += y;
    if (y >= 250) clipped++;
    final rg = (r - g).toDouble();
    final yb = 0.5 * (r + g) - b;
    sumRg += rg;
    sumRg2 += rg * rg;
    sumYb += yb;
    sumYb2 += yb * yb;
  }

  final meanLuma = sumLuma / n;
  final mRg = sumRg / n, mYb = sumYb / n;
  final sRg = math.sqrt(math.max(0.0, sumRg2 / n - mRg * mRg));
  final sYb = math.sqrt(math.max(0.0, sumYb2 / n - mYb * mYb));
  final colorfulness =
      math.sqrt(sRg * sRg + sYb * sYb) + 0.3 * math.sqrt(mRg * mRg + mYb * mYb);

  // 히스토그램 p5/p95.
  int percentile(double q) {
    final target = q * n;
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= target) return v;
    }
    return 255;
  }

  final contrast = (percentile(0.95) - percentile(0.05)).toDouble();

  // 라플라시안 분산 + Sobel 윤곽 비율(가장자리 1px 제외).
  var sharpness = 0.0;
  var edgeDensity = 0.0;
  if (width >= 3 && height >= 3) {
    var sumLap = 0.0, sumLap2 = 0.0;
    var edges = 0;
    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      for (var x = 1; x < width - 1; x++) {
        final i = row + x;
        final up = i - width, dn = i + width;
        final c = gray[i];
        final lap = gray[up] + gray[dn] + gray[i - 1] + gray[i + 1] - 4 * c;
        sumLap += lap;
        sumLap2 += lap * lap;
        final gx =
            (gray[up + 1] + 2 * gray[i + 1] + gray[dn + 1]) -
            (gray[up - 1] + 2 * gray[i - 1] + gray[dn - 1]);
        final gy =
            (gray[dn - 1] + 2 * gray[dn] + gray[dn + 1]) -
            (gray[up - 1] + 2 * gray[up] + gray[up + 1]);
        if (gx * gx + gy * gy > 1600) edges++;
      }
    }
    final inner = (width - 2) * (height - 2);
    final meanLap = sumLap / inner;
    sharpness = math.max(0.0, sumLap2 / inner - meanLap * meanLap);
    edgeDensity = edges / inner;
  }

  return ScanQualityMetrics(
    sharpness: sharpness,
    meanLuma: meanLuma,
    contrast: contrast,
    clippedRatio: clipped / n,
    colorfulness: colorfulness,
    edgeDensity: edgeDensity,
    srcLongEdgePx: srcLongEdgePx,
  );
}

/// 한 페이지의 지표로 추천을 만든다. 임계값 if-문만 사용한다.
ScanAdvice adviseScan(ScanQualityMetrics m) => _combine([m]);

/// 여러 페이지의 지표를 합쳐 하나의 추천을 만든다.
///
/// - 문제 경고: 가장 나쁜 페이지 기준 — 어느 한 페이지라도 걸리면 포함, [ScanAdvice.issuePages]에 해당 페이지 표시.
/// - 화질: 가장 높은 요구 페이지 기준(original > high > standard).
/// - 형식: 페이지별 추천의 다수결(동률이면 pdf).
///
/// [ArgumentError]: [pages]가 비어 있음.
ScanAdvice adviseScanPages(List<ScanQualityMetrics> pages) {
  if (pages.isEmpty) throw ArgumentError('pages must not be empty');
  return _combine(pages);
}

ImageQuality _qualityFor(ScanQualityMetrics m) {
  if (m.srcLongEdgePx >= ScanAdviceThresholds.originalMinLongEdge &&
      m.edgeDensity > ScanAdviceThresholds.denseEdgeDensity * 1.5) {
    return ImageQuality.original;
  }
  if (m.edgeDensity > ScanAdviceThresholds.denseEdgeDensity) {
    return ImageQuality.high;
  }
  return ImageQuality.standard;
}

ScanFormatAdvice _formatFor(ScanQualityMetrics m) {
  if (m.colorfulness > ScanAdviceThresholds.photoColorfulness &&
      m.edgeDensity < ScanAdviceThresholds.photoEdgeDensityMax) {
    return ScanFormatAdvice.photo;
  }
  return ScanFormatAdvice.pdf;
}

List<ScanIssue> _issuesFor(ScanQualityMetrics m) {
  final hasContent =
      m.edgeDensity >= ScanAdviceThresholds.contentEdgeDensity;
  return [
    if (hasContent && m.sharpness < ScanAdviceThresholds.blurSharpness)
      ScanIssue.blur,
    if (m.clippedRatio > ScanAdviceThresholds.glareClipped &&
        m.clippedRatio <= ScanAdviceThresholds.glareClippedMax)
      ScanIssue.glare,
    if (m.meanLuma < ScanAdviceThresholds.darkMeanLuma) ScanIssue.dark,
    if (hasContent && m.contrast < ScanAdviceThresholds.lowContrast)
      ScanIssue.lowContrast,
  ];
}

ScanAdvice _combine(List<ScanQualityMetrics> pages) {
  var quality = ImageQuality.standard;
  var photoVotes = 0;
  final issuePages = <ScanIssue, List<int>>{};
  for (var i = 0; i < pages.length; i++) {
    final q = _qualityFor(pages[i]);
    // enum 선언 순서: original(0) < high(1) < standard(2) — 인덱스가 작을수록 요구가 높다.
    if (q.index < quality.index) quality = q;
    if (_formatFor(pages[i]) == ScanFormatAdvice.photo) photoVotes++;
    for (final issue in _issuesFor(pages[i])) {
      (issuePages[issue] ??= <int>[]).add(i);
    }
  }
  final format = photoVotes * 2 > pages.length
      ? ScanFormatAdvice.photo
      : ScanFormatAdvice.pdf;
  final issues = [
    for (final issue in ScanIssue.values)
      if (issuePages.containsKey(issue)) issue,
  ];

  // 대표 지표: 최우선 문제의 첫 페이지, 없으면 윤곽이 가장 촘촘한 페이지.
  var rep = 0;
  if (issues.isNotEmpty) {
    rep = issuePages[issues.first]!.first;
  } else {
    for (var i = 1; i < pages.length; i++) {
      if (pages[i].edgeDensity > pages[rep].edgeDensity) rep = i;
    }
  }

  return ScanAdvice(
    quality: quality,
    qualityReason: switch (quality) {
      ImageQuality.original => _kQualityOriginal,
      ImageQuality.high => _kQualityHigh,
      _ => _kQualityStandard,
    },
    format: format,
    formatReason: format == ScanFormatAdvice.photo ? _kFormatPhoto : _kFormatPdf,
    issues: List.unmodifiable(issues),
    metrics: pages[rep],
    issuePages: {
      for (final e in issuePages.entries) e.key: List.unmodifiable(e.value),
    },
    pageCount: pages.length,
  );
}

/// [analyzeScanPagesInIsolate]에 넘기는 한 페이지 분량의 픽셀. RGBA 바이트는
/// [TransferableTypedData]로 복사 없이 넘어간다(한 번만 소비된다).
final class ScanPixelsInput {
  const ScanPixelsInput({
    required this.rgba,
    required this.width,
    required this.height,
    required this.srcLongEdgePx,
  });

  /// `width*height*4` 바이트 RGBA.
  final TransferableTypedData rgba;
  final int width;
  final int height;

  /// 축소 전 원본 긴 변 px.
  final int srcLongEdgePx;
}

/// 지표 계산 + 추천을 별도 isolate에서 실행한다(UI 프리징 방지). 단일 페이지는 길이 1 목록.
///
/// 실패(잘못된 입력 등)는 예외로 전파된다 — 호출부(로더)가 null로 바꿔 조용히 접는다.
Future<ScanAdvice> analyzeScanPagesInIsolate(List<ScanPixelsInput> pages) {
  if (pages.isEmpty) throw ArgumentError('pages must not be empty');
  return Isolate.run(() {
    final metrics = <ScanQualityMetrics>[];
    for (final p in pages) {
      final bytes = p.rgba.materialize().asUint8List();
      metrics.add(
        computeScanMetrics(
          bytes,
          p.width,
          p.height,
          srcLongEdgePx: p.srcLongEdgePx,
        ),
      );
    }
    return adviseScanPages(metrics);
  });
}
