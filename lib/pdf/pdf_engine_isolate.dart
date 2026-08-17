/// 엔진의 isolate 워커 진입 함수 (저장 실작업). §8.
///
/// **이 파일에서만** `pdfrx_engine`(PDF 엔진 라이브러리)을 import한다.
/// Flutter SDK의 화면 그리기 계층이나 UI 렌더러 파일은 이 파일 어디서도 import하지 않는다 —
/// 화면 표시용 비트맵 생성 API에 손이 닿지 않으면 래스터화 코드는 문법적으로 작성될 수 없다(§3.1 봉쇄).
///
/// PDFium의 화면 표시용 비트맵 생성 API는 이 파일에서 호출하지 않는다.
/// 페이지는 오직 `FPDF_ImportPagesByIndex`(→ `PdfDocument.pages` setter)로 객체째 복사되거나,
/// JPEG 원본 바이트 그대로 `PdfDocument.createFromJpegData`로 임베드된다.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfrx;

import '../core/cancel_token.dart';
import '../core/progress.dart';
import 'page_ref.dart';

/// 워커 스폰 시 전달하는 인자. 전부 원시 타입/Map — isolate 경계를 넘긴다(§8.2).
/// `PageRef` 인스턴스 자체가 아니라 `toMap()` 결과만 보낸다.
class SaveIsolateArgs {
  const SaveIsolateArgs({
    required this.pages,
    required this.outputPath,
    required this.resultSendPort,
    required this.progressSendPort,
    required this.readySendPort,
  });

  /// `PageRef.toMap()` 결과 목록.
  final List<Map<String, Object?>> pages;

  /// 반드시 `.tmp` 스테이징 경로. 검증은 `pdf_engine.dart`가 스폰 전에 수행한다.
  final String outputPath;

  final SendPort resultSendPort;
  final SendPort progressSendPort;

  /// 워커가 취소 수신용 `SendPort`를 돌려보내는 핸드셰이크 포트.
  final SendPort readySendPort;
}

