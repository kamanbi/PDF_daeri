/// 스캔 추천 분석의 UI 쪽 입구. 네이티브 디코더로 긴 변 [kAnalysisLongEdge]까지 줄여 읽은 뒤
/// 바이트만 엔진(`lib/pdf/scan_quality_advisor.dart`)의 isolate 호출에 넘긴다. 읽기 전용.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../pdf/scan_quality_advisor.dart';

/// 이미지 파일들을 분석해 추천을 돌려준다. 디코드 오류·타임아웃 등 모든 실패는 `null`이며
/// 예외를 밖으로 던지지 않는다(호출부 UI는 조용히 접힌다). 여러 장이면 한 번에 결합 분석한다.
Future<ScanAdvice?> loadScanAdvice(
  List<String> imagePaths, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (imagePaths.isEmpty) return null;
  try {
    return await _analyze(imagePaths).timeout(timeout * imagePaths.length);
  } catch (_) {
    return null;
  }
}

Future<ScanAdvice> _analyze(List<String> paths) async {
  final inputs = <ScanPixelsInput>[];
  for (final path in paths) {
    inputs.add(await _decodeForAnalysis(path));
  }
  return analyzeScanPagesInIsolate(inputs);
}

Future<ScanPixelsInput> _decodeForAnalysis(String path) async {
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    final longEdge = math.max(w, h);
    final scale = longEdge > kAnalysisLongEdge ? kAnalysisLongEdge / longEdge : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (w * scale).round()),
      targetHeight: math.max(1, (h * scale).round()),
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('decode failed');
    return ScanPixelsInput(
      rgba: TransferableTypedData.fromList([
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ]),
      width: image.width,
      height: image.height,
      srcLongEdgePx: longEdge,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
