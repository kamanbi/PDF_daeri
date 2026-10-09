/// iOS 구독의 마지막 검증 거래 ID를 기기에 저장한다.
///
/// Android는 Google Play가 현재 활성 구매 목록을 주지만, iOS(StoreKit)는 앱 실행마다 활성 구독을
/// 조용히 조회하는 API가 없다(복원은 Apple ID 로그인 창을 띄울 수 있다). 그래서 서버가 활성으로 확인한
/// 거래 ID를 저장해 두었다가 실행·복귀 때 그 ID로 서버에 다시 확인해 갱신·만료를 반영한다.
/// 거래 ID는 결제 수단·개인 식별 정보가 아니다.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class IosTransactionStore {
  Future<String?> read();
  Future<void> write(String transactionId);
}

class SharedPreferencesIosTransactionStore implements IosTransactionStore {
  static const _key = 'ios_ads_removed_transaction_id';

  @override
  Future<String?> read() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(_key);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String transactionId) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        transactionId,
      );
    } catch (_) {
      // 저장 실패는 다음 구매·복원에서 다시 채워지므로 구독 처리를 막지 않는다.
    }
  }
}
