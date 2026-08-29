import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/features/scan/local_document_scan_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalDocumentScanSource', () {
    testWidgets('지원하지 않는 플랫폼에서는 카메라 채널을 열지 않는다', (tester) async {
      final launcher = _FakeDocumentScanLauncher(['/cache/scan.jpg']);
      final source = LocalDocumentScanSource(
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

    testWidgets('원근 보정된 모든 페이지 경로를 반환한다', (tester) async {
      final launcher = _FakeDocumentScanLauncher([
        '/cache/corrected-1.jpg',
        '/cache/corrected-2.jpg',
      ]);
      final source = LocalDocumentScanSource(
        launcher: launcher,
        isSupported: () => true,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context, pageLimit: 2);

      expect((result as PdfOk<List<String>>).value, [
        '/cache/corrected-1.jpg',
        '/cache/corrected-2.jpg',
      ]);
      expect(launcher.pageLimit, 2);
    });

    testWidgets('카메라 권한 거부를 PermissionDenied로 바꾼다', (tester) async {
      final source = LocalDocumentScanSource(
        launcher: _ThrowingDocumentScanLauncher(
          const ScannerPermissionException(),
        ),
        isSupported: () => true,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context);

      expect((result as PdfErr<List<String>>).failure, isA<PermissionDenied>());
    });

    testWidgets('원근 보정 실패를 사용자 재시도 가능한 오류로 바꾼다', (tester) async {
      final source = LocalDocumentScanSource(
        launcher: _ThrowingDocumentScanLauncher(
          const ScannerCaptureException('문서 모서리 보정에 실패했습니다.'),
        ),
        isSupported: () => true,
      );
      final context = await _buildContext(tester);

      final result = await source.scan(context);

      final failure = (result as PdfErr<List<String>>).failure;
      expect(failure, isA<UnknownFailure>());
      expect((failure as UnknownFailure).message, '문서 모서리 보정에 실패했습니다.');
    });
  });
}

Future<BuildContext> _buildContext(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
  return tester.element(find.byType(SizedBox));
}

class _FakeDocumentScanLauncher implements DocumentScanLauncher {
  _FakeDocumentScanLauncher(this.paths);

  final List<String>? paths;
  int openCount = 0;
  int? pageLimit;

  @override
  Future<List<String>?> open(
    BuildContext context, {
    required int pageLimit,
  }) async {
    openCount += 1;
    this.pageLimit = pageLimit;
    return paths;
  }
}

class _ThrowingDocumentScanLauncher implements DocumentScanLauncher {
  const _ThrowingDocumentScanLauncher(this.error);

  final Object error;

  @override
  Future<List<String>?> open(BuildContext context, {required int pageLimit}) =>
      Future.error(error);
}
