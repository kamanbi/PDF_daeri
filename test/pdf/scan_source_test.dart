import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/features/scan/local_document_scan_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleDocumentScanSource', () {
    testWidgets('지원하지 않는 플랫폼에서는 스캐너 채널을 열지 않는다', (tester) async {
      final launcher = _FakeDocumentScanLauncher('/cache/scan.jpg');
      final source = GoogleDocumentScanSource(
        launcher: launcher,
        isSupported: () => false,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context);

      expect(await source.isAvailable(), isFalse);
      expect(
        (result as PdfErr<List<String>>).failure,
        isA<EngineUnsupported>(),
      );
      expect(launcher.openCount, 0);
    });

    testWidgets('보정된 JPEG 한 장을 기존 저장 흐름으로 반환한다', (tester) async {
      final launcher = _FakeDocumentScanLauncher('/cache/corrected.jpg');
      final source = GoogleDocumentScanSource(
        launcher: launcher,
        isSupported: () => true,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context);

      expect((result as PdfOk<List<String>>).value, ['/cache/corrected.jpg']);
      expect(launcher.openCount, 1);
    });

    testWidgets('ML Kit 준비 실패를 지원 불가로 바꾼다', (tester) async {
      final source = GoogleDocumentScanSource(
        launcher: _ThrowingDocumentScanLauncher(
          PlatformException(code: 'UNAVAILABLE'),
        ),
        isSupported: () => true,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context);

      expect(
        (result as PdfErr<List<String>>).failure,
        isA<EngineUnsupported>(),
      );
    });

    testWidgets('결과 복사 실패를 재시도 가능한 오류로 바꾼다', (tester) async {
      final source = GoogleDocumentScanSource(
        launcher: _ThrowingDocumentScanLauncher(
          PlatformException(code: 'COPY_FAILED'),
        ),
        isSupported: () => true,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context);

      expect(
        (result as PdfErr<List<String>>).failure,
        isA<ScannerUnavailable>(),
      );
    });
  });
}

Future<BuildContext> _buildContext(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
  return tester.element(find.byType(SizedBox));
}

class _FakeDocumentScanLauncher implements DocumentScanLauncher {
  _FakeDocumentScanLauncher(this.path);

  final String? path;
  int openCount = 0;

  @override
  Future<String?> open() async {
    openCount += 1;
    return path;
  }
}

class _ThrowingDocumentScanLauncher implements DocumentScanLauncher {
  const _ThrowingDocumentScanLauncher(this.error);

  final Object error;

  @override
  Future<String?> open() => Future.error(error);
}
