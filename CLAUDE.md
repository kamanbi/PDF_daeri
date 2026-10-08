# CLAUDE.md — PDF 앱 (뷰어 + 스캐너 + 정리 도구)

## 프로젝트 한 줄 정의
외부 PDF를 열어보고, 종이 문서를 촬영해 PDF로 만들고, 페이지를 정리하는 **Android·iOS(iPhone, iOS 16+) Flutter 앱**.
[2026-10-08 개정] iOS 출시 결정(설계: `_workspace/91_architect_ios_port_design.md`). Mac 없이 Codemagic 클라우드 macOS로 빌드·서명·TestFlight 업로드.
로그인 없음, 서버 없음, 파일이 기기 밖으로 나가지 않음.

관련 문서: `data-model.md` / `screens.md` / `pipeline.md` / `ads.md` / `milestones.md`

---

## 절대 규칙 (위반 시 작업 중단하고 사용자에게 확인)

1. **서버·계정을 추가하지 않는다.** 네트워크는 광고 SDK와 인앱결제 외에 사용하지 않는다.
   [2026-09-23 개정] 예외: 구독(인앱결제) 구매 토큰을 서버 쪽에서 검증하는 자체 Netlify 함수
   (`netlify/functions/verify-subscription.mjs`, 호출부 `lib/billing/subscription_verifier.dart`)는
   사용자 확인 결과 의도된 결정으로 확정됐다 — 클라이언트가 로컬 DB의 bool 하나로 결제 여부를
   판정하면 루팅 기기에서 조작이 쉬워, 실제 결제 상태를 서버에서 재확인하기 위함이다. 이
   예외는 "인앱결제 검증" 목적으로만 한정되며, 그 외 서버·계정 기능 추가는 여전히 금지다.
   [2026-10-08] iOS(StoreKit) 구매 검증도 같은 함수에 Apple 분기로만 추가한다. 새 서버·함수 금지.
2. **외부 PDF를 절대 래스터화하지 않는다.** 페이지 객체를 그대로 복사한다. `pipeline.md` 참조.
3. **저장 결과 용량이 원본을 초과하면 저장을 중단한다.** 검증 게이트는 우회 대상이 아니다.
4. **기존 PDF 텍스트 수정 기능을 만들지 않는다.** 영구 제외.
5. **스캔·크롭·필터는 문서 스캐너 패키지의 완성된 플로우가 유일한 경로다** — 별도로 임의의
   카메라/보정 로직을 새로 만들지 않는다. [2026-08-26 개정, `_workspace/64_security_review_full_app.md`
   M-4 계기] 원래 `google_mlkit_document_scanner`(Play 서비스)로 명시됐던 걸 프로젝트 진행 중
   `doclens`(자체 Flutter 카메라 UI 패키지, `third_party/doclens`에 벤더링)로 전환한 것이
   사용자 확인 결과 의도된 결정으로 확정됐다 — 이 규칙은 "특정 패키지 고정"이 아니라 "스캔 UI를
   산발적으로 새로 만들지 않는다"는 원칙으로 재해석한다.
   [2026-09-23 재개정, 재감사로 표기 오류 정정] 실제 기본 경로는 `ResilientDocumentScanSource`
   (정의: `lib/features/scan/doclens_fallback_scan_source.dart`, 생성: `lib/app/providers.dart`)가
   먼저 Google Play 서비스의 네이티브 문서 스캐너 모듈(`play-services-mlkit-document-scanner`,
   Dart 패키지가 아니라 자체 MethodChannel로 직접 호출)을 시도하고, 기기가
   `EngineUnsupported`(Play 서비스 미지원)일 때만 `doclens` 자체 UI로 폴백하는 구조다 — doclens
   단독이 아니다. 완성된 스캐너 플로우 2종(ML Kit 공식 플로우, doclens 자체 플로우) 사이의 자동
   폴백이며, 둘 다 "임의의 카메라/보정 로직을 새로 만들지 않는다"는 본 규칙 취지를 지킨다. 이
   재개정으로 규칙 5 문구와 아래 스택 표를 실제 코드에 맞춘다.
   [2026-10-08] iOS의 유일한 스캔 경로는 VisionKit `VNDocumentCameraViewController`(OS 완성 플로우)다.
