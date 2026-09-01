# PDF 대리 — 기능·구조·로직 상세 설계서 (작업 인계용)

작성일: 2026-08-26. Claude Code 하네스(6개 서브 에이전트: pdf-architect/pdf-core/flutter-ui/
platform-integration/spec-guardian/build-runner)로 진행 중인 프로젝트를 다른 도구(Codex 등)로
이어받을 때 참고하는 문서다. 이 문서만 읽고도 "왜 이렇게 만들었는지"와 "지금 뭐가 끝났고 뭐가
남았는지"를 알 수 있게 쓴다.

**먼저 읽을 원본 스펙 문서(이 문서보다 우선함, 충돌 시 원본이 맞다)**: `CLAUDE.md`(절대 규칙),
`pipeline.md`, `data-model.md`, `screens.md`, `ads.md`, `milestones.md`. 이 문서는 그 위에 얹은
"구현이 실제로 어떻게 됐는지"의 요약이다.

---

## 0-A. Windows 데스크톱판 (2026-09-01 추가)

Flutter 코드를 그대로 재사용해 Windows 데스크톱 프로그램을 포팅했다(사용자 요청: "동일하게
기능하도록" — 단 스코프는 문서 처리 기능만, 카메라 스캔·광고·인앱결제·외부 인텐트 연동은 제외
확정). 설계·실행 전 과정은 `_workspace/68`(설계 확정서)~`75`(W5 최종 실측) 참고, 요약:

- **구조**: 단일 코드 트리 + `lib/core/platform_features.dart`(`AppFeatures`)의 런타임 게이트.
  `Platform.isWindows`/`Platform.isAndroid`로 조건부 import를 쓰는 안은 언어 차원에서 불가능함을
  확인(둘 다 `dart.library.io`가 참이라 구분 안 됨) — 그래서 런타임 게이트로 갔다. Android
  코드베이스는 이 포팅으로 **한 줄도 조건 분기가 들어가지 않았다**(광고/배너/결제/스캔 화면은
  전부 무수정, provider 주입 지점과 `ad_gate.dart`/`banner_host.dart` 안에서만 껐다).
- **qpdf**: `native/qpdf/windows-x64/qpdf30.dll`(공식 msvc64 배포물, `test/native/qpdf30.dll`과
  SHA-256 동일 — 검사33이 이 동일성을 자동으로 지킨다). `windows/CMakeLists.txt`의 `install()`로
  번들 루트에 배치.
