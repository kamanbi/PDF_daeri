import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/app/app_locale.dart';

import 'package:pdf_daeri/features/edit/stamp_placement.dart';
import 'package:pdf_daeri/pdf/stamp_builder.dart' show StampRect;

void main() {
  group('defaultStampRect', () {
    test('가로세로비가 클수록 낮은 높이의 rect를 만든다', () {
      final wide = defaultStampRect(aspectRatio: 4.0);
      final narrow = defaultStampRect(aspectRatio: 1.0);
      expect(wide.heightFraction, lessThan(narrow.heightFraction));
      expect(wide.widthFraction, closeTo(0.4, 1e-9));
    });

    test('항상 유효한 StampRect 불변식을 만족한다(0~1, right>left, bottom>top)', () {
      final rect = defaultStampRect(aspectRatio: 0.2); // 극단적 세로 비율
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1));
      expect(rect.bottom, lessThanOrEqualTo(1));
      expect(rect.right, greaterThan(rect.left));
      expect(rect.bottom, greaterThan(rect.top));
    });
  });

  group('StampPlacement', () {
    Widget harness(StampRect rect, ValueChanged<StampRect> onChanged) {
      return MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: appLocalizationDelegates,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: StampPlacement(
              pageAspectRatio: 1.0,
              pageChild: const ColoredBox(color: Colors.white),
              overlayChild: const ColoredBox(color: Colors.red),
              rect: rect,
              onRectChanged: onChanged,
            ),
          ),
        ),
      );
    }

    testWidgets('초기 rect대로 오버레이가 배치된다', (tester) async {
      const rect = StampRect(left: 0.2, top: 0.2, right: 0.5, bottom: 0.4);
      await tester.pumpWidget(harness(rect, (_) {}));

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      // 300x300 정사각 배치 영역 기준 -- left=0.2*300=60, top=0.2*300=60.
      expect(positioned.left, closeTo(60, 0.5));
      expect(positioned.top, closeTo(60, 0.5));
    });

    testWidgets('드래그하면 onRectChanged가 이동된 rect로 호출된다', (tester) async {
      const rect = StampRect(left: 0.3, top: 0.3, right: 0.6, bottom: 0.5);
      StampRect? changed;
      await tester.pumpWidget(harness(rect, (r) => changed = r));

      // 오버레이(빨간 상자) 중앙에서 드래그 시작 -> 우측 아래로 이동.
      final overlayCenter = tester.getCenter(find.byType(GestureDetector));
      final gesture = await tester.startGesture(overlayCenter);
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(changed, isNotNull);
      // 폭 300px 기준 30px 이동 = 0.1 비율만큼 오른쪽/아래로 이동해야 한다.
      expect(changed!.left, greaterThan(rect.left));
      expect(changed!.top, greaterThan(rect.top));
      // 순수 이동이므로 폭·높이는 그대로 유지된다.
      expect(changed!.widthFraction, closeTo(rect.widthFraction, 0.01));
      expect(changed!.heightFraction, closeTo(rect.heightFraction, 0.01));
    });

    testWidgets('rect가 배치 영역 밖으로 나가지 않게 clamp된다', (tester) async {
      const rect = StampRect(left: 0.0, top: 0.0, right: 0.3, bottom: 0.3);
      StampRect? changed;
      await tester.pumpWidget(harness(rect, (r) => changed = r));

      final overlayCenter = tester.getCenter(find.byType(GestureDetector));
      final gesture = await tester.startGesture(overlayCenter);
      // 좌상단 방향으로 크게 드래그 -- 음수 좌표로 나가려 시도한다.
      await gesture.moveBy(const Offset(-500, -500));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(changed, isNotNull);
      expect(changed!.left, greaterThanOrEqualTo(0));
      expect(changed!.top, greaterThanOrEqualTo(0));
    });
  });
}
