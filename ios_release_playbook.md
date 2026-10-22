# Android Flutter 앱 → iOS 출시 플레이북 (Mac 없이)

PDF 대리 iOS 출시 과정(2026-10)에서 겪은 시행착오를 기준으로 정리했다. 다음 앱은 이 순서대로 하면 같은 실수를 피할 수 있다.
비밀값(키·ID)은 이 문서에 쓰지 않는다. 각 앱의 키 폴더(`F:\keys\<앱>`)에만 둔다.

---

## 0. 먼저 결정할 것 (착수 전)

| 결정 | PDF 대리에서의 선택 | 메모 |
|---|---|---|
| 계정 유형 | 개인 가입 → 조직 전환 | **개인사업자(법인 아님)도 D-U-N-S로 조직 승인됨.** 전환 요청부터 완료까지 약 5일 |
| 빌드 방식 | Codemagic 클라우드 macOS | 무료 개인 플랜 월 500분, 큐 대기 수십 분 |
| 광고 | AdMob, ATT 없이 비맞춤형 | iOS 앱 ID는 Android와 **별도 생성** |
| 구독 | 연간 1개 | Android 가격·약관과 맞춘다. 가격 문서 불일치 먼저 정리 |
| 서버 검증 | 기존 Netlify 함수에 Apple 분기만 추가 | 새 서버·함수 금지(프로젝트 규칙) |

**한 번에 하나의 Apple ID로 시작한다.** 계정 유형을 중간에 바꾸면 TestFlight 테스터가 철회된다(아래 4번).

---

## 1. Apple 계정·계약 (가장 오래 걸린다, 먼저 시작)

1. Apple Developer Program 가입 → 승인까지 대기.
2. 주소·이름이 사업자등록증과 다르면 **조직 전환**을 요청한다. 개인 주소 변경 케이스는 "부적합"으로 반려됐다. 전환 양식에 D-U-N-S와 사업자등록증(영문)을 쓴다.
   - **사업자등록증명에는 주민등록번호가 노출된다. 업로드할 땐 가린 사본을 쓴다.**
3. 번들 ID 등록, 앱 레코드(ASC) 생성.
4. **유료 앱 계약은 조직 전환이 끝난 뒤에** 서명한다. 법인 정보 → 한국 규정 → DSA → 계약 서명 → 세금 → 은행 순서.
   - 한국 연락처 정보는 한국 App Store 페이지에 **공개**된다. 사업용 전화·이메일을 쓴다.
   - EU DSA: EU 판매를 안 할 거면 "거래자 아님 / EU 배포 계획 없음"이 가장 간단하다.
5. 세금: 미국 양식 1개 + 한국 세금 양식. **조직 유형이면 W-8BEN-E가 필요할 가능성이 크다**(짧은 "Certificate of Foreign Status" 양식만 내면 계약이 "사용자 정보 대기 중"에 머물 수 있다 — 이 앱에서 관찰, 원인 확정은 아님). 엔티티 유형 선택은 세무사·Apple 지원 확인 후 제출한다. 제출 후 수정 불가.
6. 은행 반영 24시간, 한국 세금 양식 검토 대기. **계약이 "활성화됨"이어야 StoreKit이 구독 상품을 내려주는 것으로 보인다**(추정).

---

## 2. 코드·프로젝트 준비

- `ios/` 생성, 번들 ID·iOS 16+·iPhone 전용.
- **Google Play 문구가 iOS 화면에 남지 않게 한다.** 설정 화면의 "칭찬하기", 구독 관리, 갱신 안내 등. 다른 스토어 언급은 심사 거절 사유이고 스크린샷에도 찍힌다. 출시 전에 `grep -rn "Google Play\|play.google" lib`로 사용자 노출 문자열을 점검한다.
- Android 전용 기능은 플랫폼 플래그로 끈다(예: `storeUpdate`).
- 스캔은 VisionKit(`VNDocumentCameraViewController`), 파일 열기는 SceneDelegate에서 "open in" URL을 채널로 전달.
- Info.plist 필수: 카메라·사진 사용 설명, `ITSAppUsesNonExemptEncryption=false`(수출 규정 질문과 일치), `GADApplicationIdentifier`, SKAdNetwork, `PrivacyInfo.xcprivacy`.
- **AdMob 앱 ID를 Info.plist에 넣지 않으면 앱 실행 직후 충돌한다**(`GADApplicationVerifyPublisherInitializedCorrectly`). 빌드 1번째 TestFlight에서 겪었다.
- C/C++ 네이티브 라이브러리는 static arm64로 빌드해 `-force_load`로 링크하고 `DynamicLibrary.process()`로 연다. 빌드 스크립트에 심볼 존재 검사를 넣는다.

