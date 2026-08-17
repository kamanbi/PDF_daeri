import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/pdf/scan_source.dart';

/// [W6 2026-08-18] `MlKitScanSource`/`FilePickerPhotoSource`의 실제 스캔·선택
/// 동작은 플랫폼 채널·실기기 없이는 결정적으로 재현할 수 없다(체크리스트 참조).
/// 여기서는 빌드 없이도 검증 가능한 계약만 고정한다:
/// - 테스트 호스트(데스크톱/CI)는 Android가 아니므로 `isAvailable()`은 false여야 하고,
///   `scan()`은 MethodChannel을 건드리지 않고 즉시 EngineUnsupported로 실패해야 한다
///   (스캐너 초기화 시도 자체가 없어야 앱이 죽지 않는다).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MlKitScanSource', () {
    test('테스트 호스트(비-Android)에서 isAvailable()은 false다', () async {
      final source = MlKitScanSource();
      expect(await source.isAvailable(), isFalse);
    });

    test('비-Android에서 scan()은 채널을 건드리지 않고 EngineUnsupported로 즉시 실패한다', () async {
      final source = MlKitScanSource();
      final result = await source.scan();
      expect(result, isA<PdfErr<List<String>>>());
      final failure = (result as PdfErr<List<String>>).failure;
      expect(failure, isA<EngineUnsupported>());
      expect((failure as EngineUnsupported).capability, 'mlkit_document_scanner');
    });
  });
}