- **가장 위험했던 지점**: `workspace.dart`의 저장 루트. 그대로 뒀으면 Windows에서 사용자의 실제
  `내 문서` 폴더에 앱 데이터가 쏟아질 뻔했다 — `getApplicationSupportDirectory()`로 분기해서
  `%APPDATA%\com.kamanbi\pdf_daeri\`를 쓰도록 고쳤고, 실측으로 재확인했다.
- **불변식 검사 신설**: `no_raster_test.dart` 검사31(`Platform.is*` 사용처 화이트리스트)·32(광고
  게이트 단일화)·33(qpdf30.dll 동일성). **주의**: 네이티브 애셋(pdfium.dll·qpdf30.dll) 추가 이후
  `flutter test`를 기본 동시성으로 돌리면 33개 파일 중 15개만 로드하고도 조용히 "통과"로 표시되는
  버그를 발견했다 — 반드시 `--concurrency=1`로 순차 실행할 것(§9에도 기록).
- **배포**: 자체 배포(Microsoft Store 아님), Inno Setup으로 만든 설치 프로그램
  (`windows/installer/PDFDaeriSetup.iss`, VC++ x64 재배포를 선행 조건으로 자동 설치). 빌드
  산출물(`PDF대리Setup.exe`, 46.59MB)과 `vcredist_x64.exe`는 gitignore 대상 — 커밋 안 됨, 다시
  만들려면 `flutter build windows --release` 후 Inno Setup(`ISCC.exe`)으로 `.iss` 컴파일.
- **실측 결과**(전부 RO 원칙 — 저장 후 pdfrx로 재열기 검증): 100쪽 삭제 200ms·회전 56ms·
  100+100쪽 합치기 93ms·압축 40ms(43.3% 감소), 50쪽 저장 메모리 피크 델타 약 0.4MB, 한글 파일명
  왕복 정상. 미검증: 공유 시트 실제 클릭 동작(자동화 불가, `share_plus`가 Windows 10 21H2+에서
  지원한다는 것만 코드 근거로 확인됨).
- **아직 안 한 것**: 앱 아이콘은 기본 Flutter 템플릿 아이콘 그대로(`assets/image.png`로 교체
  안 함, 설계 §6이 "일회성 작업"으로 남겨둔 항목). 서명(코드사이닝) 없음 — 자체 배포라 SmartScreen
  경고가 뜰 수 있음, 필요하면 별도 인증서 구매·서명 절차 추가해야 함.

---

## 0. 한 줄 요약

Flutter(Android 전용) PDF 유틸 앱. 스캔·사진→PDF·외부 PDF 열기·편집(자르기/회전/순서변경/삭제)·
합치기·나누기·무손실 압축을 로그인 없이, 서버 전송 없이, 기기 안에서만 처리한다. 4주 마일스톤 중
3.5주차(디자인)까지 끝났고 4주차(광고·수익화·마감)가 진행 중이다.

---

## 1. 기술 스택

| 영역 | 선택 | 비고 |
|---|---|---|
| 프레임워크 | Flutter (Android만, iOS 없음) | v1.1 후보에 iOS 있음 |
| 상태관리 | Riverpod 2.6.1 | `flutter_riverpod` |
| DB | Drift(SQLite) | `lib/data/db/` |
| PDF 렌더링(읽기 전용) | pdfrx(PDFium) | **저장/조작에는 안 씀** — §3 참고 |
| PDF 저장/조작 | qpdf 12.4.0 (네이티브, `dart:ffi`) | pdfrx는 무손실 저장 불가로 폐기(§3) |
| 이미지 처리 | libjpeg-turbo 3.0.4(네이티브) + `package:image`(순수 Dart) | |
| 스캔 | `doclens`(`third_party/doclens` 벤더링, 자체 Flutter 카메라 UI) | 원래 google_mlkit_document_scanner였으나 진행 중 전환됨(2026-08-26 사용자 확인, 의도된 결정). 무결성 매니페스트 미비(§9) |
| 공유 | share_plus 13.3.0 | |
| 광고 | google_mobile_ads ^9.1.0 | 4주차 신규 |
| 결제 | in_app_purchase ^3.3.0 | 4주차 신규 |
| 폰트(UI) | Pretendard(임베딩, OFL) | 3.5주차부터 |
| 폰트(PDF 텍스트 임베딩) | Noto Sans KR | UI 폰트와 별개, 헷갈리지 말 것 |

---

## 2. 레이어 구조 (`lib/`)

```
lib/
├── main.dart              # 부팅 시퀀스 — DB/Workspace/Settings/Ads/Billing 초기화
├── app/                   # 앱 셸: 라우팅·테마·providers·인텐트 수신
│   ├── app.dart               # MaterialApp, navigatorKey, 인텐트 소비 로직
│   ├── router.dart            # onGenerateRoute
│   ├── providers.dart         # 전역 Riverpod provider 모음
│   ├── theme.dart              # AppTheme.light() — 3.5주차 디자인 토큰
│   └── incoming_intent.dart   # 외부 앱에서 PDF 열기(카톡/Gmail 등) 수신
├── core/                  # 순수 로직, 어떤 계층에도 의존 안 함
│   ├── size_guard.dart        # 저장 전 용량 게이트 (SaveOp별 비율 규칙)
│   ├── file_name.dart          # 파일명 정규화/중복회피/제목 생성 규칙
│   ├── app_error.dart          # PdfFailure sealed 타입들
│   ├── cancel_token.dart      # 저장/압축 취소 신호
│   ├── progress.dart           # 진행률 콜백 타입
│   └── korean_font.dart        # PDF 텍스트 임베딩용 한글 폰트 로더
├── pdf/                   # PDF 조작 엔진 — "2-key separation" 원칙의 핵심
│   ├── pdf_engine.dart          # PdfEngine 인터페이스 + QpdfPdfEngine
│   ├── qpdf_isolate.dart        # qpdf FFI 전담 isolate (작업마다 새로 뜸)
│   ├── qpdf_ffi.dart             # 수기 작성 FFI 바인딩(ffigen 이 환경에서 불가)
│   ├── pdf_renderer.dart         # PdfxRenderer — 렌더 전용(pdfrx), 저장 안 함
│   ├── pdf_compressor.dart       # L1(무손실 최적화)/L2(이미지 다운샘플) 압축
│   ├── image_pdf_builder.dart    # 순수 Dart 이미지→PDF 인코딩(크롭 포함)
│   ├── image_encode_isolate.dart # 이미지 인코딩 isolate
│   ├── page_ref.dart              # PdfPageRef/ImagePageRef — 페이지 조립 단위
│   ├── image_quality.dart        # 압축 품질 프리셋
│   └── scan_source.dart           # ML Kit 스캐너 추상화
├── data/
│   ├── db/                      # Drift 스키마(tables.dart) + AppDatabase
│   ├── repository/
│   │   ├── document_repository.dart   # 모든 저장의 유일한 진입점(createDocument)
│   │   ├── recent_repository.dart      # 최근 열람 파일, 300MB/20개 quota
│   │   └── settings_repository.dart    # 4주차 신설 — 설정 단일 행 소유
│   └── storage/
│       ├── workspace.dart              # 스테이징/롤백, 저장공간 usage() 조회
│       ├── share_export.dart            # 시스템 공유 시트 연동
│       └── saf_import.dart              # SAF 파일 선택 + content:// 복사
├── features/               # 화면(S1~S5) — UI만, 로직은 위 계층에 위임
│   ├── home/                  # S1 홈
│   ├── scan/                  # S2 스캔, 사진→PDF(생성 중 편집 포함)
│   ├── viewer/                 # S4 뷰어, 외부 PDF 열기(S2-b), 압축 시트
│   ├── edit/                   # S3 편집(그리드/드래그/크롭/저장 다이얼로그)
│   ├── settings/                # S5 설정 (4주차에 광고제거/화질/저장공간 추가)
│   └── common/                  # FailureUi, share_flow(공유 단일 진입점)
├── ads/                    # 4주차 신설 — 광고 전담, lib/ads/ 밖으로 판단 로직 유출 금지
│   ├── ad_gate.dart              # adsRemoved 판단이 이뤄지는 유일한 지점
│   ├── ad_ids.dart                # 광고 ID 안전 로딩(디버그=강제 테스트ID)
│   ├── ads_bootstrap.dart        # MobileAds 초기화, 배너 높이 부팅 시 1회 확정
│   ├── banner_host.dart          # 배너 단일 구현(4중 방어 상태 머신)
│   └── interstitial_controller.dart  # 전면광고 노출 판단(하루 3회, 5분 간격)
└── billing/                 # 4주차 신설
    ├── billing_service.dart      # InAppPurchase 단일 소유자
    └── entitlement.dart           # adsRemovedProvider 노출, 단방향 markRemoved()
