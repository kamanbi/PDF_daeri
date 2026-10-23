import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/app/app_locale.dart';
import 'package:pdf_daeri/app/providers.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/features/scan/local_document_scan_source.dart';
import 'package:pdf_daeri/features/scan/scan_screen.dart';

class _SequenceScanSource implements ScanSource {
  _SequenceScanSource(this._results);

  final List<PdfResult<List<String>>> _results;
  final pageLimits = <int>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PdfResult<List<String>>> scan(
    BuildContext context, {
    int pageLimit = 1,
  }) async {
    pageLimits.add(pageLimit);
    return _results[pageLimits.length - 1];
  }
}

class _RouteLog extends NavigatorObserver {
  final replaced = <Route<dynamic>?>[];
  int popCount = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaced.add(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
  }
}

Future<_RouteLog> _pump(WidgetTester tester, _SequenceScanSource source) async {
  final log = _RouteLog();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [scanSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: const [Locale('ko'), Locale('en')],
        navigatorObservers: [log],
        home: const Scaffold(body: SizedBox()),
      ),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(MaterialPageRoute<void>(builder: (_) => const ScanScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return log;
}

void main() {
  testWidgets('Android: 스캐너를 닫을 때까지 한 장씩 자동으로 다시 열고, 닫으면 모인 장을 넘긴다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final source = _SequenceScanSource([
      const PdfOk(['/tmp/1.jpg']),
      const PdfOk(['/tmp/2.jpg']),
      const PdfOk(['/tmp/3.jpg']),
      const PdfErr(Cancelled()),
    ]);

    final log = await _pump(tester, source);

    expect(source.pageLimits, [1, 1, 1, 1]);
    expect(log.replaced, hasLength(1), reason: '모인 3장은 편집 화면으로 넘어가야 한다');
    expect(log.popCount, 0, reason: '장이 있으면 홈으로 되돌아가지 않는다');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android: 한 장도 찍지 않고 닫으면 홈으로 돌아간다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final source = _SequenceScanSource([const PdfErr(Cancelled())]);

    final log = await _pump(tester, source);

    expect(source.pageLimits, [1]);
    expect(log.replaced, isEmpty);
    expect(log.popCount, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: 스캐너가 여러 장을 한 번에 돌려주므로 반복하지 않는다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final source = _SequenceScanSource([
      const PdfOk(['/tmp/1.jpg', '/tmp/2.jpg']),
    ]);

    final log = await _pump(tester, source);

    expect(source.pageLimits, [30]);
    expect(log.replaced, hasLength(1));
    debugDefaultTargetPlatformOverride = null;
  });
}
