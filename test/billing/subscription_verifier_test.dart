import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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

  iosTests();

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

class _FakePurchase extends PurchaseDetails {
  _FakePurchase({String? id, String token = 'receipt-data'})
    : super(
        purchaseID: id,
        productID: kAdsRemovedProductId,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: token,
          source: 'app_store',
        ),
        transactionDate: null,
        status: PurchaseStatus.purchased,
      );
}

void iosTests() {
  group('iOS 거래 ID 검증 요청', () {
    test('요청 JSON은 platform=ios와 거래 ID만 담고 영수증·토큰은 담지 않는다', () {
      const request = SubscriptionVerificationRequest.ios(
        productId: kAdsRemovedProductId,
        transactionId: '2000000123456789',
      );
      expect(request.toJson(), {
        'platform': 'ios',
        'productId': 'ads_removed',
        'transactionId': '2000000123456789',
      });
    });

    test('Android 요청 JSON은 기존 형식을 유지한다', () {
      const request = SubscriptionVerificationRequest(
        productId: kAdsRemovedProductId,
        purchaseToken: 'token',
      );
      expect(request.toJson(), {
        'productId': 'ads_removed',
        'purchaseToken': 'token',
      });
    });

    test('iOS 구매는 purchaseID(거래 ID)로 서버에 확인한다', () async {
      SubscriptionVerificationRequest? sent;
      final verifier = RemoteSubscriptionVerifier(
        isIos: () => true,
        transport: (request) async {
          sent = request;
          return const SubscriptionVerificationResponse(
            statusCode: 200,
            body: '{"status":"active"}',
          );
        },
      );
      final result = await verifier.verify(_FakePurchase(id: ' 777 '));
      expect(result, SubscriptionVerificationResult.active);
      expect(sent!.toJson(), {
        'platform': 'ios',
        'productId': 'ads_removed',
        'transactionId': '777',
      });
    });

    test('iOS 구매에 거래 ID가 없으면 서버를 부르지 않고 비활성이다', () async {
      var called = false;
      final verifier = RemoteSubscriptionVerifier(
        isIos: () => true,
        transport: (request) async {
          called = true;
          throw StateError('호출되면 안 된다');
        },
      );
      expect(
        await verifier.verify(_FakePurchase(id: null)),
        SubscriptionVerificationResult.inactive,
      );
      expect(called, isFalse);
    });

    test('네트워크 실패는 판단 불가로 기존 권한을 보존한다', () async {
      final verifier = RemoteSubscriptionVerifier(
        isIos: () => true,
        transport: (request) async => throw const SocketException('offline'),
      );
      expect(
        await verifier.verifyIosTransaction('1'),
        SubscriptionVerificationResult.unavailable,
      );
    });
  });
}