/// 워커 진입 함수. `Isolate.spawn`으로 실행된다.
/// `Isolate.run`은 진행률 스트리밍과 취소를 지원하지 않아 쓰지 않는다(§8.3).
///
/// 결과는 예외를 던지지 않고 [resultSendPort]로 Map을 보낸다:
/// - 성공: `{'ok': true, 'bytes': int, 'pageCount': int}`
/// - 실패: `{'error': <code>, 'detail': String?}` (`code` ∈ missing/corrupted/encrypted/cancelled/unknown)
Future<void> pdfEngineIsolateEntryPoint(SaveIsolateArgs args) async {
  final cancelReceivePort = ReceivePort();
  args.readySendPort.send(cancelReceivePort.sendPort);
  var cancelled = false;
  final cancelSub = cancelReceivePort.listen((_) => cancelled = true);

  final openedSources = <String, pdfrx.PdfDocument>{};
  final openedImageDocs = <pdfrx.PdfDocument>[];
  pdfrx.PdfDocument? targetDoc;

  try {
    final total = args.pages.length;
    args.progressSendPort.send(const PdfProgress(phase: PdfPhase.opening, done: 0, total: 0).toMap());

    Future<pdfrx.PdfDocument> openSource(String path) async {
      final existing = openedSources[path];
      if (existing != null) return existing;
      final doc = await pdfrx.PdfDocument.openFile(path);
      openedSources[path] = doc;
      return doc;
    }

    targetDoc = await pdfrx.PdfDocument.createNew(sourceName: 'memory:staging');
    final resultPages = <pdfrx.PdfPage>[];

    for (var i = 0; i < args.pages.length; i++) {
      if (cancelled) {
        args.resultSendPort.send({'error': 'cancelled'});
        await _deleteStagingDir(args.outputPath);
        return;
      }

      final PageRef pageRef;
      try {
        pageRef = PageRef.fromMap(args.pages[i]);
      } catch (e) {
        args.resultSendPort.send({'error': 'unknown', 'detail': 'invalid PageRef map: $e'});
        return;
      }

      pdfrx.PdfPage sourcePage;
      switch (pageRef) {
        case PdfPageRef():
          if (!File(pageRef.sourcePath).existsSync()) {
            args.resultSendPort.send({'error': 'missing', 'detail': pageRef.sourcePath});
            return;
          }
          final pdfrx.PdfDocument srcDoc;
          try {
            srcDoc = await openSource(pageRef.sourcePath);
          } on pdfrx.PdfPasswordException {
            args.resultSendPort.send({'error': 'encrypted', 'detail': pageRef.sourcePath});
            return;
          } on pdfrx.PdfException catch (e) {
            args.resultSendPort.send({'error': 'corrupted', 'detail': e.message});
            return;
          }
          if (pageRef.sourceIndex < 0 || pageRef.sourceIndex >= srcDoc.pages.length) {
            args.resultSendPort.send({'error': 'unknown', 'detail': 'sourceIndex out of range'});
            return;
          }
          sourcePage = srcDoc.pages[pageRef.sourceIndex];

        case ImagePageRef():
          if (!File(pageRef.imagePath).existsSync()) {
            args.resultSendPort.send({'error': 'missing', 'detail': pageRef.imagePath});
            return;
          }
          // 원본 JPEG 바이트를 그대로 임베드한다. 재인코딩·품질 프리셋은 이 지점에서 하지 않는다
          // — 설계 질의 참조(pdf-core 노트). 무손실 방향의 안전한 기본값이다.
          final bytes = await File(pageRef.imagePath).readAsBytes();
          final dims = _jpegPixelSize(bytes);
          if (dims == null) {
            args.resultSendPort.send({'error': 'corrupted', 'detail': '${pageRef.imagePath}: not a valid JPEG'});
            return;
          }
          final imgDoc = await pdfrx.PdfDocument.createFromJpegData(
            bytes,
            width: dims.$1.toDouble(),
            height: dims.$2.toDouble(),
            sourceName: 'memory:img$i',
          );
          openedImageDocs.add(imgDoc);
          sourcePage = imgDoc.pages.first;
      }

      // rotation은 원본에 더해지는 상대 회전이다(§2.2). 속성만 바뀐다 — 재인코딩 없음(§3).
      final steps = pageRef.rotation ~/ 90;
      if (steps != 0) {
        sourcePage = sourcePage.rotatedBy(pdfrx.PdfPageRotation.values[steps]);
      }
      resultPages.add(sourcePage);

      args.progressSendPort.send(PdfProgress(phase: PdfPhase.composing, done: i + 1, total: total).toMap());
    }

    if (cancelled) {
      args.resultSendPort.send({'error': 'cancelled'});
      await _deleteStagingDir(args.outputPath);
      return;
    }

    targetDoc.pages = resultPages;
    args.progressSendPort.send(PdfProgress(phase: PdfPhase.writing, done: total, total: total).toMap());

    // incremental: false 고정 — 항상 전체 재작성. 이 값은 절대 true로 호출하지 않는다(CLAUDE.md 절대 규칙 4).
    final bytes = await targetDoc.encodePdf(incremental: false);
    await File(args.outputPath).writeAsBytes(bytes, flush: true);

    args.progressSendPort.send(PdfProgress(phase: PdfPhase.finalizing, done: total, total: total).toMap());
    args.resultSendPort.send({'ok': true, 'bytes': bytes.length, 'pageCount': resultPages.length});
  } catch (e) {
    args.resultSendPort.send({'error': 'unknown', 'detail': e.toString()});
  } finally {
    await cancelSub.cancel();
    for (final doc in openedSources.values) {
      await doc.dispose();
    }
    for (final doc in openedImageDocs) {
      await doc.dispose();
    }
    if (targetDoc != null) {
      await targetDoc.dispose();
    }
  }
}

