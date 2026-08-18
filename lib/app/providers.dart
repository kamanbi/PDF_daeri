/// 앱 전역 Riverpod 프로바이더. (1주차 최소 배선 + 2주차 가산)
///
/// 초기화(`Workspace`/`AppDatabase`/`PdfEngine`/`DocumentRepository`/`RecentRepository`)는
/// `main.dart`의 부팅 시퀀스가 만들고, 성공한 것만 `ProviderScope.overrides`로 주입한다.
/// 실패한 항목은 `null`로 남아 화면이 "이 기능은 지금 쓸 수 없습니다"로 대응한다 —
/// 초기화 실패가 앱 전체 크래시로 번지지 않게 하기 위함(요구사항: 초기화 실패해도
/// 죽지 않는다).
///
/// `ScanSource`/`PhotoSource`/`SafImporter`/`PdfRenderer`는 초기화 실패 여지가 거의
/// 없는 얇은 래퍼라 기본값을 즉시 만든다(주입 실패 케이스 없음).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository/document_repository.dart';
import '../data/repository/recent_repository.dart';
import '../data/storage/saf_import.dart';
import '../data/storage/workspace.dart';
import '../pdf/pdf_engine.dart';
import '../pdf/pdf_renderer.dart';
import '../pdf/scan_source.dart';
import 'incoming_intent.dart';

/// 부팅 성공 시에만 값이 채워진다. `null`이면 해당 계층 초기화가 실패한 것이다.
final workspaceProvider = Provider<Workspace?>((ref) => null);
final documentRepositoryProvider = Provider<DocumentRepository?>((ref) => null);
final pdfEngineProvider = Provider<PdfEngine?>((ref) => null);

/// [2주차 신설] `recent_files` 접근. `documentRepositoryProvider`와 동일한 nullable
/// 패턴(§1.3) — DB/워크스페이스 초기화가 실패해도 다른 화면은 죽지 않는다.
final recentRepositoryProvider = Provider<RecentRepository?>((ref) => null);

/// 부팅 중 발생한 비치명 이슈(한글 폰트 누락 등)를 화면에 알리기 위한 목록.
final bootIssuesProvider = Provider<List<String>>((ref) => const []);

final scanSourceProvider = Provider<ScanSource>((ref) => MlKitScanSource());
final photoSourceProvider = Provider<PhotoSource>((ref) => FilePickerPhotoSource());
final safImporterProvider = Provider<SafImporter>((ref) => MethodChannelSafImporter());

/// [2주차 신설] 뷰어·홈 그리드가 공유하는 렌더러. `PdfxRenderer()` 생성 자체는
/// 실패 여지가 없다(문서를 열 때 실패하는 것과는 별개) — nullable로 두지 않는다.
final pdfRendererProvider = Provider<PdfRenderer>((ref) => PdfxRenderer());

/// [2주차 신설] 외부 인텐트 URI 수신의 유일한 구독 지점(§4.3). 앱 루트
/// (`lib/app/app.dart`)에서 한 번만 `ref.read`로 꺼내 `start()`를 호출한다.
final incomingIntentServiceProvider = Provider<IncomingIntentService>((ref) {
  final service = IncomingIntentService(ref.watch(safImporterProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// [2주차 신설] 인텐트로 도착했으나 아직 소비되지 않은 URI. 큐 길이 1(§4.4) —
/// 나중에 도착한 것이 이전 것을 덮어쓴다. 이번 라운드는 이 값을 **보관만** 한다.
/// 실제 소비(스캔·저장 진행 중이면 가로채지 않고 대기하다가 완료 후 뷰어로
/// 이동하는 것)는 다음 라운드 flutter-ui의 `openPdfAndGoToViewer` +
/// `lib/app/router.dart`가 이 값을 읽어 처리한다(§25 노트의 미해결 항목 참고).
final pendingIncomingUriProvider = StateProvider<String?>((ref) => null);

/// 홈 화면이 구독하는 스트림 2개(§1.3) — 섹션 1·2를 데이터 레이어에서부터
/// 분리한다. 합치는 provider를 만들지 않는다.
final documentsStreamProvider = StreamProvider<List<DocumentSummary>>((ref) {
  final repo = ref.watch(documentRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchDocuments();
});

final recentFilesStreamProvider = StreamProvider<List<RecentFile>>((ref) {
  final repo = ref.watch(recentRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchRecent();
});