---

## 3. Codemagic (`codemagic.yaml`)

- 워크플로 2개: `ios-ci`(서명 없음, analyze·test는 실패해도 계속), `ios-release`(수동, TestFlight 업로드).
- 서명은 **App Store Connect API 키 통합** + `app-store-connect fetch-signing-files`로 자동 생성. 인증서 개인 키는 변수 그룹(`CERTIFICATE_PRIVATE_KEY`)에 둔다.
- 변수 그룹: AdMob iOS 앱 ID / 배너 / 전면 ID. 빌드에서 없으면 **실패하게** 하고, 최종 바이너리에서 PlistBuddy로 ID를 다시 검사한다. **광고 ID 주입 누락은 절대 반복하지 않는다.**
- `flutter build ipa`에 `--build-number=$BUILD_NUMBER`가 들어가므로 **TestFlight에 표시되는 빌드 번호는 pubspec의 +N이 아니라 Codemagic 순번**이다. 사용자에게 "(25)"가 아니라 "(9)"를 찾으라고 안내해야 한다. 버전 문자열(1.1.25)은 매 빌드 올려서 구분한다.
- "finished with post-processing failed"는 **실제 실패가 아니다.** 외부 베타 심사 제출이 "Beta App Description 누락"으로 거절된 것이고 내부 테스트 설치는 된다. 신경 쓰이면 `submit_to_testflight: false`로 바꾼다.
- Flutter 신버전 lint 실패는 분석 범위를 `lib test`로 좁히고 비차단으로 돌려서 해결했다.
- 무료 플랜은 큐 대기가 길다. 빌드 요청 후 바로 결과를 기대하지 않는다.
- **Codemagic 로그인은 브라우저 프로필마다 풀려 있을 수 있다.** 빌드 시작 전에 로그인 상태를 확인한다.

---

## 4. TestFlight

- 내부 테스트 그룹 + 본인 Apple ID를 추가한다. 상태는 "테스트 준비 완료"가 뜬다.
- **계정 유형(개인→조직) 전환 후 내부 테스터가 `REVOKED`가 된다.** iPhone에는 "개발자가 해당 테스트 프로그램에서 사용자를 삭제했습니다"가 뜬다. 해결: ASC API(`POST /v1/betaTesters`, 기존 철회 레코드는 무시)로 **새 테스터를 만들고 그룹에 넣고** 초대 메일을 다시 수락한다.
- 충돌 로그는 ASC API(`/v1/apps/{id}/betaFeedbackCrashSubmissions` 등)로 가져올 수 있다. 키 값은 출력하지 않는다.
- 첫 실행에 죽으면 AdMob ID·Info.plist 키 누락부터 본다.

---

## 5. 구독(IAP) — 가장 많이 헤맨 부분

1. ASC에서 구독 그룹 + 상품 생성. 가격·판매 국가·한국어 현지화 입력.
2. **구독 그룹 현지화(그룹 표시 이름)도 입력**한다. API로 확인하면 현지화가 비어 있을 수 있다.
3. **심사용 스크린샷이 없으면 상태가 `MISSING_METADATA`**이고 앱에서 상품이 안 내려와 "지금 구독할 수 없습니다"가 뜬다. 스크린샷을 올리면 `READY_TO_SUBMIT`이 된다(이 앱에서 확인). 제출 전에 **실제 구독 화면 스크린샷으로 교체**해야 한다.
4. 상품 상태 확인 스크립트: ASC API `GET /v1/subscriptionGroups/{id}/subscriptions`, `.../subscriptionLocalizations`, `.../appStoreReviewScreenshot`.
5. 구독이 안 내려올 때 점검 순서: 상품 상태 → **유료 앱 계약 상태** → 세금·은행 → 번들 ID·상품 ID 일치.
6. 서버(Netlify 함수) 검증:
   - App Store Server API는 **"앱 내 구입" 키(IAP 키)**를 쓴다. ASC API 키와 다르다.
   - 운영 서버를 먼저 조회하고, 404 또는 401이면 샌드박스를 조회한다(TestFlight·심사 구매는 샌드박스 거래).
   - **운영 인증이 확인되지 않은 상태의 "거래 없음"을 만료로 처리하지 않는다**(실제 구독자 보호).
   - 앱 출시 전에는 운영 서버가 새 키에 401을 줄 수 있다. 출시 게이트: `node tool/check_apple_iap_auth.mjs`에서 **운영: 인증 통과**가 나와야 한다.
   - **Netlify 환경 변수에 PEM을 직접 넣지 않는다.** `-----BEGIN`으로 시작하는 값을 CLI가 옵션으로 오해해 **개인 키를 오류 메시지로 출력**한다. base64로 인코딩해서 넣고 CLI 출력은 전부 버린다. 한 번 노출되면 키를 폐기·재발급한다.
   - Netlify `--secret`은 `--context production`이 필요하다.
