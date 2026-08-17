---
name: pdf-app-orchestrator
description: "PDF 앱(뷰어·스캐너·정리 도구) 개발 에이전트 팀을 조율하는 오케스트레이터. 기능 구현, 화면 작업, PDF 파이프라인, 플랫폼 연동, 주차별 마일스톤 진행 시 사용. 후속 작업에도 반드시 사용 — 다시 실행, 재실행, 이어서, 업데이트, 수정, 보완, 이전 결과 개선, 특정 화면만 다시, 검증만 다시, 1~4주차 진행, 마일스톤 판정, 리팩터링, 버그 수정 요청 시 모두 이 스킬로 처리한다."
---

# PDF 앱 개발 오케스트레이터

`CLAUDE.md`·`pipeline.md`·`data-model.md`·`screens.md`·`ads.md`·`milestones.md`를 근거로 에이전트 팀을 조율한다.

## 실행 모드: 에이전트 팀 (하이브리드 허용)

기본은 에이전트 팀이다. 설계자↔구현자↔검증자 간 계약 변경과 위반 지적이 실시간으로 오가야 하므로 팀 통신이 품질의 핵심 동력이다.
단, **단일 검증만 필요한 후속 작업**(예: "게이트 테스트만 다시 돌려줘")은 서브 에이전트 1명으로 처리한다.

## 팀 구성

| 팀원 | 역할 | 담당 스킬 | 주 산출물 |
|---|---|---|---|
| `pdf-architect` | 설계·판정 | `pdf-lossless-pipeline` | `_workspace/01_architect_design.md` |
| `pdf-core` | PDF 엔진 코딩 | `pdf-lossless-pipeline` | `lib/pdf/**`, `lib/core/size_guard.dart` |
| `flutter-ui` | 화면 코딩 | `pdf-app-ui` | `lib/features/**`, `lib/ads/banner_host.dart` |
| `platform-integration` | 플랫폼 경계 코딩 | `android-platform-bridge` | `lib/data/**`, `lib/core/file_name.dart`, `korean_font.dart`, Manifest |
| `spec-guardian` | 불변식 검증 | `spec-invariant-audit` | `_workspace/{phase}_spec-guardian_report.md` |
| `build-runner` | 빌드·측정 | `build-measure-gate` | `_workspace/{phase}_build-runner_results.md` |

## 모델 배정 — 승인 완료 (2026-08-17)

| 팀원 | 모델 | 근거 |
|---|---|---|
| `pdf-architect` | **opus** | 설계·트레이드오프·라이브러리 판정 |
| `spec-guardian` | **opus** | 놓친 위반의 비용이 가장 큼 (사용자 승인) |
| `pdf-core` | **sonnet** | 확정 설계의 구현 |
| `flutter-ui` | **sonnet** | 상세 스펙의 이행 |
| `platform-integration` | **sonnet** | 확정 스키마·경로의 구현 |
| `build-runner` | **haiku** | 명령 실행·수치 기록, 판단 없음 |

사용자 방침: **설계 opus / 코딩 sonnet / 빌드 haiku**, 검증은 opus.

**새 역할이 추가되어 위 표로 모델이 정해지지 않을 때는, 후보와 근거를 제시하고 사용자 선택을 요청한 뒤 팀을 만든다. 승인 없이 `TeamCreate`를 호출하지 않는다.** 확정된 6개 역할은 매번 다시 묻지 않는다.

## 워크플로우

### Phase 0: 컨텍스트 확인

1. `_workspace/` 존재 여부 확인
2. 실행 모드 결정:
   - **미존재** → 초기 실행. Phase 1로
   - **존재 + 부분 수정 요청** → 부분 재실행. 해당 에이전트만 재호출하고, 이전 산출물 경로를 프롬프트에 포함해 개선하게 한다
   - **존재 + 새 입력/새 주차** → 이어서 실행. 기존 `_workspace/`를 유지하고 새 phase 번호로 산출물을 추가한다
3. 현재 주차를 `milestones.md`와 `_workspace/` 산출물로 판별하고 사용자에게 확인받는다

### Phase 1: 준비

