# PDF 생성 후 리뷰 요청 현황

- 앱 버전은 `1.1.5+5`다. `in_app_review` 2.0.12와 `shared_preferences` 2.5.5를 사용한다.
- 새 PDF 생성은 `DocumentRepository.createDocument`를 통해 원자적으로 완료된다. UI 성공 지점은 공용 `save_dialog.dart`와 단일 스캔용 `single_scan_save_screen.dart` 두 곳이다.
- 공용 저장 다이얼로그는 사진→PDF, PDF 편집, 문서 합치기에서 사용된다. 단일 스캔 저장은 공용 다이얼로그를 거치지 않는다.
- 저장 성공 시 전면 광고 작업 등록과 별도로 리뷰 요청 서비스가 실행된다. 완료 생성 횟수와 리뷰 요청 이력은 기기 로컬 저장소에 보관한다.
- Google Play 인앱 리뷰는 `requestReview()`를 요청해도 플랫폼의 사용량 제한 때문에 항상 대화상자가 나타나는 것은 아니다. 따라서 10회째 성공 완료 시 한 번만 요청하고, 사용자에게 별도 강제 다이얼로그는 띄우지 않아야 한다.