6. **원본 외부 파일을 수정하지 않는다.** 항상 앱 작업공간의 복사본을 편집한다.
7. **광고는 `ads.md`에 정의된 지점 외에 어디에도 넣지 않는다.** iOS도 동일 지점만 사용한다(ATT 동의 후 요청).
8. **스펙에 없는 기능을 선제적으로 추가하지 않는다.** 필요해 보이면 구현 전에 묻는다.
9. **빌드는 임의로 실행하지 않는다.** 빌드 여부, 버전 업, APK/AAB 선택, 실기기 설치는 매번 사용자에게 묻는다.
   iOS 클라우드 빌드(Codemagic)·TestFlight 업로드·심사 제출도 매번 사전 고지·확인한다.

---

## 스택

| 영역 | 선택 |
|---|---|
| 프레임워크 | Flutter (Android only) |
| PDF 뷰어·페이지 조작·문서 결합 | `pdfrx` (PDFium 기반) — **1주차 무손실 검증 필수** |
| 대안 | `syncfusion_flutter_pdf` — 대용량 UI 프리징 사례 있음, 라이선스 조건 확인 필요 |
| 스캔 | `ResilientDocumentScanSource`: 기본 Play 서비스 네이티브 문서 스캐너 모듈(`play-services-mlkit-document-scanner`, MethodChannel 직접 호출) → `EngineUnsupported`(Play 서비스 미지원 기기)일 때만 `doclens`(`third_party/doclens` 벤더링, 자체 Flutter 카메라 UI)로 폴백 — 2026-09-23 재개정, 규칙 5 참조 |
| PDF 생성(이미지 기반) | `pdf` |
| 이미지 처리 | `image` |
| 파일 선택 | SAF 기반 (`file_picker` 등), content:// URI 처리 |
| 로컬 저장 | 파일시스템 + Drift (메타데이터만) |
| 광고 | `google_mobile_ads` |
| 결제 | `in_app_purchase` |
| 상태관리 | Riverpod |
| 무거운 작업 | **isolate 필수** (PDF 파싱·병합·압축) |

---

## 디렉터리 구조

```
lib/
  main.dart
  app/            라우팅, 테마
  core/
    file_name.dart      파일명 정규화 (단일 구현)
    korean_font.dart    한글 폰트 로딩 (단일 구현)
    size_guard.dart     용량 검증 게이트 (단일 구현)
  data/
    db/                 Drift
    repository/
    storage/            앱 작업공간 경로, SAF 임포트
  pdf/
    page_ref.dart       PageRef 모델 (Image | Pdf)
    pdf_engine.dart     저장·병합·분할 진입점 (단일 구현)
    pdf_renderer.dart   렌더·썸네일 (단일 구현, 라이브러리 교체 가능)
    pdf_compressor.dart 압축 전용 (편집 저장과 분리)
    scan_source.dart    사진 선택(PhotoSource) 래퍼
    ocr_source.dart     ML Kit 텍스트 인식 래퍼 (인터페이스로 감쌈)
  features/
    home/ scan/ edit/ viewer/ settings/
    scan/doclens_fallback_scan_source.dart  ResilientDocumentScanSource(스캔 래퍼, 규칙 5)
  ads/
    banner_host.dart    높이 선점 + 드래그 회피 (단일 구현)
  billing/
```

---

## 중복 금지

아래는 반드시 한 곳에만 존재한다. 두 번째 구현을 발견하면 즉시 통합한다.

- 저장 경로 → `pdf_engine.dart`
- 렌더·썸네일 → `pdf_renderer.dart`
- 파일명 정규화 → `file_name.dart`
- 한글 폰트 로딩 → `korean_font.dart`
- 용량 검증 → `size_guard.dart`
- 배너 배치 → `banner_host.dart`

작업 중 유사 기능을 새로 만들기 전에 위 6개를 먼저 확인한다.

---

## 한글 처리 (1일차부터 적용)

