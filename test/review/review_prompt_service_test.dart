import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/review/review_prompt_service.dart';

void main() {
  test(
    'requests a review once at each configured successful PDF creation threshold',
    () async {
      final preferences = _MemoryReviewPreferences();
      final reviewer = _FakeReviewRequester();
      final service = ReviewPromptService(preferences, reviewer);

      for (var completedCount = 1; completedCount <= 100; completedCount += 1) {
        await service.recordSuccessfulPdfCreation();
        final expectedRequestCount = switch (completedCount) {
          < 10 => 0,
          < 30 => 1,
          < 50 => 2,
          < 100 => 3,
          _ => 4,
        };
        expect(reviewer.requestCount, expectedRequestCount);
      }
    },
  );

  test('does not repeat the legacy tenth-creation review request', () async {
    final preferences = _MemoryReviewPreferences()
      ..writeInt('completed_pdf_count', 9)
      ..writeBool('review_request_attempted', true);
    final reviewer = _FakeReviewRequester();
    final service = ReviewPromptService(preferences, reviewer);

    await service.recordSuccessfulPdfCreation();

    expect(reviewer.requestCount, 0);
  });
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
