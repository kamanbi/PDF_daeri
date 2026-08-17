/// 앱 전체에서 PDF를 파일로 쓰는 유일한 경로. §2.3 계약을 그대로 구현한다.
///
/// 이 파일은 UI 렌더러 파일이나 Flutter SDK의 화면 그리기 계층을 import하지 않는다(§3.1).
/// PDFium/pdfrx 호출은 전부 isolate 워커 파일에 있다 — 이 파일은 그 함수를
/// 호출하는 얇은 오케스트레이션 계층이다(경로 검증 → isolate 실행 → SizeGuard 판정).
library;

import 'dart:io';

import '../core/app_error.dart';
import '../core/cancel_token.dart';
import '../core/progress.dart';
import '../core/size_guard.dart';
import 'image_pdf_builder.dart';
import 'page_ref.dart';
import 'pdf_engine_isolate.dart';

abstract interface class PdfEngine {
  /// 페이지 목록으로 새 PDF를 만든다. 항상 전체 재작성(full rebuild).
  /// 증분 저장(incremental save) 옵션은 인터페이스에 존재하지 않는다.
  ///
  /// - [pages] 순서가 결과 페이지 순서다.
  /// - [outputPath] 는 반드시 스테이징 경로(`<docDir>.tmp/document.pdf`)여야 한다.
  ///   최종 경로 직접 쓰기는 구현에서 거부한다(§7.3).
  /// - [guardInput] 없이 호출할 수 없다. 게이트 우회 경로를 만들지 않기 위함이다.
  Future<PdfResult<SaveOutcome>> save({
    required List<PageRef> pages,
    required String outputPath,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });

  /// 여러 문서를 하나로 합친다. 내부적으로 save()와 동일한 full rebuild 경로를 탄다.
  Future<PdfResult<SaveOutcome>> merge({
    required List<String> sourcePdfPaths,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });

  /// 선택 페이지로 새 문서를 만든다(나누기).
  Future<PdfResult<SaveOutcome>> split({
    required String sourcePdfPath,
    required List<int> pageIndices,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });

  /// 파일을 열지 않고 페이지 수만 얻는다(임포트 직후 목록 구성용).
  Future<PdfResult<PdfDocInfo>> inspect(String pdfPath, {String? password});
}

class SaveOutcome {
  const SaveOutcome({required this.outputPath, required this.bytes, required this.pageCount, required this.guard});
  final String outputPath;
  final int bytes;
  final int pageCount;
  final GuardPass guard; // 게이트를 통과한 증거. 통과 없이는 이 타입을 만들 수 없다.
}

class PdfDocInfo {
  const PdfDocInfo({required this.pageCount, required this.bytes, required this.isEncrypted});
  final int pageCount;
  final int bytes;
  final bool isEncrypted;
}

enum ImageQuality { high, standard, min }

/// `pdfrx_engine` 기반 구현체. M0 서베이(`_workspace/03_pdf-core_m0_survey.md`) 결과에 따라 채택.
class PdfrxPdfEngine implements PdfEngine {
  const PdfrxPdfEngine();

