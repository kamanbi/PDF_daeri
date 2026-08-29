library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scan_image_quality.dart';

const double _minimumDocumentArea = 0.28;
const double _maximumDocumentArea = 0.90;
const double _cornerHandleDiameter = 48;
const double _cornerHandleEdgeInset = 32;

/// 하나의 문서를 명시적으로 촬영하고 곧바로 모서리를 보정하는 화면이다.
///
/// 기본 다중 스캔 UI를 사용하지 않는다. 문서가 너무 멀면 셔터를 열지 않아
/// 낮은 해상도의 PDF가 만들어지는 것을 막고, 인식이 불안정한 경우에는 사용자가
/// 의도적으로 수동 보정을 선택할 수 있게 한다.
class SingleDocumentScanner extends StatefulWidget {
  const SingleDocumentScanner({super.key});

  @override
  State<SingleDocumentScanner> createState() => _SingleDocumentScannerState();
}

class _SingleDocumentScannerState extends State<SingleDocumentScanner> {
  late final DoclensController _controller = DoclensController(
    config: ScannerConfig(
      enableAutoCapture: false,
      enablePerspectiveWarp: false,
      captureResolution: Resolution.max,
      jpegQuality: scanJpegQuality,
      imageEnhancement: ImageEnhancement.enhanced,
      autoOrientation: AutoOrientation.none,
      initialFlashMode: FlashMode.auto,
    ),
  );

  StreamSubscription<Quad?>? _quadSubscription;
  StreamSubscription<DetectionStatus>? _statusSubscription;
  Quad? _quad;
  DetectionStatus _status = DetectionStatus.searching;
  Object? _initializationError;
  bool _initializing = true;
  bool _openingAdjustment = false;

  @override
  void initState() {
    super.initState();
    unawaited(_openScanner());
  }

  @override
  void dispose() {
    _quadSubscription?.cancel();
    _statusSubscription?.cancel();
    unawaited(_controller.dispose());
    unawaited(SystemChrome.setPreferredOrientations(const []));
    super.dispose();
  }

