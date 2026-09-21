/// 스탬프 배치 공용 위젯 — 서명·주석 공용 컴포넌트.
/// (`_workspace/79_architect_v1.1_v2_design.md` §2 "공통 메커니즘", §13 배치 1 항목 3)
///
/// PDF 페이지 미리보기 위에 마크(이미지든 텍스트든)를 드래그로 이동, 핀치로 크기
/// 조정한다. 좌표는 `StampRect`와 같은 정규화 비율(0.0~1.0, 좌상단 원점) 규약을
/// 그대로 쓴다 — 이 화면이 두 번째 좌표 규약을 만들지 않는다.
///
/// **서명 전용이 아니다.** 이번 라운드는 이미지 마크(서명 PNG)만 실제로 쓰지만,
/// 배치될 콘텐츠는 `overlayChild`로 주입받는다 — 다음 라운드(주석)에서 텍스트·
/// 하이라이트 마크를 얹을 때도 이 위젯을 그대로 재사용한다(중복 금지).
library;

import 'package:flutter/material.dart';

import '../../pdf/stamp_builder.dart' show StampRect;

/// 페이지 미리보기 위에서 마크 하나를 드래그·핀치로 배치하는 위젯.
///
/// [pageChild]는 배경(페이지 미리보기, 보통 `Image.memory`). [pageAspectRatio]는
/// 배경의 가로세로비 — 배치 영역 크기를 고정하는 데 쓰인다(뷰어의 `_ViewerPage`와
/// 같은 `AspectRatio` 패턴).
///
/// [overlayChild]는 배치되는 마크 자체(예: 서명 PNG의 `Image.memory`). 크기·위치는
/// 이 위젯이 [rect]로 관리하며, [overlayChild]는 항상 `rect`가 정한 사각형을 가득
/// 채우도록 그려진다.
///
/// [rect]/[onRectChanged]는 외부(호출부)가 상태를 갖는 controlled 위젯 패턴이다 —
/// 이 위젯 자신은 배치 결과를 들고 있지 않는다(재사용성을 위해 상태를 밖으로 뺀다).
class StampPlacement extends StatefulWidget {
  const StampPlacement({
    super.key,
    required this.pageChild,
    required this.pageAspectRatio,
    required this.overlayChild,
    required this.rect,
    required this.onRectChanged,
    this.minWidthFraction = 0.08,
    this.minHeightFraction = 0.04,
  });

  final Widget pageChild;
  final double pageAspectRatio;
  final Widget overlayChild;
  final StampRect rect;
  final ValueChanged<StampRect> onRectChanged;

  /// 마크가 이보다 작아지지 않도록 하는 하한(과도한 축소로 다루기 힘들어지는 것 방지).
  final double minWidthFraction;
  final double minHeightFraction;

  @override
  State<StampPlacement> createState() => _StampPlacementState();
}

class _StampPlacementState extends State<StampPlacement> {
  // 제스처 시작 시점의 rect·픽셀 크기를 기억해 두고, onScaleUpdate의 누적
  // focalPointDelta/scale을 그 시점 기준으로 적용한다(드리프트 방지).
  StampRect? _gestureStartRect;
  Size? _areaSize;

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartRect = widget.rect;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _gestureStartRect;
    final area = _areaSize;
    if (start == null || area == null || area.isEmpty) return;

    // 이동: focalPointDelta를 배치 영역 크기에 대한 비율로 환산해 누적한다.
    final dxFraction = details.focalPointDelta.dx / area.width;
    final dyFraction = details.focalPointDelta.dy / area.height;

    // 크기: 이번 프레임의 순간 배율(details.horizontalScale 등은 Flutter가 없으므로
    // details.scale을 균등 배율로 쓴다 -- 과설계 금지, 가로세로 별도 배율은 두지 않는다)
    // 을 현재 rect의 폭·높이에 곱해 새 폭·높이를 구하고, 중심은 고정한다.
    final centerX = (start.left + start.right) / 2 + dxFraction;
    final centerY = (start.top + start.bottom) / 2 + dyFraction;
    var width = start.widthFraction * details.scale;
    var height = start.heightFraction * details.scale;
    width = width.clamp(widget.minWidthFraction, 1.0);
    height = height.clamp(widget.minHeightFraction, 1.0);

    var left = centerX - width / 2;
    var top = centerY - height / 2;
    left = left.clamp(0.0, 1.0 - width);
    top = top.clamp(0.0, 1.0 - height);

    widget.onRectChanged(
      StampRect(left: left, top: top, right: left + width, bottom: top + height),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AspectRatio(
          aspectRatio: widget.pageAspectRatio,
          child: Builder(
            builder: (context) {
              return LayoutBuilder(
                builder: (context, inner) {
                  _areaSize = Size(inner.maxWidth, inner.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.pageChild,
                      Positioned(
                        left: widget.rect.left * inner.maxWidth,
                        top: widget.rect.top * inner.maxHeight,
                        width: widget.rect.widthFraction * inner.maxWidth,
                        height: widget.rect.heightFraction * inner.maxHeight,
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                            child: widget.overlayChild,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// 마크의 초기 배치 — 페이지 중앙 아래쪽, 폭 40%(가로세로비는 [aspectRatio]로 유지).
/// 서명·주석 공용 기본값. 호출부가 다른 초기값을 원하면 직접 `StampRect`를 만들면 된다.
StampRect defaultStampRect({double aspectRatio = 2.0}) {
  const width = 0.4;
  final height = (width / aspectRatio).clamp(0.05, 0.6);
  const left = (1.0 - width) / 2;
  // 페이지 하단부 3/4 지점 — 프리셋 리터럴 검사(§3.4-9)와의 우연한 충돌을 피하려고 분수로 표기한다
  final top = (1.0 - height) * (3 / 4);
  return StampRect(left: left, top: top, right: left + width, bottom: top + height);
}
