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
      // [2026-08-26 · 보안점검 전체 회귀 중 발견] 기본 테스트 뷰포트(논리 800×600,
      // 실제 폰보다 가로로 훨씬 넓고 세로로 짧다)에서는 3.5주차 디자인 패스로 커진
      // 홈 화면 상단 소개 문구(_HomeIntro) 때문에 `_EntryPoints`(스캔 버튼)가
      // CustomScrollView의 기본 cacheExtent 밖으로 밀려나 애초에 빌드되지 않는다
      // (스크롤 안 한 게 아니라 렌더 트리에 존재 자체를 안 함 — SliverToBoxAdapter
      // 개수로 확인). 실기기는 세로가 훨씬 길어(예: 360×800dp) 이 문제가 없다.
      // 실제 폰 비율로 뷰포트를 맞춰 재현 조건을 실사용 환경에 가깝게 만든다.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: PdfDaeriApp()));
      await tester.pumpAndSettle();

      // 홈 화면에서 시작한다. [2026-09-01 · Windows 포팅 W3] "스캔"은
      // `AppFeatures.scan`(Android 전용)이 거짓인 플랫폼에서 렌더 트리에서
      // 제외된다(68 §6) — 이 테스트가 실행되는 호스트가 그 대상일 수 있으므로,
      // 모든 플랫폼에 항상 존재하는 "PDF 열기" 버튼으로 홈 화면 도달을 확인한다.
      expect(find.text('PDF 열기'), findsOneWidget);

      // 실기기 로그에서 관찰된 것과 동일한 문자열("file://" 스킴이 제거된 형태).
      await _simulatePushRouteInformation(tester, '/sdcard/Download/fixture.pdf');

      // 수정 전: onGenerateRoute가 이 이름을 처리하지 못하고 onUnknownRoute도
      // 없어 위젯 라이브러리가 예외를 캐치해 기록한다(tester.takeException()에 잡힘).
      // 수정 후: onUnknownRoute가 예외를 흡수해 아무 것도 남기지 않는다.
      expect(tester.takeException(), isNull);

      // 예외가 흡수된 뒤에도 앱은 여전히 정상 화면(홈)에 남아 있어야 한다 —
      // 빈 화면이나 크래시 흔적이 아니어야 한다.
      expect(find.text('PDF 열기'), findsOneWidget);
    },
  );
}
