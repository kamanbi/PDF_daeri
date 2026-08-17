/// 앱 전역 Riverpod 프로바이더. (1주차 최소 배선)
///
/// 초기화(`Workspace`/`AppDatabase`/`PdfEngine`/`DocumentRepository`)는 `main.dart`의
/// 부팅 시퀀스가 만들고, 성공한 것만 `ProviderScope.overrides`로 주입한다. 실패한
/// 항목은 `null`로 남아 화면이 "이 기능은 지금 쓸 수 없습니다"로 대응한다 —
/// 초기화 실패가 앱 전체 크래시로 번지지 않게 하기 위함(요구사항: 초기화 실패해도
/// 죽지 않는다).
///
/// `ScanSource`/`PhotoSource`/`SafImporter`는 초기화 실패 여지가 거의 없는 얇은
/// 래퍼라 기본값을 즉시 만든다(주입 실패 케이스 없음).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository/document_repository.dart';
import '../data/storage/saf_import.dart';
import '../data/storage/workspace.dart';
import '../pdf/pdf_engine.dart';
import '../pdf/scan_source.dart';

/// 부팅 성공 시에만 값이 채워진다. `null`이면 해당 계층 초기화가 실패한 것이다.
final workspaceProvider = Provider<Workspace?>((ref) => null);
final documentRepositoryProvider = Provider<DocumentRepository?>((ref) => null);
final pdfEngineProvider = Provider<PdfEngine?>((ref) => null);

/// 부팅 중 발생한 비치명 이슈(한글 폰트 누락 등)를 화면에 알리기 위한 목록.
final bootIssuesProvider = Provider<List<String>>((ref) => const []);

final scanSourceProvider = Provider<ScanSource>((ref) => MlKitScanSource());
final photoSourceProvider = Provider<PhotoSource>((ref) => FilePickerPhotoSource());
final safImporterProvider = Provider<SafImporter>((ref) => MethodChannelSafImporter());
