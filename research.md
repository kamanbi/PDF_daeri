# 광고 제거 연간 구독 현재 상태

- `ads_removed`는 연 4,990원 자동 갱신 구독으로 전환하도록 앱·홈페이지·환불 규정을 갱신했다.
- Android 앱은 Google Play의 활성 구독 목록을 앱 시작과 수동 갱신 시 조회해 `settings.ads_removed` 캐시를 동기화한다. 조회 실패 시 직전 캐시를 유지한다.
- 설정은 Play Console의 실제 현지 가격을 표시하며, 활성 구독의 Google Play 관리·취소 페이지를 연다.
- 공개 홈페이지 `https://verdant-pixie-350067.netlify.app`와 환불 규정에 구독 가격·자동 갱신·관리/취소 경로가 배포돼 있다.
- 최종 릴리즈 산출물은 `com.kamanbi.pdf_daeri` 버전 `1.0.2`(versionCode 3)이며, APK와 AAB 모두 외부 릴리즈 키로 서명됐다.
- `ads_removed`가 Play Console에 일회성 상품으로 이미 생성됐다면 같은 ID를 구독으로 변경할 수 없다. 이 경우 새 구독 ID를 정하고 앱 상수를 함께 바꿔야 한다.
- 서버 영수증 검증은 없다. 기기 내 Google Play 활성 구매 목록을 기준으로 판정하므로 즉시 철회·다중 기기 검증을 보장하려면 별도 서버가 필요하다.
