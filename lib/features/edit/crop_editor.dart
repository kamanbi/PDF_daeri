/// 크롭 UI — 사진→PDF 생성 흐름 전용(설계 §2.2 판정 — S3에는 넣지 않는다).
///
/// 전체 화면 크롭 편집기. 이미지 1장을 받아 `CropRect`를 돌려준다. **자체 카메라·
/// 필터·보정 기능을 넣지 않는다**(절대 규칙 5) — 사각형 영역 지정 1종뿐이다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_error.dart';
import '../../pdf/page_ref.dart';

const int _cropPreviewWidthPx = 1080;
const double _handleSize = 24;

/// [page]의 크롭을 편집한다. 결과가 전체 영역(`CropRect.isFull`)이면 `null`을
/// 반환한다(크롭 없음으로 정규화, 설계 §2.6). 사용자가 취소하면 `null`을 반환한다
/// — "취소"와 "크롭 없음"을 UI 결과 값 하나로 구분하지 않는다(호출자는 어느 쪽이든
/// "이번 편집에서는 크롭을 반영하지 않는다"로 처리하면 된다).
Future<CropRect?> showCropEditor({
  required BuildContext context,
  required WidgetRef ref,
  required ImagePageRef page,
}) {
  return Navigator.of(context).push<CropRect?>(
    MaterialPageRoute(builder: (_) => _CropEditorScreen(page: page)),
  );
}

class _CropEditorScreen extends ConsumerStatefulWidget {
  const _CropEditorScreen({required this.page});
  final ImagePageRef page;

  @override
  ConsumerState<_CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends ConsumerState<_CropEditorScreen> {
  Uint8List? _bytes;
  Rect _rect = const Rect.fromLTRB(0, 0, 1, 1); // 정규화 좌표(0..1)

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.page.crop != null) {
      final c = widget.page.crop!;
      _rect = Rect.fromLTRB(c.left, c.top, c.right, c.bottom);
    }
  }

  Future<void> _load() async {
    // 표시 이미지는 크롭 없는 사본으로 얻는다(설계 §2.6) — `features/**`는
    // `package:image`를 import할 수 없으므로 `PdfRenderer`를 재사용한다.
    final renderer = ref.read(pdfRendererProvider);
    final uncropped = ImagePageRef(imagePath: widget.page.imagePath, rotation: widget.page.rotation);
    final result = await renderer.renderPageThumbnail(page: uncropped, targetWidthPx: _cropPreviewWidthPx);
    if (!mounted) return;
    if (result is PdfOk<Uint8List>) {
      setState(() => _bytes = result.value);
    }
  }

  void _reset() => setState(() => _rect = const Rect.fromLTRB(0, 0, 1, 1));

  void _apply() {
    final rect = _rect;
    final crop = CropRect(left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom);
    Navigator.of(context).pop(crop.isFull ? null : crop);
  }

  void _updateHandle(_HandlePos handlePos, Offset deltaFraction) {
    setState(() {
      var left = _rect.left;
      var top = _rect.top;
      var right = _rect.right;
      var bottom = _rect.bottom;
      const minSize = 0.05;

      if (handlePos.affectsLeft) left = (left + deltaFraction.dx).clamp(0.0, right - minSize);
      if (handlePos.affectsRight) right = (right + deltaFraction.dx).clamp(left + minSize, 1.0);
      if (handlePos.affectsTop) top = (top + deltaFraction.dy).clamp(0.0, bottom - minSize);
      if (handlePos.affectsBottom) bottom = (bottom + deltaFraction.dy).clamp(top + minSize, 1.0);

      _rect = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('자르기'),
      ),
      body: _bytes == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_bytes!, fit: BoxFit.contain),
                        _CropOverlay(rect: _rect, onHandleDrag: _updateHandle),
                      ],
                    ),
                  );
                },
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: _reset, child: const Text('초기화')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: _apply, child: const Text('적용')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8방향 핸들이 영향을 주는 변(들).
class _HandlePos {
  const _HandlePos({
    required this.affectsLeft,
    required this.affectsTop,
    required this.affectsRight,
    required this.affectsBottom,
    required this.alignment,
  });
  final bool affectsLeft;
  final bool affectsTop;
  final bool affectsRight;
  final bool affectsBottom;
  final Alignment alignment;

  static const nw = _HandlePos(affectsLeft: true, affectsTop: true, affectsRight: false, affectsBottom: false, alignment: Alignment.topLeft);
  static const n = _HandlePos(affectsLeft: false, affectsTop: true, affectsRight: false, affectsBottom: false, alignment: Alignment.topCenter);
  static const ne = _HandlePos(affectsLeft: false, affectsTop: true, affectsRight: true, affectsBottom: false, alignment: Alignment.topRight);
  static const e = _HandlePos(affectsLeft: false, affectsTop: false, affectsRight: true, affectsBottom: false, alignment: Alignment.centerRight);
  static const se = _HandlePos(affectsLeft: false, affectsTop: false, affectsRight: true, affectsBottom: true, alignment: Alignment.bottomRight);
  static const s = _HandlePos(affectsLeft: false, affectsTop: false, affectsRight: false, affectsBottom: true, alignment: Alignment.bottomCenter);
  static const sw = _HandlePos(affectsLeft: true, affectsTop: false, affectsRight: false, affectsBottom: true, alignment: Alignment.bottomLeft);
  static const w = _HandlePos(affectsLeft: true, affectsTop: false, affectsRight: false, affectsBottom: false, alignment: Alignment.centerLeft);

  static const all = [nw, n, ne, e, se, s, sw, w];
}

class _CropOverlay extends StatelessWidget {
  const _CropOverlay({required this.rect, required this.onHandleDrag});
  final Rect rect;
  final void Function(_HandlePos, Offset) onHandleDrag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final px = Rect.fromLTRB(rect.left * w, rect.top * h, rect.right * w, rect.bottom * h);

        return Stack(
          children: [
            // 크롭 영역 밖을 어둡게 덮는다.
            CustomPaint(size: Size(w, h), painter: _DimPainter(px)),
            Positioned.fromRect(
              rect: px,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.5)),
                ),
              ),
            ),
            for (final handlePos in _HandlePos.all)
              Positioned(
                left: px.left + px.width * (handlePos.alignment.x + 1) / 2 - _handleSize / 2,
                top: px.top + px.height * (handlePos.alignment.y + 1) / 2 - _handleSize / 2,
                width: _handleSize,
                height: _handleSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    onHandleDrag(handlePos, Offset(details.delta.dx / w, details.delta.dy / h));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _DimPainter oldDelegate) => oldDelegate.hole != hole;
}