1. 근거 문서 6종을 읽는다
2. `_workspace/` 생성, `_workspace/00_input/`에 이번 작업 범위 기록
3. **모델 배정 승인 요청** (위 표 제시)
4. 이번 라운드의 작업 범위를 사용자에게 확인받는다 — 주차 단위인지 특정 기능인지

### Phase 2: 설계 (팀 없이 단독 선행)

**실행 모드:** 서브 에이전트 1명 (`pdf-architect`)

구현자들이 동시에 움직이기 전에 API 계약이 확정되어야 한다. 계약이 흔들리면 UI가 스텁에 갇히고 재작업이 발생한다.

- 산출: `_workspace/01_architect_design.md` — API 시그니처, 데이터 모델, isolate 경계, 파일 소유표, 광고 수치, 미결 질문
- 미결 질문이 있으면 **사용자에게 확인받은 뒤** Phase 3으로 넘어간다
- 새 의존성·스코프 변경·라이브러리 교체 제안이 나오면 여기서 사용자 승인을 받는다

### Phase 2-b: QC 1라운드 — 설계 산출물 검사 (승인된 시작점)

**실행 모드:** 서브 에이전트 1명 (`spec-guardian`, opus)

코드가 생기기 전에 설계에서 구조적 위반 여지를 봉쇄하는 것이 가장 저렴하다.
`spec-guardian`이 검사 계획을 제출 → 사용자 승인 → `_workspace/01_architect_design.md`를 절대 규칙 9개·중복 금지 6개와 대조한다.

핵심 확인: 설계가 `pdf_engine.dart`에서 렌더 API에 접근할 여지를 남겼는가 / `size_guard`를 우회할 수 있는 저장 경로가 있는가 / 6개 단일 소유 파일의 책임이 겹치는가 / `PageRef` 이원화가 모든 소비 지점에 반영되었는가 / 폰트 임베딩·NFC 정규화가 모든 경로를 덮는가.

지적 사항은 `pdf-architect`가 설계에 반영한 뒤 Phase 3으로 넘어간다.

### Phase 3: 구현 (에이전트 팀)

**실행 모드:** 에이전트 팀

1. `TeamCreate` — 승인된 모델로 `pdf-core`, `flutter-ui`, `platform-integration`, `spec-guardian`, `build-runner` 구성
2. `TaskCreate` — 주차별 체크리스트를 작업으로 등록. 의존 관계는 `depends_on`으로 명시

통신 규칙:
- `pdf-core`는 엔진 API 확정 즉시 `flutter-ui`에게 시그니처를 전달한다
- `platform-integration`은 Repository·저장소 경로 확정 즉시 `flutter-ui`·`pdf-core`에게 전달한다
- 설계에 없는 판단이 필요하면 구현자는 **직접 결정하지 않고** `pdf-architect`에게 요청한다 (Phase 2 산출물 갱신)
- `spec-guardian`은 **모듈 완성 직후 점진 검증**한다. 전체 완성 후 1회가 아니다
- 경계면 위반은 양쪽 담당자 **모두**에게 통보한다

**QC 착수 규칙:** `spec-guardian`은 검증 시작 전 **검사 계획(범위·항목·방법·제외·산출물)을 리더에게 제출**하고, 리더는 이를 사용자에게 확인받은 뒤 착수를 지시한다. 승인 없이 검증 범위를 넓히지 않는다. 단, 절대 규칙 위반이 우연히 발견되면 범위 밖이어도 즉시 보고한다.

**빌드 규칙:** `build-runner`의 `flutter analyze`·`flutter test`는 자유 실행. 빌드·버전 업·실기기 설치·서명 빌드는 **매번 사용자 확인**을 받는다.

### Phase 4: 검증·판정

1. `TaskGet`으로 완료 확인, 각 산출물을 Read로 수집
2. `spec-guardian` 최종 리포트 확인 — "확인 필요" 항목이 남아 있으면 통과로 처리하지 않는다
3. `build-runner` 측정 수치를 `pdf-architect`에게 전달 → `_workspace/9x_architect_verdict.md` 판정
4. 주차 판정이 실패면 **다음 주차로 넘어가지 않고 사용자에게 보고**한다 (`milestones.md` 규칙)

