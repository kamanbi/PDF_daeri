# PDF 대리 보안 현황

- Android 앱은 구독 구매 토큰을 `verify-subscription` 함수로 보내고, 함수는 Google Play Developer API를 호출한다. 함수는 웹사이트와 함께 배포되며 자격 증명은 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` 런타임 변수에서 읽는다.
- 정상 응답은 구독 상태·상품 ID·만료시각으로 판정한다. 앱은 검증 불가 응답에서 기존 권한을 보존한다. Google 문서상 410 영구 무효 reason만 확정 무효로 구별 가능하다.
- 방문자 함수는 UUID v4를 해시해 Netlify Blobs에 일일·누적 집계를 저장한다. 문의 폼은 Netlify Forms와 honeypot을 사용한다.
- 정적 파일과 `netlify/functions/`는 한 Netlify 배포에 포함된다. Functions 환경 변수 목록에서 서비스 계정 변수 이름은 확인했으나 값은 읽거나 출력하지 않았다.
- 비밀 패턴 점검, Pub 의존성 advisory 조회, `npm audit`에서 알려진 취약점은 발견되지 않았다. PDF 수신은 100MB 제한과 헤더 검사를 하지만 파서 복잡도·메모리 상한은 별도 제한이 없다.
- Netlify Forms 제출은 사이트 Forms 대시보드에서 확인·삭제할 수 있다. 실제 계정의 처리 지역·보유 설정은 코드만으로 확인할 수 없다.