  @override
  Future<PdfResult<SaveOutcome>> save({
    required List<PageRef> pages,
    required String outputPath,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final pathError = _validateStagingPath(outputPath);
    if (pathError != null) return PdfErr(pathError);

    // §5 #2: ImagePageRef -> 화이트리스트+파일 존재, PdfPageRef -> 파일 존재+sourceIndex 범위.
    // sealed switch로 두 케이스를 전부 명시한다(B1 -- is 분기로 우회하지 않는다, default/_ 금지).
    final inspectedCounts = <String, int>{};
    for (final page in pages) {
      switch (page) {
        case ImagePageRef():
          final wl = _validateImageWhitelist(imagePath: page.imagePath, outputPath: outputPath);
          if (wl != null) return PdfErr(wl);
          if (!File(page.imagePath).existsSync()) {
            return PdfErr(SourceMissing(page.imagePath));
          }
        case PdfPageRef():
          if (!File(page.sourcePath).existsSync()) {
            return PdfErr(SourceMissing(page.sourcePath));
          }
          var count = inspectedCounts[page.sourcePath];
          if (count == null) {
            final infoResult = await inspect(page.sourcePath);
            switch (infoResult) {
              case PdfErr<PdfDocInfo>():
                return PdfErr(infoResult.failure);
              case PdfOk<PdfDocInfo>():
                if (infoResult.value.isEncrypted) return PdfErr(SourceEncrypted(page.sourcePath));
                count = infoResult.value.pageCount;
                inspectedCounts[page.sourcePath] = count;
            }
          }
          if (page.sourceIndex < 0 || page.sourceIndex >= count) {
            return PdfErr(UnknownFailure('sourceIndex out of range: ${page.sourcePath}[${page.sourceIndex}]'));
          }
      }
    }

    final preset = _presetFor(quality);
    return _composeAndSave(
      pages: pages,
      outputPath: outputPath,
      guardInput: guardInput,
      longEdgeMaxPx: preset.$1,
      jpegQuality: preset.$2,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<PdfResult<SaveOutcome>> merge({
    required List<String> sourcePdfPaths,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final pathError = _validateStagingPath(outputPath);
    if (pathError != null) return PdfErr(pathError);

    var baselineBytes = 0;
    final pages = <PageRef>[];
    for (final sourcePath in sourcePdfPaths) {
      if (!File(sourcePath).existsSync()) {
        return PdfErr(SourceMissing(sourcePath));
      }
      final infoResult = await inspect(sourcePath);
      switch (infoResult) {
        case PdfErr<PdfDocInfo>():
          return PdfErr(infoResult.failure);
        case PdfOk<PdfDocInfo>():
          final info = infoResult.value;
          if (info.isEncrypted) return PdfErr(SourceEncrypted(sourcePath));
          baselineBytes += info.bytes;
          for (var i = 0; i < info.pageCount; i++) {
            pages.add(PdfPageRef(sourcePath: sourcePath, sourceIndex: i, rotation: 0));
          }
      }
    }

    // merge/split은 PdfPageRef만 생성한다(A-6) -- quality는 쓰이지 않으므로 상수 참조만 넘긴다.
    final guardInput = GuardInput(op: SaveOp.merge, baselineBytes: baselineBytes);
    return _composeAndSave(
      pages: pages,
      outputPath: outputPath,
      guardInput: guardInput,
      longEdgeMaxPx: ImagePdfBuilder.standardLongEdgeMaxPx,
      jpegQuality: ImagePdfBuilder.standardJpegQuality,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<PdfResult<SaveOutcome>> split({
    required String sourcePdfPath,
    required List<int> pageIndices,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final pathError = _validateStagingPath(outputPath);
    if (pathError != null) return PdfErr(pathError);

    if (!File(sourcePdfPath).existsSync()) {
      return PdfErr(SourceMissing(sourcePdfPath));
    }
    final infoResult = await inspect(sourcePdfPath);
    final PdfDocInfo info;
    switch (infoResult) {
      case PdfErr<PdfDocInfo>():
        return PdfErr(infoResult.failure);
      case PdfOk<PdfDocInfo>():
        info = infoResult.value;
    }
    if (info.isEncrypted) return PdfErr(SourceEncrypted(sourcePdfPath));
    if (pageIndices.isEmpty || pageIndices.any((i) => i < 0 || i >= info.pageCount)) {
      return PdfErr(UnknownFailure('pageIndices out of range for $sourcePdfPath'));
    }

    final pages = pageIndices
        .map((i) => PdfPageRef(sourcePath: sourcePdfPath, sourceIndex: i, rotation: 0))
        .toList(growable: false);

    final guardInput = GuardInput(
      op: SaveOp.split,
      baselineBytes: info.bytes,
      totalPages: info.pageCount,
      selectedPages: pageIndices.length,
    );
    return _composeAndSave(
      pages: pages,
      outputPath: outputPath,
      guardInput: guardInput,
      longEdgeMaxPx: ImagePdfBuilder.standardLongEdgeMaxPx,
      jpegQuality: ImagePdfBuilder.standardJpegQuality,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<PdfResult<PdfDocInfo>> inspect(String pdfPath, {String? password}) async {
    final map = await inspectPdfFile(pdfPath, password: password);
    if (map['ok'] == true) {
      return PdfOk(
        PdfDocInfo(
          pageCount: map['pageCount']! as int,
          bytes: map['bytes']! as int,
          isEncrypted: map['isEncrypted']! as bool,
        ),
      );
    }
    return PdfErr(_failureFromErrorMap(map));
  }

  /// [quality] -> (longEdgeMaxPx, jpegQuality). 리터럴 숫자는 여기 없다 -- `image_pdf_builder.dart`의
  /// 프리셋 상수를 참조만 한다(A-1, §3.4 검사 9).
  (int, int) _presetFor(ImageQuality quality) => switch (quality) {
    ImageQuality.high => (ImagePdfBuilder.highLongEdgeMaxPx, ImagePdfBuilder.highJpegQuality),
    ImageQuality.standard => (ImagePdfBuilder.standardLongEdgeMaxPx, ImagePdfBuilder.standardJpegQuality),
    ImageQuality.min => (ImagePdfBuilder.minLongEdgeMaxPx, ImagePdfBuilder.minJpegQuality),
  };

  Future<PdfResult<SaveOutcome>> _composeAndSave({
    required List<PageRef> pages,
    required String outputPath,
    required GuardInput guardInput,
    required int longEdgeMaxPx,
    required int jpegQuality,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final resultMap = await runSaveInIsolate(
      pages: pages.map((p) => p.toMap()).toList(growable: false),
      outputPath: outputPath,
      longEdgeMaxPx: longEdgeMaxPx,
      jpegQuality: jpegQuality,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    if (resultMap['ok'] != true) {
      return PdfErr(_failureFromErrorMap(resultMap));
    }

    final resultBytes = resultMap['bytes']! as int;
    final pageCount = resultMap['pageCount']! as int;

    final guardResult = SizeGuard.check(input: guardInput, resultBytes: resultBytes);
    switch (guardResult) {
      case GuardBlocked():
        // 엔진은 자기가 쓴 출력 파일만 지운다. 디렉터리 삭제는 Workspace.rollbackStaging 단독 책임이다(Q-D).
        try {
          await File(outputPath).delete();
        } catch (_) {
          // 최선 노력. 상위(Repository)가 Workspace.rollbackStaging으로 다시 정리한다.
        }
        return PdfErr(SizeGuardViolation(guardResult));
      case GuardPass():
        return PdfOk(
          SaveOutcome(outputPath: outputPath, bytes: resultBytes, pageCount: pageCount, guard: guardResult),
        );
    }
  }

  PdfFailure _failureFromErrorMap(Map<String, Object?> map) {
    final code = map['error'] as String?;
    final detail = map['detail'] as String?;
    return switch (code) {
      'missing' => SourceMissing(detail ?? ''),
      'corrupted' => SourceCorrupted(detail ?? ''),
      'encrypted' => SourceEncrypted(detail ?? ''),
      'cancelled' => const Cancelled(),
      _ => UnknownFailure(detail ?? code ?? 'unknown failure'),
    };
  }
}

/// `/` 로 정규화된 경로에서 `.`/`..` 세그먼트를 접어 정규 형태로 만든다.
/// `package:path`를 쓰지 않는다(§3.1 -- 이 파일의 허용 import 목록 밖).
String _collapseDotSegments(String slashPath) {
  final isAbsolute = slashPath.startsWith('/');
  final out = <String>[];
  for (final part in slashPath.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(part);
  }
  return (isAbsolute ? '/' : '') + out.join('/');
}

String _normalize(String path) => _collapseDotSegments(path.replaceAll('\\', '/'));

/// outputPath에서 `<root>/docs/<docId>.tmp/...` 형태를 파싱해 (root, docId)를 뽑는다.
/// 형태가 아니면 null.
({String root, String docId})? _stagingScope(String outputPath) {
  final normalized = _normalize(outputPath);
  final match = RegExp(r'^(.*)/docs/([^/]+)\.tmp/[^/]+$').firstMatch(normalized);
  if (match == null) return null;
  return (root: match.group(1)!, docId: match.group(2)!);
}

/// outputPath가 `<root>/docs/<docId>.tmp/document.pdf` 형태인지 검증한다(§2.3 계약 불변식 1).
PdfFailure? _validateStagingPath(String outputPath) {
  if (_stagingScope(outputPath) == null) {
    return const UnknownFailure('outputPath must be inside a .tmp staging directory');
  }
  return null;
}

/// `ImagePageRef.imagePath`가 §3.3 화이트리스트 안인지 검증한다.
/// 허용: `<root>/docs/<docId>/sources/pages/` 또는 `<root>/docs/<docId>.tmp/sources/pages/` 하위뿐
/// (같은 저장 요청의 outputPath에서 유도한 root+docId에 바인딩 -- V2).
PdfFailure? _validateImageWhitelist({required String imagePath, required String outputPath}) {
  final scope = _stagingScope(outputPath);
  if (scope == null) {
    return const UnknownFailure('image path outside sources');
  }
  final normalizedImg = _normalize(imagePath);
  final committedPrefix = '${scope.root}/docs/${scope.docId}/sources/pages/';
  final stagingPrefix = '${scope.root}/docs/${scope.docId}.tmp/sources/pages/';

  String? matchedPrefix;
  if (normalizedImg.startsWith(committedPrefix)) {
    matchedPrefix = committedPrefix;
  } else if (normalizedImg.startsWith(stagingPrefix)) {
    matchedPrefix = stagingPrefix;
  }
  if (matchedPrefix == null) {
    return const UnknownFailure('image path outside sources');
  }
  // 화이트리스트 디렉터리 바로 아래 파일이어야 한다(추가 하위 디렉터리 금지).
  final remainder = normalizedImg.substring(matchedPrefix.length);
  if (remainder.isEmpty || remainder.contains('/')) {
    return const UnknownFailure('image path outside sources');
  }
  return null;
}