  Future<void> _openScanner() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    try {
      await _controller.initialize();
      _quadSubscription = _controller.quadStream.listen((quad) {
        if (mounted) setState(() => _quad = quad);
      });
      _statusSubscription = _controller.statusStream.listen((status) {
        if (mounted) setState(() => _status = status);
      });
      if (mounted) setState(() => _initializing = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _initializationError = error;
          _initializing = false;
        });
      }
    }
  }

  bool get _isDocumentFar {
    final quad = _quad;
    return quad == null || quad.area < _minimumDocumentArea;
  }

  bool get _isDocumentClose {
    final quad = _quad;
    return quad != null && quad.area > _maximumDocumentArea;
  }

  bool get _canCapture =>
      !_openingAdjustment && !_isDocumentFar && !_isDocumentClose;

  String get _guidance {
    if (_quad == null) return '문서 윤곽을 찾는 중입니다.';
    if (_isDocumentFar) return '문서를 화면에 더 크게 맞춰주세요.';
    if (_isDocumentClose) return '문서를 조금 더 멀리 맞춰주세요.';
    if (_status == DetectionStatus.tilted) return '휴대폰을 문서와 평행하게 맞춰주세요.';
    return '문서가 충분히 크게 잡혔습니다.';
  }

  Future<void> _openAdjustment(ScanResult capture) async {
    if (_openingAdjustment || !mounted) return;
    setState(() => _openingAdjustment = true);
    try {
      final adjustedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) =>
              _CornerAdjustmentPage(controller: _controller, capture: capture),
        ),
      );
      if (adjustedPath != null && mounted) {
        Navigator.of(context).pop(adjustedPath);
      }
    } finally {
      if (mounted) setState(() => _openingAdjustment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(body: Center(child: Text('카메라를 준비하는 중입니다.')));
    }
    if (_initializationError != null) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('스캐너를 열지 못했습니다. 돌아가기'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DoclensView(
              controller: _controller,
              overlayBuilder: (context, quad, status) => QuadOverlay.filled(
                quad: quad,
                status: _canCapture
                    ? DetectionStatus.aligned
                    : DetectionStatus.tooFar,
                accent: Colors.white,
              ),
              captureButtonBuilder: (context, capture) => TextButton(
                onPressed: _canCapture ? capture : null,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(_openingAdjustment ? '보정 화면을 여는 중…' : '촬영'),
              ),
              onCapture: (capture) => unawaited(_openAdjustment(capture)),
              onError: (error, stackTrace) {
                if (mounted) setState(() => _initializationError = true);
              },
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _guidance,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerAdjustmentPage extends StatefulWidget {
  const _CornerAdjustmentPage({
    required this.controller,
    required this.capture,
  });

  final DoclensController controller;
  final ScanResult capture;

  @override
  State<_CornerAdjustmentPage> createState() => _CornerAdjustmentPageState();
}

class _CornerAdjustmentPageState extends State<_CornerAdjustmentPage> {
  late Quad _quad = widget.capture.detectedQuad;
  var _saving = false;
  String? _failure;
  Offset? _dragStartGlobalPosition;
  Offset? _dragStartImagePoint;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final imagePath = await widget.controller.warpImage(
        widget.capture.rawImagePath,
        _quad,
      );
      if (mounted) {
        Navigator.of(context).pop(imagePath);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failure = '보정에 실패했습니다. 모서리를 조정하거나 다시 촬영하세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('다시 촬영'),
                  ),
                  const Expanded(
                    child: Text(
                      '모서리 조정',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 84),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _buildEditor(constraints.biggest),
              ),
            ),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(
                  _failure!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            const Divider(height: 1, color: Color(0xFF484848)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : _save,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_saving ? '저장 중…' : '저장'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(Size canvasSize) {
    final fit = _ImageFit.contain(widget.capture.rawImageSize, canvasSize);
    return Stack(
      children: [
        Positioned(
          left: fit.offset.dx,
          top: fit.offset.dy,
          width: fit.size.width,
          height: fit.size.height,
          child: Image.file(
            File(widget.capture.rawImagePath),
            fit: BoxFit.fill,
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _CornerPainter(quad: _quad, fit: fit),
          ),
        ),
        ..._handles(fit),
      ],
    );
  }

  List<Widget> _handles(_ImageFit fit) {
    return [
      _handle(
        fit,
        _quad.topLeft,
        (point) => _quad = Quad(
          topLeft: point,
          topRight: _quad.topRight,
          bottomRight: _quad.bottomRight,
          bottomLeft: _quad.bottomLeft,
        ),
      ),
      _handle(
        fit,
        _quad.topRight,
        (point) => _quad = Quad(
          topLeft: _quad.topLeft,
          topRight: point,
          bottomRight: _quad.bottomRight,
          bottomLeft: _quad.bottomLeft,
        ),
      ),
      _handle(
        fit,
        _quad.bottomRight,
        (point) => _quad = Quad(
          topLeft: _quad.topLeft,
          topRight: _quad.topRight,
          bottomRight: point,
          bottomLeft: _quad.bottomLeft,
        ),
      ),
      _handle(
        fit,
        _quad.bottomLeft,
        (point) => _quad = Quad(
          topLeft: _quad.topLeft,
          topRight: _quad.topRight,
          bottomRight: _quad.bottomRight,
          bottomLeft: point,
        ),
      ),
    ];
  }

  Widget _handle(
    _ImageFit fit,
    Offset imagePoint,
    void Function(Offset) update,
  ) {
    final documentCorner = fit.toCanvas(imagePoint);
    final position = fit.handleAnchor(
      documentCorner,
      edgeInset: _cornerHandleEdgeInset,
    );
    return Positioned(
      left: position.dx - _cornerHandleDiameter / 2,
      top: position.dy - _cornerHandleDiameter / 2,
      width: _cornerHandleDiameter,
      height: _cornerHandleDiameter,
      child: GestureDetector(
        onPanStart: (details) {
          _dragStartGlobalPosition = details.globalPosition;
          _dragStartImagePoint = imagePoint;
        },
        onPanUpdate: (details) {
          final pointerStart = _dragStartGlobalPosition;
          final imageStart = _dragStartImagePoint;
          if (pointerStart == null || imageStart == null) return;
          final pointerDelta = details.globalPosition - pointerStart;
          final target =
              imageStart +
              Offset(
                pointerDelta.dx * fit.imageSize.width / fit.size.width,
                pointerDelta.dy * fit.imageSize.height / fit.size.height,
              );
          setState(() => update(fit.clamp(target)));
        },
        onPanEnd: (_) => _clearDrag(),
        onPanCancel: _clearDrag,
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  void _clearDrag() {
    _dragStartGlobalPosition = null;
    _dragStartImagePoint = null;
  }
}

class _ImageFit {
  const _ImageFit({
    required this.offset,
    required this.size,
    required this.imageSize,
  });

  final Offset offset;
  final Size size;
  final Size imageSize;

  factory _ImageFit.contain(Size imageSize, Size canvasSize) {
    final scale = math.min(
      canvasSize.width / imageSize.width,
      canvasSize.height / imageSize.height,
    );
    final size = Size(imageSize.width * scale, imageSize.height * scale);
    return _ImageFit(
      offset: Offset(
        (canvasSize.width - size.width) / 2,
        (canvasSize.height - size.height) / 2,
      ),
      size: size,
      imageSize: imageSize,
    );
  }

  Offset toCanvas(Offset point) => Offset(
    offset.dx + point.dx * size.width / imageSize.width,
    offset.dy + point.dy * size.height / imageSize.height,
  );
  Offset toImage(Offset point) => Offset(
    (point.dx - offset.dx) * imageSize.width / size.width,
    (point.dy - offset.dy) * imageSize.height / size.height,
  );
  Offset clamp(Offset point) => Offset(
    point.dx.clamp(0, imageSize.width),
    point.dy.clamp(0, imageSize.height),
  );

  /// 실제 보정점은 이미지 끝까지 유지하되 손가락이 잡는 제어점만 안쪽에 둔다.
  Offset handleAnchor(Offset documentCorner, {required double edgeInset}) {
    final horizontalInset = math.min(edgeInset, size.width / 2);
    final verticalInset = math.min(edgeInset, size.height / 2);
    return Offset(
      documentCorner.dx.clamp(
        offset.dx + horizontalInset,
        offset.dx + size.width - horizontalInset,
      ),
      documentCorner.dy.clamp(
        offset.dy + verticalInset,
        offset.dy + size.height - verticalInset,
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.quad, required this.fit});

  final Quad quad;
  final _ImageFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      quad.topLeft,
      quad.topRight,
      quad.bottomRight,
      quad.bottomLeft,
    ].map(fit.toCanvas).toList();
    final handlePoints = [
      for (final point in points)
        fit.handleAnchor(point, edgeInset: _cornerHandleEdgeInset),
    ];
    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      path,
    );
    canvas.drawPath(dim, Paint()..color = const Color(0x9B000000));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final connector = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var index = 0; index < points.length; index++) {
      if (points[index] == handlePoints[index]) continue;
      canvas.drawLine(points[index], handlePoints[index], connector);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.fit != fit;
}
