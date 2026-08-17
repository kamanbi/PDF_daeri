import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/data/storage/saf_import.dart';

/// [W6 2026-08-18] `MethodChannelSafImporter`의 실제 복사·표시명 추출·인텐트
/// 수신 동작은 네이티브(`MainActivity.kt`) 채널이 있어야 확인된다(체크리스트
/// 참조). 여기서는 테스트 환경(채널 핸들러 미등록 → `MissingPluginException`)에서
/// 조용히 무음 실패하지 않고 정해진 방식으로 실패/대체되는지만 고정한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelSafImporter — 채널 미연결(테스트 환경) 시 동작', () {
    test('takeInitialUri()는 예외를 던지지 않고 null을 반환한다', () async {
      final importer = MethodChannelSafImporter();
      expect(await importer.takeInitialUri(), isNull);
    });

    test('importToPath()는 EngineUnsupported로 실패한다(무음 실패 아님)', () async {
      final importer = MethodChannelSafImporter();
      final result = await importer.importToPath(
        contentUri: 'content://com.example/document/1',
        destinationPath: '/tmp/does-not-matter.pdf',
      );
      expect(result, isA<PdfErr<SafImportResult>>());
      expect((result as PdfErr<SafImportResult>).failure, isA<EngineUnsupported>());
    });

    test('onNewIntentUri()는 구독 시점까지 예외를 던지지 않는다', () {
      final importer = MethodChannelSafImporter();
      expect(() => importer.onNewIntentUri(), returnsNormally);
    });
  });
}
