# 보안 개선 실행 계획

- 상태: 요청된 코드 수정과 로컬 검증 완료. 프로덕션 배포는 사용자 승인 전 대기.
- 구독: 활성 상태와 미만료 상품만 활성으로 판정한다. 문서화된 Google 410 영구 무효 reason만 권한을 회수하고, 404 및 기타 오류는 `unavailable`로 처리해 기존 권한을 보존한다.
- 서버: JSON 형식·본문 크기를 검증하고 IP/도메인별 호출 제한을 적용한다. 방문자 식별자는 UUID v4만 허용한다.
- 웹: CSP와 프레임 삽입 방어를 적용한다. 문의 필드 길이를 제한하고 Netlify Forms 안내를 한국어·영어로 제공한다.
- 완료 기준: Node 입력/상태 테스트, Dart 구독 회귀 테스트, JavaScript 구문 검사와 diff 공백 검사가 통과한다. 운영 배포·환경 변수 수정·APK/AAB 빌드는 별도 요청 전 하지 않는다.

## 가독성 5칙

- Early Return: 메서드, Origin, 크기, 형식 오류는 외부 호출 전 반환한다.
- Contextual Naming: `readBoundedJson`, `classifyGooglePlayFailure`, `visitorToken`으로 의도를 드러낸다.
- Magic Number Hunter: 본문 8KB/256B, 호출 빈도, 필드 길이를 상수/함수 설정으로 둔다.
- Parameter Object: 세 개 이상 입력이 필요한 새 로직은 객체 인자로 묶는다.
- Complexity Check: 작은 검증·분류 함수로 복잡도를 6/10 이하로 유지한다.
