/// 앱 부팅 진입점. (1주차 최소 배선)
///
/// 순서: `Workspace.ensureLayout()`(디렉터리 보장 + `.tmp`/`.old` 잔재 정리는
/// `AppWorkspace.ensureLayout` 내부에서 함께 수행된다, workspace.dart 참조) →
/// `KoreanFont.warmUp()`(폰트 파일이 없어도 죽지 않고 로그만 남김) →
/// `AppDatabase`/`PdfEngine`/`DocumentRepository` 생성 → `reconcileWithFilesystem()`.
///
/// 각 단계는 독립적으로 실패를 흡수한다 — 한 단계가 실패해도 다음 단계를 계속
/// 시도하고, 실패한 계층에 의존하는 화면 기능만 비활성화된다(요구사항: 초기화
/// 실패 시 앱이 죽지 않고 사용자에게 상태를 알려야 한다).
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/korean_font.dart';
import 'data/db/app_database.dart';
import 'data/repository/document_repository.dart';
import 'data/storage/workspace.dart';
import 'pdf/pdf_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 위젯 트리 내부 오류로 앱 프로세스가 죽지 않게 한다 — 기본 빨간 에러 화면은
  // 유지하되(문제를 숨기지 않는다) 로그를 남긴다.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    developer.log(
      '위젯 오류: ${details.exceptionAsString()}',
      name: 'main',
      level: 1000,
      error: details.exception,
      stackTrace: details.stack,
    );
    originalOnError?.call(details);
  };

  final issues = <String>[];

  // `Workspace` 추상 인터페이스에는 `root`가 없다(설계 §2.9 — 경로 계산 메서드만
  // 공개). DB·엔진 생성에 필요한 루트 경로는 구현체(`AppWorkspace`)에만 있으므로
  // 여기서는 구체 타입으로 들고 있다가 provider에는 인터페이스 타입으로 노출한다.
  AppWorkspace? appWorkspace;
  try {
    appWorkspace = await AppWorkspace.create();
    await appWorkspace.ensureLayout();
  } catch (e, st) {
    developer.log('Workspace 초기화 실패', name: 'main', level: 1000, error: e, stackTrace: st);
    issues.add('저장 공간 초기화에 실패했습니다. 스캔·PDF 열기를 사용할 수 없습니다.');
    appWorkspace = null;
  }
  final Workspace? workspace = appWorkspace;

  // KoreanFont.warmUp()은 내부에서 실패를 흡수하고 로그만 남긴다(korean_font.dart).
  // 그래도 예상 밖 예외로부터 부팅 전체를 보호하기 위해 한 번 더 감싼다.
  try {
    await KoreanFont.warmUp();
    if (!KoreanFont.isLoaded) {
      issues.add('한글 폰트 파일이 없습니다. PDF의 한글이 "□□□"로 나올 수 있습니다.');
    }
  } catch (e, st) {
    developer.log('KoreanFont.warmUp 실패', name: 'main', level: 900, error: e, stackTrace: st);
    issues.add('한글 폰트 예열에 실패했습니다.');
  }

  DocumentRepository? repository;
  PdfEngine? engine;
  if (appWorkspace != null) {
    try {
      final db = AppDatabase.open(appWorkspace.root);
      engine = QpdfPdfEngine(appRoot: appWorkspace.root);
      final repo = DriftDocumentRepository(db: db, workspace: appWorkspace, engine: engine);
      await repo.reconcileWithFilesystem();
      repository = repo;
    } catch (e, st) {
      developer.log('문서 저장소 초기화 실패', name: 'main', level: 1000, error: e, stackTrace: st);
      issues.add('문서 목록을 불러오지 못했습니다. 앱을 다시 시작해 주세요.');
      repository = null;
      engine = null;
    }
  }

  // 최상위 미처리 예외도 앱을 죽이지 않고 로그로 남긴다.
  runZonedGuarded(() {
    runApp(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWithValue(workspace),
          documentRepositoryProvider.overrideWithValue(repository),
          pdfEngineProvider.overrideWithValue(engine),
          bootIssuesProvider.overrideWithValue(List.unmodifiable(issues)),
        ],
        child: const PdfDaeriApp(),
      ),
    );
  }, (error, stack) {
    developer.log('처리되지 않은 예외', name: 'main', level: 1200, error: error, stackTrace: stack);
  });
}
