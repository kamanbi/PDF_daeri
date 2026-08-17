# 데이터 모델

서버 없음. 로컬 파일시스템 + Drift(메타데이터 전용).
**원본 진실은 파일이다.** DB는 목록 조회용 인덱스이며, 불일치 시 파일 기준으로 복구한다.

---

## 파일 레이아웃

```
<app_documents>/
  docs/<docId>/
    document.pdf        최종 산출물
    sources/            원본 소스 (편집·재저장에 필요하므로 보관)
      src_0.pdf         외부에서 임포트한 PDF 복사본
      pages/001.jpg     스캔·사진 페이지
  thumbs/<docId>.jpg    목록용 대표 썸네일
  recent/               최근 연 외부 파일의 복사본 (용량 상한 관리)
  cache/                페이지 썸네일 캐시 (언제든 삭제 가능)
```

- `docId`는 UUID v4. **사용자 제목을 경로에 쓰지 않는다** (한글·특수문자 사고 차단)
- 사용자 제목은 DB에만 저장하고, 공유·내보내기 시점에만 파일명으로 변환

---

## 테이블

### documents
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | TEXT PK | UUID |
| title | TEXT | 사용자 지정 제목 (한글 그대로) |
| origin | TEXT | scan / photo / imported |
| page_count | INT | |
| file_size | INT | document.pdf 바이트 |
| created_at / updated_at | INT | epoch ms |
| thumb_path | TEXT | |

### pages
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | TEXT PK | |
| doc_id | TEXT FK | |
| order_index | INT | 0부터. 순서 변경 시 재부여 |
| kind | TEXT | `image` / `pdf` |
| source_path | TEXT | sources/ 내 경로 (이미지 또는 원본 PDF) |
| source_index | INT | kind=pdf일 때 원본에서의 페이지 번호. image면 null |
| rotation | INT | 0/90/180/270 |

> **핵심:** `kind`가 이원화된 이유는 외부 PDF 페이지를 이미지로 바꾸지 않고 **원본 페이지를 그대로 참조**하기 위해서다. 한 문서에 두 종류가 섞일 수 있다.

### recent_files
| 컬럼 | 설명 |
|---|---|
| id / display_name / copied_path / opened_at / size |

- 외부에서 연 파일의 최근 목록. 앱이 소유하지 않으므로 삭제가 아니라 **목록에서 제거**
- 용량 상한 초과 시 오래된 복사본부터 정리

### settings (단일 행)
- default_quality, ads_removed(bool), interstitial_count_today, last_ad_date

---

## 상태 규칙

- 저장 실패 시 `docs/<docId>/` 전체 롤백. 반쪽 문서를 목록에 남기지 않는다
- 앱 시작 시 DB에 있으나 파일이 없는 문서는 목록에서 제거
- `cache/`는 삭제되어도 기능에 영향이 없어야 한다
- `sources/`는 편집 재저장에 필요하므로 함부로 지우지 않는다. 저장 공간 관리 화면에서만 정리
