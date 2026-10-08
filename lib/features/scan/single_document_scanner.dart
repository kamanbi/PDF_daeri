library;

import '../../app/app_locale.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
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
      // 패키지 기본 제공 enhanced 필터(그림자 보정·배경 밝게)를 기본 적용한다.
      imageEnhancement: ImageEnhancement.enhanced,
      autoOrientation: AutoOrientation.none,
      initialFlashMode: FlashMode.auto,
    ),
  );

  StreamSubscription<Quad?>? _quadSubscription;
  StreamSubscription<DetectionStatus>? _statusSubscription;
  StreamSubscription<int>? _physicalRotationSubscription;
  Quad? _quad;
  DetectionStatus _status = DetectionStatus.searching;
  Object? _initializationError;
  bool _initializing = true;
  bool _openingAdjustment = false;
  int _physicalRotationDegrees = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_openScanner());
  }

  @override
  void dispose() {
    _quadSubscription?.cancel();
    _statusSubscription?.cancel();
    _physicalRotationSubscription?.cancel();
    unawaited(_controller.dispose());
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    super.dispose();
  }

  Future<void> _openScanner() async {
    // 카메라 Texture와 모서리 좌표는 세로 좌표계를 유지한다. 물리 방향은
    // 네이티브 센서 이벤트로 별도 받아 조작 UI·저장 JPEG에만 반영한다.
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
      _physicalRotationSubscription = _controller.physicalRotationStream.listen(
        (degrees) {
          if (mounted) setState(() => _physicalRotationDegrees = degrees);
        },
      );
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
      return Scaffold(body: Center(child: Text(appText(context, '카메라를 준비하는 중입니다.'))));
    }
    if (_initializationError != null) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText(context, '스캐너를 열지 못했습니다. 돌아가기')),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1C2022),
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
              captureButtonBuilder: (context, capture) => _rotatedControl(
                FilledButton(
                  onPressed: _canCapture ? capture : null,
                  child: Text(appText(context, _openingAdjustment ? '보정 화면을 여는 중…' : '촬영')),
                ),
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
                    child: _rotatedControl(Text(appText(context, '취소'))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _rotatedControl(
                      Text(
                        appText(context, _guidance),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
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

  Widget _rotatedControl(Widget child) => AnimatedRotation(
    // 센서 각도는 기기 자체가 회전한 방향이다. 세로 고정 화면 안에서 글자를
    // 사용자의 눈에 똑바로 보이게 하려면 조작 UI는 반대 방향으로 회전해야 한다.
    // JPEG EXIF·캡처에는 네이티브의 원래 센서 각도를 그대로 사용한다.
    turns: -_physicalRotationDegrees / 360,
    duration: const Duration(milliseconds: 150),
    child: child,
  );
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
  var _refreshingCorners = false;
  var _additionalCorrection = true;
  var _flattenFold = false;
  String? _failure;
  Offset? _dragStartLocalPosition;
  Offset? _dragStartImagePoint;

  /// 캔버스 확대/이동 상태의 단일 소유자. 핸들 좌표 변환은 이 값 하나만 참조한다.
  final TransformationController _view = TransformationController();

  /// 현재 확대 배율(=행렬의 스케일 성분). 핸들 드래그의 입력 스케일 보정과
  /// 핸들 크기 역보정에 쓴다.
  double get _zoom => _view.value.getMaxScaleOnAxis();

  static const double _minZoom = 1.0;
  static const double _maxZoom = 6.0; // 장변 4000px급 원본에서 1 논리픽셀 ≈ 1.5 원본픽셀

  @override
  void initState() {
    super.initState();
    _view.addListener(_onViewChanged);
  }

  @override
  void dispose() {
    _view.removeListener(_onViewChanged);
    _view.dispose();
    super.dispose();
  }

  void _onViewChanged() => setState(() {});

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
        enhancement: _additionalCorrection
            ? ImageEnhancement.enhanced
            : ImageEnhancement.none,
        flattenFold: _flattenFold,
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

  Future<void> _refreshCorners() async {
    if (_refreshingCorners || _saving) return;
    // 확대 상태에서 쿼드가 통째로 바뀌면 사용자가 방향을 잃으므로 되돌린다.
    _view.value = Matrix4.identity();
    setState(() {
      _refreshingCorners = true;
      _failure = null;
    });
    try {
      final detection = await widget.controller.detectInImage(
        widget.capture.rawImagePath,
      );
      final detectedQuad = detection?.quad;
      if (detectedQuad == null) {
        if (mounted) {
          setState(() => _failure = '문서 윤곽을 찾지 못했습니다. 현재 핀을 조정하세요.');
        }
        return;
      }
      if (mounted) {
        setState(
          () => _quad = detectedQuad.scaleToSize(widget.capture.rawImageSize),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failure = '윤곽을 다시 찾지 못했습니다. 현재 핀을 조정하세요.');
      }
    } finally {
      if (mounted) setState(() => _refreshingCorners = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C2022),
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
                    child: Text(appText(context, '다시 촬영')),
                  ),
                  Expanded(
                    child: Text(
                      appText(context, '모서리 조정'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _refreshingCorners || _saving
                        ? null
                        : _refreshCorners,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(appText(context, _refreshingCorners ? '윤곽 찾는 중…' : '윤곽 다시 찾기')),
                  ),
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
                  appText(context, _failure!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _additionalCorrection = false;
                        _flattenFold = false;
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _additionalCorrection
                            ? Colors.transparent
                            : AppTheme.seedColor,
                        side: const BorderSide(color: Color(0xFF8AA6B5)),
                      ),
                      child: Text(appText(context, '원본 컬러')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _additionalCorrection = true;
                        _flattenFold = false;
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _additionalCorrection
                            ? AppTheme.seedColor
                            : Colors.transparent,
                        side: const BorderSide(color: Color(0xFF8AA6B5)),
                      ),
                      child: Text(appText(context, '추가 보정')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _additionalCorrection = true;
                        _flattenFold = true;
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _flattenFold
                            ? AppTheme.seedColor
                            : Colors.transparent,
                        side: const BorderSide(color: Color(0xFF8AA6B5)),
                      ),
                      child: Text(appText(context, '평탄화 보정')),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                appText(context, _flattenFold
                    ? '접힘 골이 확인되면 종이를 펴 보이도록 보정합니다.'
                    : _additionalCorrection
                    ? '컬러를 유지하며 그림자와 접힌 자국의 명암을 완화합니다.'
                    : '실사 컬러와 원본 명암을 유지합니다.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFC2CCCC), fontSize: 12),
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
                      child: Text(appText(context, _saving ? '저장 중…' : '저장')),
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
    final edgeInset = _zoom > 1.01 ? 0.0 : _cornerHandleEdgeInset;
    return InteractiveViewer(
      panEnabled: true,
      scaleEnabled: true,
      minScale: _minZoom,
      maxScale: _maxZoom,
      boundaryMargin: EdgeInsets.zero,
      transformationController: _view,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: Stack(
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
                painter: _CornerPainter(
                  quad: _quad,
                  fit: fit,
                  edgeInset: edgeInset,
                ),
              ),
            ),
            ..._handles(fit, edgeInset),
          ],
        ),
      ),
    );
  }

  List<Widget> _handles(_ImageFit fit, double edgeInset) {
    return [
      _handle(
        fit,
        edgeInset,
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
        edgeInset,
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
        edgeInset,
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
        edgeInset,
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
    double edgeInset,
    Offset imagePoint,
    void Function(Offset) update,
  ) {
    final documentCorner = fit.toCanvas(imagePoint);
    final position = fit.handleAnchor(documentCorner, edgeInset: edgeInset);
    return Positioned(
      left: position.dx - _cornerHandleDiameter / 2,
      top: position.dy - _cornerHandleDiameter / 2,
      width: _cornerHandleDiameter,
      height: _cornerHandleDiameter,
      child: GestureDetector(
        onPanStart: (details) {
          // InteractiveViewer 내부(child) 좌표계로 들어오는 좌표를 쓴다 — 이
          // 제스처의 히트테스트 변환은 팬 시작 시점에 고정되므로, 확대 중에도
          // 화면 픽셀 이동이 자동으로 배율만큼 나뉘어 들어온다.
          _dragStartLocalPosition = details.localPosition;
          _dragStartImagePoint = imagePoint;
        },
        onPanUpdate: (details) {
          final pointerStart = _dragStartLocalPosition;
          final imageStart = _dragStartImagePoint;
          if (pointerStart == null || imageStart == null) return;
          final pointerDelta = details.localPosition - pointerStart;
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
          child: Transform.scale(
            scale: 1 / _zoom,
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
      ),
    );
  }

  void _clearDrag() {
    _dragStartLocalPosition = null;
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
  const _CornerPainter({
    required this.quad,
    required this.fit,
    required this.edgeInset,
  });

  final Quad quad;
  final _ImageFit fit;
  final double edgeInset;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      quad.topLeft,
      quad.topRight,
      quad.bottomRight,
      quad.bottomLeft,
    ].map(fit.toCanvas).toList();
    final handlePoints = [
      for (final point in points) fit.handleAnchor(point, edgeInset: edgeInset),
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
      oldDelegate.quad != quad ||
      oldDelegate.fit != fit ||
      oldDelegate.edgeInset != edgeInset;
}