```

---

## 3. 핵심 설계 원칙 (반드시 지킬 것 — 위반하면 아키텍처 테스트가 fail한다)

### 3.1 "2-key 분리" (원칙, `test/architecture/no_raster_test.dart`가 강제)
- **qpdf FFI 계열**(`lib/pdf/qpdf_isolate.dart`, `qpdf_ffi.dart`)은 `package:image`를 절대
  import하지 않는다.
- **이미지 인코딩 계열**(`image_pdf_builder.dart`, `image_encode_isolate.dart`)은 qpdf FFI나
  `dart:io`를 isolate 쪽에서 import하지 않는다.
- 이유: 두 책임(PDF 구조 조작 vs 픽셀 인코딩)을 완전히 분리해서, 한쪽 버그가 다른 쪽에 전염되지
  않게 하고, 리뷰어가 "이 파일이 뭘 하는 파일인지" 한 줄로 알 수 있게 한다.

### 3.2 저장 경로 단일화
`DocumentRepository.createDocument`가 **유일한** 저장 진입점이다. 화면 코드는 `PdfEngine`을
직접 조립하지 않는다(단, 읽기 전용 `PdfEngine.inspect`는 예외 — `open_pdf_flow.dart`가 문서 열기
검사에 씀). 이걸 감시하는 자동 검사가 `no_raster_test.dart` 검사27에 있다.

### 3.3 RO 원칙 (Reopen-Or-It-Didn't-Happen)
모든 저장 경로 테스트는 **저장 후 다시 열어서**(가능하면 저장에 쓴 것과 다른 라이브러리로,
즉 qpdf로 쓴 걸 pdfrx로 읽어서) 실제 페이지 수/내용/회전을 검증해야 한다. 리턴값만 확인하는
테스트는 금지 — 과거에 이 원칙을 안 지켜서 "리턴값은 맞는데 실제로는 원본을 그대로 복사한"
심각한 무음 버그를 한 번 놓친 적이 있다.

### 3.4 BO 원칙 (Baseline = Original bytes Only)
용량 비율 측정은 항상 **진짜 원본 파일**의 바이트 수를 기준으로 한다. 앱이 자체 생성한 중간
산출물을 기준으로 삼으면 안 된다(과거에 이걸 어겨서 거짓 "개선됨" 보고를 한 적 있음).

### 3.5 SizeGuard 게이트
`lib/core/size_guard.dart`의 `SizeGuard.classify(before, after, intent)`가 저장 전 마지막
관문이다. `SaveOp`별 허용 비율:
- delete ≤ 1.0
- reorder/rotate ≤ 1.05
- split ≤ ratio × 1.2
- merge ≤ 1.05
- compose ≤ 1.15

UI가 이 비율을 임의로 고르지 않는다 — 순수 함수 하나로 판단이 고정돼 있다.

### 3.6 FailureUi 단일 소유
`lib/features/common/failure_ui.dart`가 `PdfFailure` → 사용자 메시지 매핑의 유일한 소유자다.
원본 예외 메시지(경로, 비밀번호 등)는 절대 UI 문자열에 노출하지 않는다(`developer.log`에만).
`switch`에 `default:`를 안 둬서, 새 실패 타입이 추가되면 컴파일 에러가 나게 강제한다(매핑 누락
구조적 방지).

### 3.7 단일 소유 파일 관례
이 프로젝트는 "기능 하나 = 구현 하나"를 자동 검사로 강제하는 걸 좋아한다. 지금까지 지정된 단일
소유:

| 기능 | 파일 |
|---|---|
| 저장 | `lib/pdf/pdf_engine.dart` |
| 렌더 | `lib/pdf/pdf_renderer.dart` |
| 파일명 정규화 | `lib/core/file_name.dart` |
| 용량 검증 | `lib/core/size_guard.dart` |
| 배너 | `lib/ads/banner_host.dart` |
| 광고 제거 판단 | `lib/ads/ad_gate.dart` |
| 설정 영속화 | `lib/data/repository/settings_repository.dart` |
| 결제 | `lib/billing/billing_service.dart` |
| 공유 진입점 | `lib/features/common/share_flow.dart`의 `shareDocument()` |

새 기능을 추가할 때 이 표에 없는 두 번째 구현을 만들지 마라 — 만들려는 참이면 먼저 이 표부터
갱신하고 이유를 남겨라.

---

## 4. 데이터 모델 (Drift, `lib/data/db/tables.dart`)

4개 테이블, schemaVersion 2.

- **documents**: id(uuid) / title / origin(`scan`\|`photo`\|`imported`, CHECK 제약) /
  pageCount / fileSize / createdAt / updatedAt / thumbPath. `updated_at DESC` 인덱스(홈 목록
  정렬용).
- **pages**: id / docId(FK cascade) / orderIndex / kind(`image`\|`pdf`) / sourcePath /
  sourceIndex(pdf일 때만 non-null) / rotation(0/90/180/270) / crop(schemaVersion 2 신설,
  `"l,t,r,b"` 형식, image에서만 non-null — PDF 페이지는 크롭 없음). `(docId, orderIndex)`
  unique 인덱스.
- **recent_files**: 최근 연 외부 파일. displayName(한글 원문 유지) / copiedPath / openedAt /
  size. 300MB/20개 quota는 `recent_repository.dart`가 가져오는 시점마다 자동 실행.
- **settings**(단일 행, id=0 CHECK): defaultQuality / adsRemoved / interstitialCountToday /
  lastAdDate. 4주차 신설이지만 스키마 자체는 처음부터 예약돼 있었음(3주차 때 이미 컬럼 존재).

`PageRef`(`lib/pdf/page_ref.dart`)가 DB 행과 실제 조립 사이의 중간 표현이다 —
`PdfPageRef(sourcePath, sourceIndex, rotation)` / `ImagePageRef(sourcePath, rotation, crop)`.

---

## 5. PDF 조작 파이프라인

### 5.1 왜 qpdf인가
초기에 pdfrx(PDFium)만으로 저장까지 하려 했으나, 실기기 측정(최대 8.4배 용량 팽창, 페이지마다
폰트 중복)으로 **PDFium이 무손실 저장에 근본적으로 부적합**함을 확인 → qpdf(네이티브,
`dart:ffi`)로 전환. pdfrx는 지금 **렌더링(뷰어 썸네일/페이지 보기) 전용**으로만 남아있다.

### 5.2 저장 흐름
1. 화면이 `List<PageRef>`를 조립(직접 qpdf/이미지 인코더를 안 부름)
2. `DocumentRepository.createDocument(pages, guardInput, ...)` 호출
3. 내부에서 `SizeGuard.classify`로 사전 검증 → 통과 못하면 `SizeGuardViolation` 반환(저장 안 함)
4. `PdfEngine`(→ `qpdf_isolate.dart`)이 새 isolate를 띄워 qpdf 작업 실행(작업마다 매번 새
   isolate — 이전 상태 잔존 없음, 코드로 확인됨)
5. 결과 파일을 `Workspace`가 스테이징 → 검증 통과 시에만 실제 위치로 이동(원자적, 실패 시 롤백)

### 5.3 압축(L1/L2)
- **L1**: qpdf 자체 최적화(무손실), 모든 문서(앱 생성물 + 외부 PDF) 대상
- **L2**: 이미지 다운샘플링(압축률 사용자가 프리셋으로 선택), 원래 앱 생성 문서만 대상이었으나
  3주차에 **외부 PDF까지 확장**(qpdf C API `qpdf_oh_get_stream_data`/`qpdf_oh_replace_stream_data`
  로 새 네이티브 shim 없이 구현). 사용자 확정: "압축 강도는 옵션화, 원본 삭제는 사용자가 만족한
  뒤 직접"

---

## 6. 화면(features/) 흐름

- **S1 홈**: 최근 연 파일 + 내 문서 2섹션. 롱프레스 다중선택 → `merge_documents_flow.dart`가
  유일한 배선 지점(화면은 `PdfEngine`을 모름, `DocumentRepository`만 앎).
- **S2 스캔 / 사진→PDF**: ML Kit 스캐너 또는 갤러리 사진 선택. **사진→PDF 생성 중에 바로
  자르기·회전·순서바꾸기**가 가능(2026-08-19 확정 — "PDF로 변환 후 재편집"이 아니라 생성 흐름
  안에서). S3의 `PageGridEditor`/`EditController`를 공유.
- **S2-b PDF 열기**: SAF 파일 선택 또는 외부 인텐트(카톡/Gmail/드라이브에서 "다른 앱으로 열기").
- **S3 편집**: 3열 그리드(`page_grid_editor.dart`, 자체 구현 드래그 재정렬 —
  `LongPressDraggable`+`DragTarget`, 신규 의존성 0), 회전/삭제/나누기 선택모드, 크롭 편집기(사진
  경로에만 — 스캔은 ML Kit이 이미 보정하므로 이중 보정 안 함).
- **S4 뷰어**: 지연 로딩, 썸네일 바, 압축 시트(`compress_sheet.dart` — 3상태 패턴:
  입력→진행→종료, 이 패턴을 `save_dialog.dart`도 재사용).
- **S5 설정**: 오픈소스 라이선스 고지(기존) + 4주차 추가분(광고 제거 구매/복원, 기본 저장 화질,
  저장 공간 관리 — 목록 UI 없이 숫자 4줄+버튼 2개, 개인정보처리방침 링크).

**저장 다이얼로그 원칙**: "확인 창 없이 곧바로 저장 다이얼로그"(설계 §3.1) — 중간에 별도
확인창을 끼우지 않는다.

---

## 7. 광고·결제 (4주차, `ads.md` 정책 기반)

### 7.1 노출 지점
배너: 홈/뷰어/편집/설정 4개 화면 하단. ML Kit 카메라·시스템 파일 선택기는 배너 없음.
전면광고: **저장 또는 공유 완료 직후만**, 1회. 하루 최대 3회(기기 로컬 자정 기준 리셋), 연타
방지 최소 간격 **5분**(사용자 확정 — ads.md 원안 60초가 아님, 주의).

### 7.2 배너 4중 방어 (`banner_host.dart`)
1. 높이 선점 — 앱 부팅 시 `resolveAdaptiveBannerHeight()`로 1회 확정해 `bannerHeightProvider`에
   굳힘(빌드 중 await 금지 — 레이아웃 점프의 주범이라 부팅 단계에서 미리 해석)
2. 완충 밴드 — 배너 바로 위에 버튼 안 둠, 스크롤 영역 하단 패딩 = 배너높이+밴드
   (`BannerHost.contentBottomPadding`)
3. 드래그 중 회피 — `page_grid_editor.dart`의 드래그 시작/종료가 `bannerDragAvoidProvider`를
   set/reset, 배너는 **가려지는 게 아니라 아래로 슬라이드 아웃**(Matrix4.translationValues,
   Opacity/Visibility 안 씀 — 확보된 높이는 빈 공간 유지)
4. 전면 직후 지연 — 전면광고 닫힌 뒤 수 초간 배너 안 붙임

### 7.3 단일 게이트
`ads_removed == true`일 때 배너·전면이 완전히 사라지는 판단은 **`lib/ads/ad_gate.dart` 단
하나**에서만 한다. 이걸 감시하는 자동 검사 3종(`no_raster_test.dart` 검사28·29·30)이 있다.

### 7.4 결제
**[2026-08-27~29 사이, 이 세션 밖에서 전환됨 — `plan.md`/`research.md` 참고]** 원래 설계(ads.md)는
비소모성 단건 구매 "광고 제거" 4,900원이었으나, 실제 구현은 **연간 자동 갱신 구독** ₩4,990/년으로
바뀌어 있다(제품 ID는 여전히 `ads_removed`). `billing_service.dart`가 `queryPastPurchases()`로
활성 구독 여부를 앱 시작·수동 갱신 시 동기화하고, 조회 실패 시 직전 캐시를 유지(§3.5 신뢰 순서
그대로 적용). 설정 화면은 Play Console의 실제 현지 가격을 표시하고 활성 구독의 Google Play
관리·취소 페이지를 연다. 서버 영수증 검증 없음(기기 내 Google Play 활성 구매 목록 기준 판정 —
즉시 철회·다중기기 동기화가 필요하면 별도 서버가 있어야 하는데, 이 앱은 그 요구가 없다고 판단됨).

**⚠️ Play Console 작업 시 주의**: `ads_removed`가 이미 **일회성 상품**으로 생성돼 있다면 같은 ID를
구독으로 바꿀 수 없다(Play 정책) — 이 경우 새 구독 상품 ID를 만들고 `kAdsRemovedProductId`
(`lib/billing/billing_service.dart`)와 홈페이지 관리 링크를 함께 바꿔야 한다.

앱 시작 시 `billingServiceProvider.start()` → `queryProducts()` → `restorePurchases()` 순서로
자동 복원(`lib/app/app.dart` initState).

### 7.5 광고 ID 안전 처리
실제 AdMob ID는 git에 커밋되지 않는다 — App ID는 gitignore된 `android/ads.properties` +
gradle manifestPlaceholders, Ad Unit ID는 `--dart-define`. **디버그 빌드는 dart-define 값이
있어도 무조건 구글 공식 테스트 ID를 씀**(`lib/ads/ad_ids.dart`의 `kDebugMode`/`kReleaseMode`
분기) — 실광고 오클릭 사고 구조적 차단.

---

## 8. 아키텍처 불변식 테스트

`test/architecture/no_raster_test.dart` 하나에 번호 매긴 검사(현재 30개)가 전부 모여있다. 각
검사는 예외 없이 **"위반 코드를 실제로 주입 → 검사가 fail하는지 확인 → 원복"** 방식으로 검증된
것들이다(이 프로젝트 전체의 불변 원칙). 새 검사를 추가할 때 이 절차를 생략하지 마라 — grep
정규식이 미묘하게 안 걸리는 경우가 실제로 있었다(예: `\b(render|toImage)\b`가 `renderPage`를
못 잡은 사례).

주요 검사 카테고리:
- 검사 1~25: 2-key 분리(§3.1), RO/BO 원칙 관련 회귀 방지, qpdf isolate 화이트리스트
  (`replaceInput`/`uncompress`/`splitPages`/`qdf`/`encrypt`/`linearize` 차단)
- 검사 26~27: 저장 경로 단일화(§3.2) — `image_pdf_builder.dart`에 `PdfPageRef` 0회,
  `lib/features/**`에서 `PdfEngine.save/merge/split` 직접 호출 0회(`inspect`는 예외)
- 검사 28~30: 광고 단일 게이트(§7.3) — `adsRemoved` 판단 위치, `AdWidget`/`BannerAd` 위치,
  전면광고 호출부가 정확히 3곳(`save_dialog.dart`/`compress_sheet.dart`/`share_flow.dart`)인지

`test/core/size_guard_gate_test.dart` — 15셀 행렬(3픽스처×5 SaveOp) + 차단 케이스 음성 단언 +
RO 검증.

---

## 9. 환경 특이사항 (막히면 여기부터 볼 것)

- **경로**: 프로젝트가 원래 `F:\PDF_대리`(한글 경로)였다가 빌드 버그로 `F:\PDF_daeri`(ASCII)로
  이전함. 일부 쉘 세션의 cwd가 옛 경로로 리셋되는 경우가 있으니 항상 절대경로
  `F:\PDF_daeri\...`를 확인할 것.
- **adb 경로**: `C:\Android\sdk\platform-tools\adb.exe` (PATH에 없음). Git Bash에서 쓸 때
  `MSYS_NO_PATHCONV=1` 접두사 필요.
- **PUB_CACHE 크로스 드라이브**: `android/gradle.properties`에 `kotlin.incremental=false`
  고정 — 되돌리면 Kotlin 증분 컴파일이 Windows에서 크래시남.
- **`flutter test` 전체 스위트**: `qpdf_split_then_merge_crash_repro_test.dart`의 15회 반복
  케이스 때문에 보통 **2시간 이상** 걸린다. 짧게 걸렸다면(2~3분) 부분 실행이었을 가능성을
  의심할 것. 동시에 여러 flutter test를 돌리면 `pdfium.dll` 파일 잠금 충돌이 남(하나 끝날
  때까지 대기하거나 순차 실행 권장).
  **[2026-09-01 Windows 포팅 W4 추가 발견]** Windows 플랫폼 활성화(qpdf30.dll·pdfium.dll
  네이티브 애셋 추가) 이후로는 **기본 동시성으로 `flutter test`를 돌리면 33개 테스트 파일 중
  15개만 로드하고도 조용히 `exit 0`/"All tests passed!"를 출력하는 부분 실행이 재현성 있게
  발생한다**(두 번 다 정확히 같은 15개 파일). 네이티브 라이브러리를 여러 워커가 동시에 열면서
  생기는 경합으로 추정 — 아키텍처 검사가 든 파일이 통째로 안 돌고도 통과로 표시될 수 있으니
  **반드시 `flutter test --concurrency=1`로 순차 실행**하고, 실행된 파일 수(총 33개 근방이어야
  함)까지 확인할 것. 시간이 더 걸리지만 이게 유일하게 신뢰 가능한 실행 방법이다.
- **Knox Secure Folder**: 삼성 기기에서 `run-as`/일부 `adb pull`이 막힘.
- **실기기**: SM S908N(`R3CTB0CV6NN`)가 주 테스트 기기. 저사양(RAM≤3GB) 기기는 현재 **없음** —
  4주차 M-W4 측정 항목 중 L(저사양) 값은 계속 미실측 상태로 남을 수 있음, 이 사실을 숨기지 말 것.
- **Play Console**: 구독 상품 `ads_removed`(연 ₩4,990) 생성 여부 미확인 — `research.md`가
  "이미 일회성 상품으로 만들어져 있으면 같은 ID로 구독 전환 불가"를 경고하고 있으니 실제로
  만들기 전에 Play Console 현황부터 확인할 것.
- **개인정보처리방침**: 이미 실제 배포됨 — `https://verdant-pixie-350067.netlify.app/privacy`
  (`lib/features/settings/settings_screen.dart`의 `kPrivacyPolicyUrl`에 이미 채워져 있음, 더 이상
  플레이스홀더 아님). 홈페이지 소스는 `website/`(+ `netlify.toml`, `netlify/functions/`), 배포는
  Netlify. `plan.md`/`research.md`가 이 작업의 완료 기록이다.
- **릴리스 서명**: `android/app/build.gradle.kts:99-109`가 외부 키(`F:\keys\PDF_daeri\`) 부재
  시 릴리스 빌드를 `error()`로 강제 중단시키게 배선돼 있음(debug 키 폴백 금지). **[2026-08-27~29
  사이 이 세션 밖에서 완료됨]** `research.md` 기록에 따르면 릴리스 APK·AAB가 실제로
  `com.kamanbi.pdf_daeri` 버전 `1.0.2`(versionCode 3)로 외부 릴리스 키로 이미 서명·생성됐다 —
  이 세션은 그 산출물 자체를 직접 검증하지 않았으니, 이어받는 쪽에서 실물(빌드 출력 경로)이
  실제로 있는지 한 번 확인하는 게 안전하다.

---

## 10. 지금까지 확정된 스코프 결정 (v1.1/v2로 미룬 것 vs 지금 하는 것)

- **120쪽 초과 문서는 없다고 가정**(2026-08-18 확정) — 2,668쪽·102MB 합성 문서로도 크래시 없음
  실측 확인됐지만, 저장 중 취소 대기 UX는 극단적 대용량에서만 체감돼 우선순위 낮춤.
- **다크모드 v1 제외**.
- **저장 중 화면 안 꺼짐(wakelock) v1 제외**(2026-08-25 확정) — split→merge 정지 현상 조사 결과,
  원인이 테스트 환경(화면 꺼짐+백그라운드) 한정이고 실사용 영향 없다고 판단.
- **v1.1 후보**: 외부 PDF에 스캔 페이지 추가, 서명, 암호 설정, 다크모드, iOS
- **v2**: 텍스트 추가·형광펜, OCR
- **영구 제외**: 기존 PDF 텍스트 직접 수정

---

## 11. 지금 상태 (2026-08-26 기준) — Codex가 이어받을 지점

**완료**: 1~3.5주차 전부(엔진/스캔/뷰어/편집/합치기/나누기/압축/디자인). 4주차는 R0~R4까지 완료:
- 공유 배선, 광고ID 인프라, 설정 영속화, 결제+광고게이트, 배너+드래그회피, 전면광고 트리거,
  S5 설정 확장, 부팅 배선(main.dart), 자동 검사 28·29·30 — 전부 코드 검증 완료(354/354 테스트
  통과), 실사(아키텍트 R3 중간판정)로 재확인됨.
- 앱 아이콘 반영 완료(`assets/image.png` → `flutter_launcher_icons`로 생성, 빌드 확인됨).

**[2026-08-27~29 사이, 이 세션 밖에서 진행된 작업 — `plan.md`/`research.md`가 기록]**:
- 광고 제거 상품을 비소모성 단건 구매(4,900원)에서 **연간 자동 갱신 구독(₩4,990/년)**으로 전환
  완료(§7.4 갱신 반영).
- 홈페이지(`website/`, Netlify)에 개인정보처리방침·환불규정·문의 페이지 실제 배포 완료
  (`https://verdant-pixie-350067.netlify.app`). `kPrivacyPolicyUrl`도 실제 URL로 채워짐.
- 릴리스 APK·AAB 실제 서명·생성 완료 기록(`com.kamanbi.pdf_daeri` v1.0.2, versionCode 3) —
  단 이 세션은 산출물 실물은 직접 확인하지 못했다.
- 이 작업들은 이 세션이 만든 게 아니므로 임의로 재검토·수정하지 않았다(아래 원칙 참고).

**T11(저사양 실기기 측정, M-W4-1~13)**: L기기 없음이 확정, H기기(SM S908N)로 adb 자동화 측정
진행. 최신 결과는 `_workspace/63_build-runner_w4t11_lowend_measurements.md` 참고 — 완전히
끝나지 않았을 수 있음, 이어받는 쪽에서 문서의 TBD 항목 확인 필요.

**아직 안 한 것(4주차 잔여, 순서대로 — 위 §"이 세션 밖에서 진행된 작업"으로 일부는 이미 끝났을 수
있으니 실제 상태부터 재확인할 것)**:
1. T11 마무리(가능한 범위까지)
2. 스플래시 화면 제작 여부 확인(아이콘은 끝남, 스플래시는 이 세션 기준 미확인)
3. Play Console에서 `ads_removed` 구독 상품 생성 여부 확인(§9 경고 — 일회성 상품 ID 재사용 불가)
4. T14 스토어 등록물(스크린샷 6장, 설명 — 첫 줄은 "로그인 없음/서버 전송 없음", 데이터 안전
   양식 — **AdMob이 광고 ID를 수집하므로 "수집 안 함" 신고는 거짓**, 주의)
5. 보안점검 후속 조치(`_workspace/64_security_review_full_app.md` §5 우선순위표) — H-1(백업
   비활성화)·M-1(악성 PDF로 저장/압축 영구 멈춤)·M-2(외부 인텐트 스킴 미검증)·M-3(스캔 캐시
   미정리)·L-2·L-3는 사용자 승인 받아 이 세션에서 처리·검증 완료(`_workspace/65`·`66`,
   전체 회귀 360/360 통과, 2026-08-29). M-4(doclens 벤더 무결성 매니페스트)는 전환 자체는
   의도된 결정으로 확인됐으나 qpdf 수준의 SHA-256 매니페스트가 아직 없음. M-5(UMP 동의·데이터
   안전 양식), L-1·L-4·L-5는 백로그.
6. 심사 제출

**중요 — 임의 변경 금지 원칙**: 이 프로젝트는 사용자가 이미 실기기에서 디버깅해 확정한 코드가
많다(예: doclens 전환). 스캐너/엔진처럼 "왜 이렇게 돼 있는지 설계 문서와 다르게 보이는" 코드를
발견해도 **먼저 왜 그런지 물어보고**, 임의로 되돌리거나 "고치지" 않는다(2026-08-26, 보안점검
중 사용자가 직접 강조한 원칙).

**미해결/이월 항목**:
- W3-R2: 실기기에서 카카오톡·Gmail·드라이브로 한글 제목 공유 시 앱 목록에 정상 표시되는지 사람이
  직접 확인(자동화 불가, 4주차 최종 점검 때 하기로 함)
- M-W4-8/12/13은 Play Console 상품 생성 + T13 완료 전까지 측정 불가

**감사 문서**: `_workspace/01`~`63`번까지 전부 gitignore 대상(커밋 안 됨)이지만, 프로젝트 결정의
전체 기록이다. 특히 `49`(3주차 최종 판정), `52`(4주차 설계 확정서), `60`(4주차 R3 중간판정)이
지금 상태를 이해하는 데 가장 중요하다.