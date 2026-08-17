/// PDF 합성 로직(저장 실작업). §8 V-2 전면 개정.
///
/// **이 파일에서만** `pdfrx_engine`(PDF 엔진 라이브러리)을 import한다. 그러나 더 이상
/// `Isolate.spawn`을 쓰지 않는다 -- 이 파일의 함수들은 **호출한 isolate(항상 메인)에서 직접**
/// 실행된다(§8.0/§8.1). `pdfrx`의 모든 FFI 호출은 라이브러리 내부 `PdfrxEngineWorker`가 이미
/// 별도 isolate에서 처리하므로, 우리가 추가로 isolate를 스폰하면 얻는 것 없이 프로세스 전역
/// PDFium 상태(`FPDF_SetSystemFontInfo` 등)가 깨져 VM이 죽는다(실측: `09_build-runner_measurements.md`,
/// 원인 규명: `9x_architect_verdict.md` §3).
///
/// §8.4 불변식: 이 파일은 `dart:isolate`를 import하지 않는다(규칙 2) -- pdfrx를 만지는 isolate는
/// 프로세스에 정확히 하나(메인)여야 하므로, pdfrx를 만지는 이 파일 자체가 다른 isolate를 스폰할
/// 수 있는 여지를 문법적으로 없앤다. 이미지 인코딩만 `image_encode_isolate.dart`(pdfrx 없음)가
/// 별도 isolate로 돌린다.
///
/// Flutter SDK의 화면 그리기 계층이나 UI 렌더러 파일은 이 파일 어디서도 import하지 않는다 --
/// 화면 표시용 비트맵 생성 API에 손이 닿지 않으면 래스터화 코드는 문법적으로 작성될 수 없다(§3.1 봉쇄).
///
/// PDFium의 화면 표시용 비트맵 생성 API는 이 파일에서 호출하지 않는다.
/// 페이지는 오직 `FPDF_ImportPagesByIndex`(→ `PdfDocument.pages` setter)로 객체째 복사되거나,
/// JPEG 바이트 그대로 `PdfDocument.createFromJpegData`로 임베드되거나, **원본이 하나뿐인 작업은
/// 그 원본 문서 자신의 페이지 목록을 제자리에서 재배열**한다(인플레이스 경로, 아래).
///
/// 2-키 분리(아키텍트 판정 Q-A, §8.4 부수 효과로 isolate 경계로 승격): 이 파일은 PDF 문서·페이지
/// 객체만 쥔다. 이미지 디코드/인코드 API(`package:image`, `package:pdf/`)는 이 파일에 절대
/// 들이지 않는다 -- 그 일은 `image_encode_isolate.dart`/`image_pdf_builder.dart`(`Uint8List` 경계)에
/// 전담시킨다.
///
/// `Directory` API는 이 파일에서 쓰지 않는다(§2.3 불변식 5) -- 실패 시 자신이 쓴 출력 파일 하나만
/// 지운다. 스테이징 디렉터리 삭제는 `Workspace.rollbackStaging`의 단독 책임이다(Q-D).
library;

import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart' as pdfrx;

import '../core/cancel_token.dart';
import '../core/progress.dart';
import 'image_encode_isolate.dart';
import 'page_ref.dart';

/// 인플레이스 경로 적용 조건(아키텍트 판정 `9x_architect_verdict.md` §2.5).
///
/// [pages]의 **모든** 원소가 `PdfPageRef`이고, 그 `sourcePath`가 전부 **동일한 값 하나**이면
/// 그 sourcePath를 반환한다. 그 외(빈 목록, `ImagePageRef` 혼입, 서로 다른 sourcePath 혼입 --
/// merge·혼합 문서)는 `null`.
///
/// `null`이 아니면 `pdfrx`의 `_DocumentPageArranger.doShufflePagesInPlace`가 모든 페이지를
/// "자기 문서 소속"으로 인식해 `FPDF_ImportPagesByIndex`(압축 해제 + 리소스 복제의 원인, §2.2)를
/// 한 번도 타지 않는다 -- `move`/`remove`만 실행된다. 즉 삭제·순서변경·회전·발췌(원본 1개)는
/// 이 함수가 non-null을 반환해 인플레이스 경로를 타고, merge(원본 N개)·혼합 문서(이미지 포함)는
/// null을 반환해 기존 `createNew()` + import 경로를 그대로 탄다.
String? singleInPlaceSource(List<PageRef> pages) {
  if (pages.isEmpty) return null;
  String? source;
  for (final page in pages) {
    switch (page) {
      case ImagePageRef():
        return null;
      case PdfPageRef():
        source ??= page.sourcePath;
        if (page.sourcePath != source) return null;
    }
  }
  return source;
}

