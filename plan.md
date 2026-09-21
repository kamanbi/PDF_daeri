# PDF 대리 무료 유입 운영 계획

1. `PDF 열기`는 구현되어 있으므로 실기기에서 파일 선택·암호 PDF·최근 파일 재열기만 회귀 점검한다.
2. 네이버 서치어드바이저 수집·노출 리포트와 Google Search Console의 검색 실적이 생성되는지 7일 후 확인한다.
3. Google Play 등록정보 검토 결과와 스토어 방문·획득을 확인한다.
4. 블로그 글별 조회·검색 유입과 Threads 게시물 반응을 분리해 측정하고, 실제 반응이 높은 주제만 후속 콘텐츠로 확장한다.

## 가독성

- Early Return: 파일 선택 취소·검사 실패·암호 입력 취소에서는 뷰어 이동을 중단한다.
- Contextual Naming: `PickedFileSource`, `ExistingRecentSource`, `openPdfAndGoToViewer`처럼 진입 출처와 결과를 함께 표기한다.
- Magic Number Hunter: 7일은 첫 수집 상태 확인 주기이며, 코드 상수로 사용하지 않는다.
- Parameter Object: `PdfOpenSource`가 파일 선택·공유 인텐트·최근 파일의 입력을 통일한다.
- Complexity Check: PDF 열기 흐름 8/10 → 실기기 회귀 점검 후 8/10 유지.

완료 기준: PDF 열기 핵심 경로의 실기기 회귀 점검과 채널별 실제 수집·노출·방문·획득 데이터 확인을 끝낸다.