1. PDF에 텍스트를 넣는 모든 지점에서 **Noto Sans KR 임베딩**. 누락 시 `□□□` 출력
2. 파일명은 저장 직전 **NFC 정규화** + 금지문자 치환
3. 공유 시 외부 앱에서 파일명이 깨지는지 확인 (카카오톡·Gmail·드라이브)
4. **외부 PDF 임포트 시** 원본 파일명이 깨지지 않는지 확인 (content:// URI에서 표시명 추출)
5. 고정 테스트 데이터: `2026년 8월 보고서 (최종).pdf`

---

## 인텐트 필터 (v1 필수 · 유일한 무료 유입 채널)

`application/pdf` VIEW 인텐트 필터를 등록해 카카오톡·메일·드라이브에서 PDF를 탭했을 때 앱이 후보로 뜨게 한다.
외부에서 전달받은 URI도 앱 작업공간 복사본 방식으로 동일하게 처리한다.

---

## 코딩 규칙

- 새 의존성 추가 전 사용자 확인
- 파일 작업은 실패 경로 필수 처리 (공간 부족, 권한 거부, 손상 파일, 암호 PDF, 취소)
- 큰 PDF는 전체 페이지를 한 번에 렌더링하지 않는다. 지연 로딩 + 캐시
- PDF 파싱·병합·압축은 isolate에서 실행
- 커밋 단위는 기능 단위

---

## 키·비밀값

주요 키와 보안 관련 ID는 **`F:\keys\PDF_daeri`** 에 보관한다 (`.env` = 광고·결제 ID, `release.jks` = 릴리스 서명 키).

- 리포지토리에 복사하지 않는다. `*.jks`, `key.properties`, `.env`, `local.properties`는 `.gitignore`에 유지
- 값을 화면·로그·리포트에 출력하지 않는다. `설정됨 / 미설정`으로만 보고
- 코드에 하드코딩하지 않는다. `--dart-define` 또는 빌드 시 주입, `key.properties`는 외부 경로 참조
- 개발·테스트 중에는 AdMob **테스트 광고 단위 ID** 사용
- `release.jks`를 이동·덮어쓰기·삭제하지 않는다 (분실 시 Play 업데이트 영구 불가)

---

## 하네스: PDF 앱 개발

**목표:** 무손실 PDF 파이프라인과 스펙 불변식을 지키면서 4주 마일스톤을 진행한다.

**트리거:** 이 프로젝트의 구현·화면·PDF 파이프라인·플랫폼 연동·검증·마일스톤 작업 요청 시 `pdf-app-orchestrator` 스킬을 사용하라. 단순 질문은 직접 응답 가능.

**운영 규칙 (오케스트레이터가 강제):**
- **모델 배정 (승인 완료):** 설계·검증 opus (`pdf-architect`, `spec-guardian`) / 코딩 sonnet (`pdf-core`, `flutter-ui`, `platform-integration`) / 빌드 haiku (`build-runner`). 새 역할이 추가되어 이 방침으로 정해지지 않으면 후보와 근거를 제시하고 선택을 요청한 뒤 팀을 구성한다
- **QC 방식 (승인 완료):** `spec-guardian`은 **모듈 완성 직후 점진 검증**하며, 매 라운드 착수 전 검사 계획(범위·항목·방법·제외·산출물)을 제출해 승인받는다. **1라운드는 코드가 아니라 설계 산출물을 검사**한다. 승인 없이 범위를 넓히지 않되, 절대 규칙 위반 발견은 범위와 무관하게 즉시 보고
- 빌드·버전 업·APK/AAB 선택·실기기 설치는 매번 사용자 확인 (절대 규칙 9)

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-08-17 | 초기 구성 (에이전트 6 + 스킬 6) | 전체 | - |
| 2026-08-17 | 설계/코딩/빌드 모델 분리, `pdf-architect` 신설 | agents/*, orchestrator | 설계 opus·코딩 sonnet·빌드 haiku 방침 |
| 2026-08-17 | 모델 배정 사용자 승인 규칙 추가 | orchestrator, CLAUDE.md | 모델 임의 고정 금지 요청 |
| 2026-08-17 | QC 검사 계획 승인 프로토콜 추가 | agents/spec-guardian, skills/spec-invariant-audit | 검사 방법 사전 확인 요청 |
| 2026-08-17 | 비밀값 취급 규칙 추가 (`F:\keys\PDF_daeri`) | CLAUDE.md, agents/build-runner, platform-integration | 키·서명 자료 외부 보관 |
| 2026-08-17 | 검증=opus 확정, QC=모듈별 점진 검증 확정, QC 1라운드=설계 산출물 | orchestrator, spec-invariant-audit, CLAUDE.md | 사용자 승인 |
| 2026-10-08 | iOS 지원 추가: 정의, 규칙 1(Apple 검증 분기)·5(VisionKit)·7·9(클라우드 빌드) | CLAUDE.md | iOS 출시 결정, 사용자 승인 |
| 2026-09-23 | 규칙 1에 구독 검증 서버 예외 명시, 규칙 5·스택 표를 실제 스캔 경로(ML Kit 기본+doclens 폴백)에 맞춰 재개정 | CLAUDE.md | 전체 앱 보안·규칙 감사 후속 조치, 사용자 확인 |
