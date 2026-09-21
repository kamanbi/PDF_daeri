import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/billing/subscription_verifier.dart';

void main() {
  group('RemoteSubscriptionVerifier.classifyResponse', () {
    test('명시적 active 응답만 활성 구독으로 판단한다', () {
      final result = RemoteSubscriptionVerifier.classifyResponse(
        const SubscriptionVerificationResponse(
          statusCode: 200,
          body: '{"status":"active"}',
        ),
      );

      expect(result, SubscriptionVerificationResult.active);
    });

    test('명시적 inactive 응답은 광고 제거를 해제할 수 있다', () {
      final result = RemoteSubscriptionVerifier.classifyResponse(
        const SubscriptionVerificationResponse(
          statusCode: 200,
          body: '{"status":"inactive"}',
        ),
      );

      expect(result, SubscriptionVerificationResult.inactive);
    });

    test('503과 잘못된 본문은 기존 권한 보존 대상이다', () {
      expect(
        RemoteSubscriptionVerifier.classifyResponse(
          const SubscriptionVerificationResponse(statusCode: 503, body: ''),
        ),
        SubscriptionVerificationResult.unavailable,
      );
      expect(
        RemoteSubscriptionVerifier.classifyResponse(
          const SubscriptionVerificationResponse(statusCode: 200, body: '{}'),
        ),
        SubscriptionVerificationResult.unavailable,
      );
    });
  });

  group('resolveSubscriptionEntitlement', () {
    test('활성 구매 하나가 있으면 활성이다', () {
      expect(
        resolveSubscriptionEntitlement([
          SubscriptionVerificationResult.inactive,
          SubscriptionVerificationResult.active,
        ]),
        SubscriptionVerificationResult.active,
      );
    });

    test('서버 검증 불가가 있으면 비활성으로 롤백하지 않는다', () {
      expect(
        resolveSubscriptionEntitlement([
          SubscriptionVerificationResult.inactive,
          SubscriptionVerificationResult.unavailable,
        ]),
        SubscriptionVerificationResult.unavailable,
      );
    });

    test('확인된 비활성 구매만 있으면 비활성이다', () {
      expect(
        resolveSubscriptionEntitlement([
          SubscriptionVerificationResult.inactive,
        ]),
        SubscriptionVerificationResult.inactive,
      );
    });
  });
}
