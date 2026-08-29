# 광고 제거 연간 구독 전환 계획

## 완료 기준

1. 앱이 연간 자동 갱신 구독을 결제하고 활성 기간에만 광고를 제거한다. 완료
2. 설정과 홈페이지가 연 4,990원, 자동 갱신, 관리·취소 경로를 표시한다. 완료
3. 최종 릴리즈 APK와 AAB가 서명돼 생성된다. 완료
4. Google Play Console에서 구독을 활성화하고 실제 결제·취소·만료를 검증한다. 진행 필요

## 남은 작업

1. Play Console에서 구독 상품 ID `ads_removed`를 만들고 연간 자동 갱신 기본 요금제를 ₩4,990으로 활성화한다.
2. 이미 같은 ID의 일회성 상품이 있으면 새 ID를 확정한 뒤 앱 상수와 관리 링크를 변경한다.
3. AAB를 내부 테스트 트랙에 올린 뒤 결제, 취소 후 기간 유지, 만료 후 광고 재표시를 실기기로 확인한다.

## 가독성 설계

- Early Return: 결제 불가·상품 없음·오퍼 토큰 없음에서는 구독 결제를 시작하지 않는다.
- Contextual Naming: `syncSubscriptionEntitlement`, `activeSubscription`, `kSubscriptionManageUrl`로 역할을 분리했다.
- Magic Number Hunter: 가격은 코드에 넣지 않고 Play Console 상품 가격을 사용한다.
- Parameter Object: `GooglePlayPurchaseParam`에 구독 오퍼 토큰을 전달한다.
- Complexity Check: 구독 상태 조회와 화면 표기를 분리해 8/10을 유지한다.
