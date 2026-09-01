import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/review/review_prompt_service.dart';

void main() {
  test(
    'requests a review only after the tenth successful PDF creation',
    () async {
      final preferences = _MemoryReviewPreferences();
      final reviewer = _FakeReviewRequester();
      final service = ReviewPromptService(preferences, reviewer);

      for (var index = 0; index < 9; index += 1) {
        await service.recordSuccessfulPdfCreation();
      }

      expect(reviewer.requestCount, 0);

      await service.recordSuccessfulPdfCreation();
      await service.recordSuccessfulPdfCreation();

      expect(reviewer.requestCount, 1);
    },
  );
}

class _MemoryReviewPreferences implements ReviewPreferences {
  final Map<String, Object> _values = {};

  @override
  Future<int?> readInt(String key) async => _values[key] as int?;

  @override
  Future<bool?> readBool(String key) async => _values[key] as bool?;

  @override
  Future<void> writeInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value;
  }
}

class _FakeReviewRequester implements ReviewRequester {
  var requestCount = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> requestReview() async {
    requestCount += 1;
  }
}
