/// Google Play 구독 구매 토큰의 서버 검증 경계.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

const String kAdsRemovedProductId = 'ads_removed';

class SubscriptionVerificationRequest {
  const SubscriptionVerificationRequest({
    required this.productId,
    required this.purchaseToken,
  });

  final String productId;
  final String purchaseToken;

  Map<String, String> toJson() => {
    'productId': productId,
    'purchaseToken': purchaseToken,
  };
}

class SubscriptionVerificationResponse {
  const SubscriptionVerificationResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

abstract interface class SubscriptionVerifier {
  Future<SubscriptionVerificationResult> verify(PurchaseDetails purchase);
}

/// 서버 검증의 결과를 실제 만료와 통신·서버 장애로 분리한다.
///
/// [unavailable]은 구매 권한을 새로 주지는 않지만, 이미 저장된 권한을 해제할
/// 근거도 아니다. 이 구분이 없으면 일시적인 503·시간초과에 구독자가 광고 사용자로
/// 되돌아간다.
enum SubscriptionVerificationResult { active, inactive, unavailable }

/// 여러 과거 구매의 서버 검증 결과를 하나의 권한 판정으로 합친다.
///
/// 활성 구매가 하나라도 있으면 [active]다. 활성 여부를 확인할 수 없는 구매가
/// 있으면 [unavailable]로 캐시를 보존한다. 나머지는 Play와 서버가 모두 비활성을
/// 확인한 [inactive]다.
SubscriptionVerificationResult resolveSubscriptionEntitlement(
  Iterable<SubscriptionVerificationResult> verificationResults,
) {
  var verificationUnavailable = false;
  for (final result in verificationResults) {
    if (result == SubscriptionVerificationResult.active) return result;
    if (result == SubscriptionVerificationResult.unavailable) {
      verificationUnavailable = true;
    }
  }
  return verificationUnavailable
      ? SubscriptionVerificationResult.unavailable
      : SubscriptionVerificationResult.inactive;
}

typedef SubscriptionVerificationTransport =
    Future<SubscriptionVerificationResponse> Function(
      SubscriptionVerificationRequest request,
    );

/// 앱은 구매 토큰을 서버에만 전달하고, Google Play Developer API 자격증명은
/// Netlify 환경 변수에만 둔다. 네트워크·응답 실패는 새 권한을 주지 않으며,
/// 기존 권한을 해제하지도 않는다.
class RemoteSubscriptionVerifier implements SubscriptionVerifier {
  RemoteSubscriptionVerifier({SubscriptionVerificationTransport? transport})
    : _transport = transport ?? _postToVerifier;

  static final Uri _endpoint = Uri.https(
    'pdf-daeri.netlify.app',
    '/.netlify/functions/verify-subscription',
  );

  final SubscriptionVerificationTransport _transport;

  @override
  Future<SubscriptionVerificationResult> verify(
    PurchaseDetails purchase,
  ) async {
    if (purchase.productID != kAdsRemovedProductId) {
      return SubscriptionVerificationResult.inactive;
    }
    final purchaseToken = purchase.verificationData.serverVerificationData
        .trim();
    if (purchaseToken.isEmpty) return SubscriptionVerificationResult.inactive;

    try {
      final response = await _transport(
        SubscriptionVerificationRequest(
          productId: purchase.productID,
          purchaseToken: purchaseToken,
        ),
      );
      return classifyResponse(response);
    } catch (_) {
      return SubscriptionVerificationResult.unavailable;
    }
  }

  /// HTTP 200의 명시적인 활성·비활성만 권한 변경 근거로 삼긴다.
  /// 인증·서버·네트워크 오류와 잘못된 응답은 모두 기존 캐시 보존 대상이다.
  static SubscriptionVerificationResult classifyResponse(
    SubscriptionVerificationResponse response,
  ) {
    if (response.statusCode != HttpStatus.ok) {
      return SubscriptionVerificationResult.unavailable;
    }
    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, Object?>) {
        return SubscriptionVerificationResult.unavailable;
      }
      return switch (payload['status']) {
        'active' => SubscriptionVerificationResult.active,
        'inactive' => SubscriptionVerificationResult.inactive,
        _ => SubscriptionVerificationResult.unavailable,
      };
    } on FormatException {
      return SubscriptionVerificationResult.unavailable;
    }
  }

  static Future<SubscriptionVerificationResponse> _postToVerifier(
    SubscriptionVerificationRequest request,
  ) async {
    final client = HttpClient();
    try {
      final httpRequest = await client
          .postUrl(_endpoint)
          .timeout(const Duration(seconds: 10));
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set(
        HttpHeaders.acceptHeader,
        ContentType.json.mimeType,
      );
      httpRequest.write(jsonEncode(request.toJson()));
      final httpResponse = await httpRequest.close().timeout(
        const Duration(seconds: 10),
      );
      return SubscriptionVerificationResponse(
        statusCode: httpResponse.statusCode,
        body: await utf8.decoder.bind(httpResponse).join(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