### Phase 5: 정리

1. 팀 종료 (`TeamDelete`)
2. `_workspace/` 보존 — 사후 검증·감사 추적용
3. 사용자에게 결과 요약 + 판정 + 미해결 항목 보고
4. 하네스 개선 피드백을 묻는다

## 비밀값 취급

키·서명 자료는 `F:\keys\PDF_대리`에 있다 (`.env`, `release.jks`).
리포지토리에 복사하지 않는다. 값을 로그·리포트에 출력하지 않는다(`설정됨`/`미설정`만). 서명 빌드 시 `key.properties`가 외부 경로를 참조하게 하고 `.gitignore`를 먼저 확인한다. 개발 중에는 AdMob 테스트 광고 단위 ID를 쓴다.

## 데이터 흐름

```
문서 6종 ─→ [pdf-architect] ─→ 01_architect_design.md
                                    │ (API 계약)
        ┌───────────────────────────┼───────────────────────────┐
        ↓                           ↓                           ↓
   [pdf-core]              [platform-integration]         [flutter-ui]
   lib/pdf/**                  lib/data/**                lib/features/**
        └───────────┬───────────────┴───────────────┬───────────┘
                    ↓                               ↓
            [spec-guardian] ←── 검사 계획 승인 ──→ 사용자
                    ↓                               ↑
            [build-runner] ──── 빌드 승인 요청 ─────┘
                    ↓
            [pdf-architect: 판정] → 9x_architect_verdict.md
```

## 에러 핸들링

| 상황 | 전략 |
|---|---|
| 구현자 1명 실패 | 1회 재시도. 재실패 시 해당 영역을 미완으로 명시하고 나머지 진행 |
| 절대 규칙 위반 발견 | 즉시 해당 작업 중단, 사용자에게 보고. 협상하지 않는다 |
| 무손실이 라이브러리 한계로 불가 | 임의 우회 금지. 라이브러리 교체 또는 스코프 축소를 **사용자 결정 사항**으로 제시 |
| 용량 게이트 위반 | 저장 중단 상태를 정상 결과로 보고. 게이트 완화를 임의 제안하지 않는다 |
| 구현자 간 계약 충돌 | `pdf-architect`가 중재하고 설계 문서를 갱신. 양쪽에 변경분 통보 |
| 같은 위반 2회 재발 | 개별 수정 대신 설계·하네스 수정을 제안 |
| 스코프 확장 요청 | `CLAUDE.md` 절대 규칙과 v1 제외 목록을 근거로 거절하고 v1.1로 기록 |

## 테스트 시나리오

### 정상 흐름 (1주차)
1. "1주차 기술 검증 시작" 요청
2. Phase 0 — `_workspace/` 없음 → 초기 실행
3. Phase 1 — 모델 배정표 제시 → 사용자 승인
4. Phase 2 — `pdf-architect`가 API 계약·데이터 모델 확정, 미결 질문 2건 사용자 확인
5. Phase 3 — 팀 구성. `pdf-core`가 엔진, `platform-integration`이 SAF·Drift·한글, `flutter-ui`가 최소 화면. `spec-guardian`이 검사 계획 승인 후 점진 검증
6. Phase 4 — `build-runner`가 측정 1~6 수행(빌드 필요분은 사용자 확인), `pdf-architect`가 판정
7. 예상 결과: `_workspace/9x_architect_verdict.md` + 측정 수치표 + 다음 주차 진행 가부

### 에러 흐름 (무손실 실패)
1. Phase 4에서 측정 1(1p 삭제 후 용량 감소)이 실패
2. `pdf-architect`가 `pdfrx` 제약을 원인으로 지목
3. 오케스트레이터는 다음 주차로 넘어가지 않는다
4. 사용자에게 두 안을 제시: (a) `syncfusion_flutter_pdf`로 교체 검증 (b) 외부 PDF를 보기·공유 전용으로 축소하고 편집을 v1.1로 이월
5. 사용자 선택 후 재실행. 임의로 래스터화 우회를 택하지 않는다