Future<void> _deleteStagingDir(String outputPath) async {
  try {
    final dir = File(outputPath).parent;
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {
    // 최선 노력. 상위(Repository)가 Workspace.rollbackStaging으로 다시 정리한다.
  }
}

/// JPEG SOF 마커에서 픽셀 폭·높이를 읽는다. `package:image` 의존 없이 순수 바이너리 파싱.
///
/// [실측 필요]: 반환된 픽셀 값을 PDF 포인트(1/72inch)로 그대로 사용한다(1px = 1pt 가정).
/// 실제 스캔 DPI 기준 물리 크기 변환은 이 라운드에서 확정되지 않았다 — 설계 질의 참조.
(int, int)? _jpegPixelSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    // SOF0..SOF15 except DHT(0xC4)/JPG(0xC8)/DAC(0xCC) carry width/height.
    final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
    if (isSof) {
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      return (width, height);
    }
    final segmentLength = (bytes[i + 2] << 8) | bytes[i + 3];
    i += 2 + segmentLength;
  }
  return null;
}

/// `pdf_engine.dart`에서 호출하는 메인 진입점. isolate 스폰·3포트 배선(§8.3)을 전부 이 함수 안에
/// 캡슐화해서 `pdf_engine.dart`가 `dart:isolate`를 직접 import하지 않아도 되게 한다(§3.1 import 표).
///
/// 이 함수 자체는 **호출한 isolate(보통 메인)에서 실행**된다 — `Isolate.spawn`을 거는 쪽이다.
/// [cancelToken]은 메인에 남고, 워커에는 `SendPort`만 전달한다(§8.2).
Future<Map<String, Object?>> runSaveInIsolate({
  required List<Map<String, Object?>> pages,
  required String outputPath,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final resultPort = ReceivePort();
  final progressPort = ReceivePort();
  final readyPort = ReceivePort();

  SendPort? cancelSendPort;
  void Function()? cancelListener;
  StreamSubscription<dynamic>? readySub;
  StreamSubscription<dynamic>? progressSub;

  try {
    await Isolate.spawn(
      pdfEngineIsolateEntryPoint,
      SaveIsolateArgs(
        pages: pages,
        outputPath: outputPath,
        resultSendPort: resultPort.sendPort,
        progressSendPort: progressPort.sendPort,
        readySendPort: readyPort.sendPort,
      ),
    );

    readySub = readyPort.listen((message) {
      cancelSendPort = message as SendPort;
      if (cancelToken?.isCancelled ?? false) {
        cancelSendPort!.send('cancel');
      }
    });

    progressSub = progressPort.listen((message) {
      onProgress?.call(PdfProgress.fromMap(message as Map<String, Object?>));
    });

    cancelListener = () => cancelSendPort?.send('cancel');
    cancelToken?.addListener(cancelListener);

    final result = await resultPort.first;
    return result as Map<String, Object?>;
  } finally {
    final listener = cancelListener;
    if (listener != null) cancelToken?.removeListener(listener);
    await readySub?.cancel();
    await progressSub?.cancel();
    resultPort.close();
    progressPort.close();
    readyPort.close();
  }
}

/// PDF 파일을 열지 않고(뷰어 상태를 만들지 않고) 메타데이터만 읽는다.
/// `pdf_engine.dart`가 pdfrx를 직접 import하지 않도록 이 함수를 경유한다(§3.1 import 경계).
/// 가벼운 읽기라 별도 isolate를 스폰하지 않고 호출한 isolate에서 직접 실행한다(§8.1에 없는 작업).
Future<Map<String, Object?>> inspectPdfFile(String path, {String? password}) async {
  if (!File(path).existsSync()) {
    return {'error': 'missing', 'detail': path};
  }
  try {
    final doc = await pdfrx.PdfDocument.openFile(
      path,
      passwordProvider: password == null ? null : pdfrx.createSimplePasswordProvider(password),
    );
    final pageCount = doc.pages.length;
    final isEncrypted = doc.isEncrypted;
    await doc.dispose();
    final bytes = await File(path).length();
    return {'ok': true, 'pageCount': pageCount, 'bytes': bytes, 'isEncrypted': isEncrypted};
  } on pdfrx.PdfPasswordException {
    return {'error': 'encrypted', 'detail': path};
  } on pdfrx.PdfException catch (e) {
    return {'error': 'corrupted', 'detail': e.message};
  } catch (e) {
    return {'error': 'unknown', 'detail': e.toString()};
  }
}
