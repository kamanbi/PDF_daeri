/// 재현 테스트 — `_workspace/28_build-runner_intent_device.md` 실기기 발견 사항.
///
/// 실기기에서 warm start VIEW 인텐트(`am start ... -d file:///sdcard/Download/fixture.pdf`)를
/// 보내면 콘솔에 다음 예외가 찍혔다:
///   "Could not find a generator for route RouteSettings("/sdcard/Download/fixture.pdf", null)"
///
/// 원인(확인됨, `_workspace/29_platform-integration_intent_route_fix.md` 참고):
/// `FlutterActivity.shouldHandleDeeplinking()`의 기본값은 manifest에
/// `flutter_deeplinking_enabled` 메타데이터가 없으면 **true**다
/// (flutter/engine `FlutterActivityLaunchConfigs.deepLinkEnabled`). 이 프로젝트의
/// `AndroidManifest.xml`에는 그 메타데이터가 없었으므로, `onNewIntent`가 호출될 때마다
/// Flutter 엔진이 intent의 `data`(URI)를 **자체적으로** `flutter/navigation`
/// 시스템 채널의 `pushRouteInformation`으로 Dart 쪽에 밀어넣는다. 이는 우리가 만든
/// `IncomingIntentService`(EventChannel)와는 완전히 별개의 경로다.
///
/// 네이티브 `onNewIntent`/`shouldHandleDeeplinking()`은 위젯 테스트로 재현할 수
/// 없으므로(실기기 필요 — build-runner 몫), 여기서는 그 네이티브 동작이 Dart 쪽에
/// 도달했을 때 Flutter 프레임워크가 실제로 무엇을 하는지를 **정확히 같은 메커니즘**
/// (`flutter/navigation` MethodChannel, `JSONMethodCodec`, `pushRouteInformation`
/// 메서드)으로 시뮬레이션해 재현한다.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_daeri/app/app.dart';

Future<void> _simulatePushRouteInformation(WidgetTester tester, String location) async {
  // FlutterActivityAndFragmentDelegate.onNewIntent()가 shouldHandleDeeplinking()==true일 때
  // 실제로 보내는 것과 동일한 메시지(SystemChannels.navigation: 'flutter/navigation',
  // JSONMethodCodec, method 'pushRouteInformation', RouteInformation{location, state}).
  final byteData = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{'location': location, 'state': null}),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    byteData,
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '외부 VIEW 인텐트의 원시 파일 경로가 flutter/navigation 채널로 유입돼도 앱이 죽지 않는다',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: PdfDaeriApp()));
      await tester.pumpAndSettle();

      // 홈 화면에서 시작한다.
      expect(find.text('스캔'), findsOneWidget);

      // 실기기 로그에서 관찰된 것과 동일한 문자열("file://" 스킴이 제거된 형태).
      await _simulatePushRouteInformation(tester, '/sdcard/Download/fixture.pdf');

      // 수정 전: onGenerateRoute가 이 이름을 처리하지 못하고 onUnknownRoute도
      // 없어 위젯 라이브러리가 예외를 캐치해 기록한다(tester.takeException()에 잡힘).
      // 수정 후: onUnknownRoute가 예외를 흡수해 아무 것도 남기지 않는다.
      expect(tester.takeException(), isNull);

      // 예외가 흡수된 뒤에도 앱은 여전히 정상 화면(홈)에 남아 있어야 한다 —
      // 빈 화면이나 크래시 흔적이 아니어야 한다.
      expect(find.text('스캔'), findsOneWidget);
    },
  );
}