7. iOS는 "구매 복원"을 자동으로 하지 않는다. 마지막 검증된 거래 ID를 저장하고 실행·복귀 시 서버로 재검증한다.
8. 구독 안내 문구(자동 갱신, 해지 방법, 이용 약관 링크)를 앱 안에 둔다(가이드라인 3.1.2). 이용 약관은 Apple 표준 EULA 링크를 쓴다.

---

## 6. App Store 등록 정보

- 버전 페이지: 프로모션 텍스트(170), 설명(4000), 키워드(100), 지원 URL, 마케팅 URL, 저작권, 빌드 선택, 심사 정보(연락처·메모).
- 별도 메뉴: **앱이 수집하는 개인정보**(광고 SDK 때문에 필수), 연령 등급, 카테고리, 가격·판매 국가.
- 수출 규정 답변과 `ITSAppUsesNonExemptEncryption` 일치. 프랑스에 배포하지 않으면 판매 국가에서 제외한다.
- **스크린샷**
  - 앱 실제 화면을 iPhone에서 직접 캡처한다. 규격은 6.9" 1320×2868, 1290×2796, 6.5" 1284×2778 등.
  - **Google Play 배지·모델 사진이 들어간 홍보 이미지는 쓰지 않는다.** 규격(941×1672)도 맞지 않는다.
  - 채팅으로 전달한 이미지는 축소된다. **원본 파일을 폴더로 복사**해서 쓴다.
  - 광고 ID 주입·상품 로드가 끝난 최종 빌드로 찍는다.
- 웹사이트에 "Google Play" 문구만 있으면 iOS용으로 같이 고친다.

---

## 7. 운영 규칙(공통)

- 빌드·버전 업·TestFlight 업로드·심사 제출은 **매번 사전 고지·확인**한다.
- 비밀값은 값을 출력하지 않고 "설정됨/미설정"으로만 보고한다.
- 법적 선언·세금·은행 정보·서명은 **사용자가 직접 입력**한다. 에이전트는 화면을 읽고 안내만 한다.
- 브라우저 자동화: 화면이 멈추면 새 탭을 열고, 네이티브 select는 `find`의 ref로 선택한다. 점 세 개 같은 숨은 메뉴 UI는 쓰지 않는다.
- 진행 상태는 메모리 파일에 날짜와 함께 기록한다.

---

## 8. 체크리스트 (복사해서 쓰기)

- [ ] Apple 계정 유형 결정(개인 / 조직 전환), 전환 완료 확인
- [ ] 번들 ID·앱 레코드·ASC API 키·IAP 키
- [ ] AdMob iOS 앱·광고 단위 생성, 변수 그룹에 등록
- [ ] `ios/` Info.plist·PrivacyInfo·SceneDelegate·채널 이식
- [ ] Google Play 문구 grep 후 iOS 분기
- [ ] Codemagic 연결, `ios-ci` → `ios-release` 순서로 첫 빌드
- [ ] TestFlight 내부 테스트: 실행·광고·스캔·파일 열기
- [ ] 유료 앱 계약·세금·은행·DSA·한국 규정 → **활성화됨** 확인
- [ ] 구독 상품: 현지화·그룹 현지화·심사용 스크린샷 → READY_TO_SUBMIT
- [ ] 서버 검증: 샌드박스 구매 → 운영 인증 통과 확인
- [ ] 스크린샷 전부 실기기 원본으로 촬영
- [ ] 앱 개인정보·연령 등급·판매 국가·심사 메모
- [ ] 구독 심사용 스크린샷을 실제 화면으로 교체
- [ ] 사용자 확인 후 심사 제출