/// `pdf_engine.dart`에서 호출하는 메인 진입점. **호출한 isolate(메인)에서 직접 실행된다** --
/// `Isolate.spawn`을 쓰지 않는다(§8.1/§8.3 V-2). [singleInPlaceSource]로 조건을 판정해 인플레이스
/// 경로와 기존 합성 경로 중 하나로 분기한다. 두 경로 모두 결과는 동일한 계약을 따른다:
/// - 성공: `{'ok': true, 'bytes': int, 'pageCount': int}`
/// - 실패: `{'error': <code>, 'detail': String?}` (`code` ∈ missing/corrupted/encrypted/cancelled/unknown)
///
/// `SizeGuard` 경유는 두 경로 모두 동일하다 -- 이 함수는 게이트를 모르며, `pdf_engine.dart`가
/// 반환된 `bytes`를 받아 항상 같은 자리에서 `SizeGuard.check`를 수행한다(게이트 우회 분기 없음).
Future<Map<String, Object?>> runSave({
  required List<Map<String, Object?>> pages,
  required String outputPath,
  required int longEdgeMaxPx,
  required int jpegQuality,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final List<PageRef> decoded;
  try {
    decoded = pages.map(PageRef.fromMap).toList(growable: false);
  } catch (e) {
    return {'error': 'unknown', 'detail': 'invalid PageRef map: $e'};
  }

  final inPlaceSource = singleInPlaceSource(decoded);
  if (inPlaceSource != null) {
    return _runInPlace(
      sourcePath: inPlaceSource,
      orderedRefs: decoded.cast<PdfPageRef>(),
      outputPath: outputPath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  return _runComposeNew(
    pages: decoded,
    outputPath: outputPath,
    longEdgeMaxPx: longEdgeMaxPx,
    jpegQuality: jpegQuality,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );
}

/// 인플레이스 경로: 원본이 단 하나뿐인 작업(삭제·순서변경·회전·발췌). 원본 문서를 열어 **그 문서
/// 자신의** 페이지 목록을 제자리에서 재배열/회전한 뒤 저장한다 -- import 경로를 타지 않는다.
///
/// 원본 파일은 절대 덮어쓰지 않는다(절대 규칙 6). `doc.pages = kept`와 `doc.encodePdf()`는
/// 메모리상의 `PdfDocument` 객체만 바꾸고 바이트 버퍼를 반환할 뿐이다 -- 그 바이트를 [outputPath]
/// (스테이징 경로, 원본과 다른 파일)에 쓰는 것은 이 함수이지 pdfrx가 원본 파일에 쓰는 것이 아니다.
Future<Map<String, Object?>> _runInPlace({
  required String sourcePath,
  required List<PdfPageRef> orderedRefs,
  required String outputPath,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final total = orderedRefs.length;
  pdfrx.PdfDocument? doc;
  try {
    if (!File(sourcePath).existsSync()) {
      return {'error': 'missing', 'detail': sourcePath};
    }

    onProgress?.call(const PdfProgress(phase: PdfPhase.opening, done: 0, total: 0));
    try {
      doc = await pdfrx.PdfDocument.openFile(sourcePath);
    } on pdfrx.PdfPasswordException {
      return {'error': 'encrypted', 'detail': sourcePath};
    } on pdfrx.PdfException catch (e) {
      return {'error': 'corrupted', 'detail': e.message};
    }

    final kept = <pdfrx.PdfPage>[];
    for (var i = 0; i < orderedRefs.length; i++) {
      if (cancelToken?.isCancelled ?? false) {
        await _deleteOutputFileIfExists(outputPath);
        return {'error': 'cancelled'};
      }

      final ref = orderedRefs[i];
      if (ref.sourceIndex < 0 || ref.sourceIndex >= doc.pages.length) {
        return {'error': 'unknown', 'detail': 'sourceIndex out of range'};
      }
      var page = doc.pages[ref.sourceIndex];

      // rotation은 원본에 더해지는 상대 회전이다(§2.2). 속성만 바뀐다 -- 재인코딩 없음(§3).
      final steps = ref.rotation ~/ 90;
      if (steps != 0) {
        page = page.rotatedBy(pdfrx.PdfPageRotation.values[steps]);
      }
      kept.add(page);
      onProgress?.call(PdfProgress(phase: PdfPhase.composing, done: i + 1, total: total));
    }

    if (cancelToken?.isCancelled ?? false) {
      await _deleteOutputFileIfExists(outputPath);
      return {'error': 'cancelled'};
    }

    // 원본이 자기 자신의 페이지만 재배열하므로 doShufflePagesInPlace가 move/remove만 실행하고
    // FPDF_ImportPagesByIndex(스트림 필터 소실의 원인, 9x_architect_verdict.md §2.2)를 타지 않는다.
    doc.pages = kept;
    onProgress?.call(PdfProgress(phase: PdfPhase.writing, done: total, total: total));

    // incremental: false 고정 -- 항상 전체 재작성(CLAUDE.md 절대 규칙 4). 스테이징 경로에만 쓴다.
    final bytes = await doc.encodePdf(incremental: false);
    await File(outputPath).writeAsBytes(bytes, flush: true);

    onProgress?.call(PdfProgress(phase: PdfPhase.finalizing, done: total, total: total));
    return {'ok': true, 'bytes': bytes.length, 'pageCount': kept.length};
  } catch (e) {
    return {'error': 'unknown', 'detail': e.toString()};
  } finally {
    if (doc != null) await doc.dispose();
  }
}

/// 기존 합성 경로: 원본이 여럿이거나(merge) 이미지가 섞인(혼합 문서) 경우. 빈 문서를 만들고
/// 모든 페이지를 그 안에 채운다 -- 이 경로는 import가 불가피하다(원본 N개 또는 이미지 포함).
Future<Map<String, Object?>> _runComposeNew({
  required List<PageRef> pages,
  required String outputPath,
  required int longEdgeMaxPx,
  required int jpegQuality,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final total = pages.length;
  onProgress?.call(const PdfProgress(phase: PdfPhase.opening, done: 0, total: 0));

  // 이미지 인코딩은 순수 Dart CPU 작업이므로 별도 isolate로 보낸다(§8.1). PdfPageRef는 영향
  // 없다(A-2). pdfrx는 여기서 전혀 쓰이지 않는다 -- image_encode_isolate.dart가 스폰하는 워커는
  // pdfrx를 import하지 않는다(§8.4 규칙 1).
  final imagePaths = [for (final p in pages) if (p is ImagePageRef) p.imagePath];
  final encodeResult = await runImageEncodeBatch(
    imagePaths: imagePaths,
    longEdgeMaxPx: longEdgeMaxPx,
    jpegQuality: jpegQuality,
    cancelToken: cancelToken,
  );
  if (encodeResult['ok'] != true) return encodeResult;
  final encodedImages = (encodeResult['images']! as List).cast<EncodedImage>();

  final openedSources = <String, pdfrx.PdfDocument>{};
  final openedImageDocs = <pdfrx.PdfDocument>[];
  pdfrx.PdfDocument? targetDoc;

  try {
    Future<pdfrx.PdfDocument> openSource(String path) async {
      final existing = openedSources[path];
      if (existing != null) return existing;
      final doc = await pdfrx.PdfDocument.openFile(path);
      openedSources[path] = doc;
      return doc;
    }

    targetDoc = await pdfrx.PdfDocument.createNew(sourceName: 'memory:staging');
    final resultPages = <pdfrx.PdfPage>[];
    var imageCursor = 0;

    for (var i = 0; i < pages.length; i++) {
      if (cancelToken?.isCancelled ?? false) {
        await _deleteOutputFileIfExists(outputPath);
        return {'error': 'cancelled'};
      }

      final pageRef = pages[i];
      pdfrx.PdfPage sourcePage;
      switch (pageRef) {
        case PdfPageRef():
          if (!File(pageRef.sourcePath).existsSync()) {
            return {'error': 'missing', 'detail': pageRef.sourcePath};
          }
          final pdfrx.PdfDocument srcDoc;
          try {
            srcDoc = await openSource(pageRef.sourcePath);
          } on pdfrx.PdfPasswordException {
            return {'error': 'encrypted', 'detail': pageRef.sourcePath};
          } on pdfrx.PdfException catch (e) {
            return {'error': 'corrupted', 'detail': e.message};
          }
          if (pageRef.sourceIndex < 0 || pageRef.sourceIndex >= srcDoc.pages.length) {
            return {'error': 'unknown', 'detail': 'sourceIndex out of range'};
          }
          sourcePage = srcDoc.pages[pageRef.sourceIndex];

        case ImagePageRef():
          final encoded = encodedImages[imageCursor];
          imageCursor++;
          final pdfrx.PdfDocument imgDoc;
          try {
            imgDoc = await pdfrx.PdfDocument.createFromJpegData(
              encoded.bytes,
              width: encoded.boxWidthPt,
              height: encoded.boxHeightPt,
              sourceName: 'memory:img$i',
            );
          } catch (e) {
            return {'error': 'corrupted', 'detail': '${pageRef.imagePath}: $e'};
          }
          openedImageDocs.add(imgDoc);
          sourcePage = imgDoc.pages.first;
      }

      // rotation은 원본에 더해지는 상대 회전이다(§2.2). 속성만 바뀐다 -- 재인코딩 없음(§3).
      final steps = pageRef.rotation ~/ 90;
      if (steps != 0) {
        sourcePage = sourcePage.rotatedBy(pdfrx.PdfPageRotation.values[steps]);
      }
      resultPages.add(sourcePage);
      onProgress?.call(PdfProgress(phase: PdfPhase.composing, done: i + 1, total: total));
    }

    if (cancelToken?.isCancelled ?? false) {
      await _deleteOutputFileIfExists(outputPath);
      return {'error': 'cancelled'};
    }

    targetDoc.pages = resultPages;
    onProgress?.call(PdfProgress(phase: PdfPhase.writing, done: total, total: total));

    // incremental: false 고정 -- 항상 전체 재작성. 이 값은 절대 true로 호출하지 않는다(CLAUDE.md 절대 규칙 4).
    final bytes = await targetDoc.encodePdf(incremental: false);
    await File(outputPath).writeAsBytes(bytes, flush: true);

    onProgress?.call(PdfProgress(phase: PdfPhase.finalizing, done: total, total: total));
    return {'ok': true, 'bytes': bytes.length, 'pageCount': resultPages.length};
  } catch (e) {
    return {'error': 'unknown', 'detail': e.toString()};
  } finally {
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

/// 실패 시 정리 범위는 **자신이 쓴 출력 파일 하나뿐**이다(§2.3 불변식 3 개정, Q-D).
/// 디렉터리는 어떤 경우에도 건드리지 않는다 -- `Workspace.rollbackStaging`의 단독 책임이다.
Future<void> _deleteOutputFileIfExists(String outputPath) async {
  try {
    final file = File(outputPath);
    if (file.existsSync()) {
      await file.delete();
    }
  } catch (_) {
    // 최선 노력. 상위(Repository)가 Workspace.rollbackStaging으로 다시 정리한다.
  }
}

/// PDF 파일을 열지 않고(뷰어 상태를 만들지 않고) 메타데이터만 읽는다.
/// `pdf_engine.dart`가 pdfrx를 직접 import하지 않도록 이 함수를 경유한다(§3.1 import 경계).
/// 메인 isolate에서 직접 실행한다 -- 별도 isolate를 스폰하지 않는다(§8.1/§8.4).
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
