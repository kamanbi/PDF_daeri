library;

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PDF 생성 성공 횟수에 따라 Google Play 리뷰 요청을 한 번만 보낸다.
///
/// 인앱 리뷰 창의 실제 표시는 Play가 사용량 제한에 따라 결정한다. 이 서비스는
/// 저장 흐름을 막지 않으며, 요청 실패도 PDF 저장 결과에 영향을 주지 않는다.
class ReviewPromptService {
  ReviewPromptService(this._preferences, this._reviewer);

  static const int reviewRequestThreshold = 10;
  static const String _completedPdfCountKey = 'completed_pdf_count';
  static const String _reviewRequestAttemptedKey = 'review_request_attempted';

  final ReviewPreferences _preferences;
  final ReviewRequester _reviewer;

  Future<void> recordSuccessfulPdfCreation() async {
    try {
      final completedPdfCount =
          (await _preferences.readInt(_completedPdfCountKey) ?? 0) + 1;
      await _preferences.writeInt(_completedPdfCountKey, completedPdfCount);

      if (completedPdfCount != reviewRequestThreshold) return;

      final reviewRequestAttempted =
          await _preferences.readBool(_reviewRequestAttemptedKey) ?? false;
      if (reviewRequestAttempted) return;

      await _preferences.writeBool(_reviewRequestAttemptedKey, true);
      if (!await _reviewer.isAvailable()) return;
      await _reviewer.requestReview();
    } catch (_) {
      // 리뷰 요청 실패는 문서 저장 성공을 되돌리지 않는다.
    }
  }
}

abstract interface class ReviewPreferences {
  Future<int?> readInt(String key);

  Future<bool?> readBool(String key);

  Future<void> writeInt(String key, int value);

  Future<void> writeBool(String key, bool value);
}

class SharedPreferencesReviewPreferences implements ReviewPreferences {
  SharedPreferencesReviewPreferences([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<int?> readInt(String key) => _preferences.getInt(key);

  @override
  Future<bool?> readBool(String key) => _preferences.getBool(key);

  @override
  Future<void> writeInt(String key, int value) =>
      _preferences.setInt(key, value);

  @override
  Future<void> writeBool(String key, bool value) =>
      _preferences.setBool(key, value);
}

abstract interface class ReviewRequester {
  Future<bool> isAvailable();

  Future<void> requestReview();
}

class GooglePlayReviewRequester implements ReviewRequester {
  GooglePlayReviewRequester([InAppReview? review])
    : _review = review ?? InAppReview.instance;

  final InAppReview _review;

  @override
  Future<bool> isAvailable() => _review.isAvailable();

  @override
  Future<void> requestReview() => _review.requestReview();
}
