/// 앱 전체에서 PDF를 파일로 쓰는 유일한 경로. §2.3 계약을 그대로 구현한다.
///
/// 이 파일은 UI 렌더러 파일이나 Flutter SDK의 화면 그리기 계층을 import하지 않는다(§3.1).
/// qpdf FFI 호출은 전부 `qpdf_isolate.dart`(워커 isolate)에 있다 — 이 파일은 `dart:ffi`를
/// 직접 쓰지 않고(§5.7 신설 불변식), 그 함수를 호출하는 얇은 오케스트레이션 계층이다
/// (경로 검증 → 필요 시 이미지 인코딩 → qpdf 잡 실행 → SizeGuard 판정).
///
/// `_workspace/15_architect_qpdf_migration.md` §5.6 저장 조립 구조를 구현한다: `pages`를 스캔해
/// (a) 전부 동일 소스의 `PdfPageRef`(회전 포함/미포함)면 `buildRotateJob`의 `inputFile` 경로로,
/// (b) 전부 `ImagePageRef`이고 회전이 없으면 qpdf를 아예 거치지 않고 `ImagePdfBuilder.build`의
/// 결과를 그대로 최종 산출물로 쓰고, (c) 그 외(이미지+PDF 혼합, 다중 PDF 소스 인터리브, 회전
/// 있는 이미지 전용 문서)는 `image_encode_isolate.dart` + `ImagePdfBuilder`로
/// `<staging>/_images.pdf`를 만든 뒤 `buildComposeJob`으로 인터리브한다.
library;

import 'dart:io';

import '../core/app_error.dart';
import '../core/cancel_token.dart';
import '../core/progress.dart';
import '../core/size_guard.dart';
import 'image_encode_isolate.dart';
import 'image_pdf_builder.dart';
import 'image_quality.dart';
import 'page_ref.dart';
import 'qpdf_isolate.dart';

// `ImageQuality`는 `image_quality.dart`(신설)에 있다 — `pdf_compressor.dart`와 상호 import
// 없이 같은 타입을 공유하기 위함(§6.4 자동 검사 19). 이 export로 기존에
// `import 'pdf_engine.dart'`를 통해 `ImageQuality`를 쓰던 코드는 전부 그대로 컴파일된다.
export 'image_quality.dart' show ImageQuality;

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

/// qpdf(`dart:ffi` + `libqpdf.so`/`qpdf.dll`) 기반 구현체. `_workspace/15_architect_qpdf_migration.md`
/// §5(API 재설계)에 따라 `PdfrxPdfEngine`을 교체했다(§7.1 -- 어댑터 공존 없이 전면 교체).
class QpdfPdfEngine implements PdfEngine {
  /// [appRoot]는 앱 작업공간 루트(정규화 전 절대경로, 슬래시/백슬래시 무관). 모든 `outputPath`와
  /// `ImagePageRef.imagePath`는 이 루트 아래 `docs/**`로 고정된다(C4 -- 1라운드 실측:
  /// `/sdcard/Download/docs/<id>.tmp/document.pdf`나 `<root>/docs/<id>.tmp/anything.exe`가
  /// 루트 미바인딩 상태에서 통과했다).
  ///
  /// [libraryPathOverride]는 호스트 테스트 전용이다. Android에서는 `null`로 두면
  /// `qpdf_isolate.dart`가 기본값(`libqpdf.so`, APK `jniLibs`에서 자동 로딩)을 쓴다. 다른
  /// 플랫폼(Windows 호스트 테스트)에서는 `qpdf_isolate.dart`가 기본값 없이 예외를 던지므로
  /// 반드시 명시해야 한다(무음으로 잘못된 라이브러리를 찾지 않기 위함, `18_..._bindings.md` §4.2).
  const QpdfPdfEngine({required this.appRoot, this.libraryPathOverride});

  final String appRoot;
  final String? libraryPathOverride;

  @override
  Future<PdfResult<SaveOutcome>> save({
    required List<PageRef> pages,
    required String outputPath,
    required ImageQuality quality,
    required GuardInput guardInput,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final pathError = _validateStagingPath(outputPath, appRoot);
    if (pathError != null) return PdfErr(pathError);
    if (pages.isEmpty) return const PdfErr(UnknownFailure('pages must not be empty'));

    // §5 #2: ImagePageRef -> 화이트리스트+파일 존재, PdfPageRef -> 파일 존재+sourceIndex 범위.
    // sealed switch로 두 케이스를 전부 명시한다(B1 -- is 분기로 우회하지 않는다, default/_ 금지).
    final inspectedCounts = <String, int>{};
    for (final page in pages) {
      switch (page) {
        case ImagePageRef():
          final wl = _validateImageWhitelist(imagePath: page.imagePath, outputPath: outputPath, appRoot: appRoot);
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

    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    final hasImages = pages.any((p) => p is ImagePageRef);
    final pdfSources = pages.whereType<PdfPageRef>().map((p) => p.sourcePath).toSet();

    // §5.2 표 행 1&2: 전부 동일 소스의 PdfPageRef(회전 포함/미포함) -- `inputFile` 경로가 원본
    // 메타데이터를 보존하므로 더 저렴하다. `buildRotateJob`은 회전이 없을 때도 그대로 쓸 수 있다
    // (rotate 스펙이 비면 키 자체를 안 넣는다).
    if (!hasImages && pdfSources.length == 1) {
      final sourcePath = pdfSources.first;
      final entries = pages
          .cast<PdfPageRef>()
          .map((p) => QpdfPageEntry(sourceIndex: p.sourceIndex, rotation: p.rotation))
          .toList(growable: false);
      final resultMap = await runRotateJob(
        sourcePath: sourcePath,
        outputPath: outputPath,
        pages: entries,
        onProgress: onProgress,
        cancelToken: cancelToken,
        libraryPathOverride: libraryPathOverride,
      );
      return _finishFromJobResult(resultMap, guardInput, outputPath);
    }

    // §5.2 표 행 3&4: 이미지 전용 또는 혼합(compose).
    final preset = _presetFor(quality);
    return _saveCompose(
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
    final pathError = _validateStagingPath(outputPath, appRoot);
    if (pathError != null) return PdfErr(pathError);
    if (sourcePdfPaths.isEmpty) return const PdfErr(UnknownFailure('sourcePdfPaths must not be empty'));

    var baselineBytes = 0;
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
      }
    }

    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    // §5.2 표: `--empty` + 다중 소스(qpdf 대응 그대로). merge/split은 quality를 쓰지 않는다(A-6).
    final resultMap = await runMergeJob(
      sourcePdfPaths: sourcePdfPaths,
      outputPath: outputPath,
      onProgress: onProgress,
      cancelToken: cancelToken,
      libraryPathOverride: libraryPathOverride,
    );
    return _finishFromJobResult(resultMap, GuardInput(op: SaveOp.merge, baselineBytes: baselineBytes), outputPath);
  }

  @override
  Future<PdfResult<SaveOutcome>> split({
    required String sourcePdfPath,
    required List<int> pageIndices,
    required String outputPath,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final pathError = _validateStagingPath(outputPath, appRoot);
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

    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    // §5.2 표: buildSplitJob은 buildSaveJob과 동일 형태다 -- `--split-pages`(다중 출력)는 절대 쓰지 않는다.
    final resultMap = await runSplitJob(
      sourcePath: sourcePdfPath,
      outputPath: outputPath,
      pageIndices: pageIndices,
      onProgress: onProgress,
      cancelToken: cancelToken,
      libraryPathOverride: libraryPathOverride,
    );
    final guardInput = GuardInput(
      op: SaveOp.split,
      baselineBytes: info.bytes,
      totalPages: info.pageCount,
      selectedPages: pageIndices.length,
    );
    return _finishFromJobResult(resultMap, guardInput, outputPath);
  }

  @override
  Future<PdfResult<PdfDocInfo>> inspect(String pdfPath, {String? password}) async {
    final map = await runInspect(pdfPath: pdfPath, password: password, libraryPathOverride: libraryPathOverride);
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

  /// §5.6 저장 조립 구조의 (b)/(c) 분기 -- 이미지 전용 또는 혼합(이미지+PDF, 다중 PDF 소스 인터리브).
  Future<PdfResult<SaveOutcome>> _saveCompose({
    required List<PageRef> pages,
    required String outputPath,
    required GuardInput guardInput,
    required int longEdgeMaxPx,
    required int jpegQuality,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(PdfProgress(phase: PdfPhase.opening, done: 0, total: pages.length));

    // (경로, 크롭) 쌍으로 넘긴다 -- 같은 마스터 경로가 서로 다른 크롭으로 두 번 나올 수 있으므로
    // 경로 기준 dedupe를 하지 않는다(설계 §2.5). 페이지 순서 그대로의 리스트라 원래도 dedupe는
    // 없었다 -- `ImageEncodeItem` 전환으로 이 사실이 타입 수준에서도 분명해진다.
    final imageItems = [
      for (final p in pages)
        if (p is ImagePageRef) ImageEncodeItem(imagePath: p.imagePath, cropEncoded: p.crop?.encode()),
    ];
    String? imagesPdfPath;

    try {
      if (imageItems.isNotEmpty) {
        // 이미지 인코딩은 순수 Dart CPU 작업이므로 별도 워커 isolate로 보낸다(§5.6 -- `package:image`/
        // `package:pdf/`가 없는 isolate). qpdf가 이 워커를 전혀 쓰지 않는다(2-키 분리 유지).
        final encodeResult = await runImageEncodeBatch(
          items: imageItems,
          longEdgeMaxPx: longEdgeMaxPx,
          jpegQuality: jpegQuality,
          cancelToken: cancelToken,
        );
        if (encodeResult['ok'] != true) return PdfErr(_failureFromErrorMap(encodeResult));
        if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

        final encodedImages = (encodeResult['images']! as List).cast<EncodedImage>();
        onProgress?.call(PdfProgress(phase: PdfPhase.composing, done: encodedImages.length, total: pages.length));

        final builtBytes = await ImagePdfBuilder.build(
          jpegPages: [for (final e in encodedImages) e.bytes],
          title: null,
        );

        final allImages = pages.every((p) => p is ImagePageRef);
        final anyRotation = pages.any((p) => p.rotation != 0);
        if (allImages && !anyRotation) {
          // §5.2 표 행 3: qpdf 미사용 -- ImagePdfBuilder의 결과가 그대로 최종 산출물이다.
          if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());
          onProgress?.call(PdfProgress(phase: PdfPhase.writing, done: pages.length, total: pages.length));
          await File(outputPath).writeAsBytes(builtBytes, flush: true);
          final inspectResult = await inspect(outputPath);
          switch (inspectResult) {
            case PdfErr<PdfDocInfo>():
              try {
                await File(outputPath).delete();
              } catch (_) {
                // 최선 노력.
              }
              return PdfErr(inspectResult.failure);
            case PdfOk<PdfDocInfo>():
              return _finishFromJobResult(
                {'ok': true, 'bytes': inspectResult.value.bytes, 'pageCount': inspectResult.value.pageCount},
                guardInput,
                outputPath,
              );
          }
        }

        // qpdf 입력으로 쓸 임시 이미지 PDF. `<staging>/_images.pdf` (§5.6).
        imagesPdfPath = '${File(outputPath).parent.path}${Platform.pathSeparator}_images.pdf';
        await File(imagesPdfPath).writeAsBytes(builtBytes, flush: true);
      }

      if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

      // §5.2 표 행 4: 원본(들)과 `_images.pdf`를 최종 순서대로 인터리브한다.
      var imageCursor = 0;
      final sources = <QpdfPageSource>[];
      for (final page in pages) {
        switch (page) {
          case PdfPageRef():
            sources.add(QpdfPageSource(sourcePath: page.sourcePath, sourceIndex: page.sourceIndex, rotation: page.rotation));
          case ImagePageRef():
            sources.add(QpdfPageSource(sourcePath: imagesPdfPath!, sourceIndex: imageCursor, rotation: page.rotation));
            imageCursor++;
        }
      }

      final resultMap = await runComposeJob(
        pages: sources,
        outputPath: outputPath,
        onProgress: onProgress,
        cancelToken: cancelToken,
        libraryPathOverride: libraryPathOverride,
      );
      return _finishFromJobResult(resultMap, guardInput, outputPath);
    } finally {
      // `_images.pdf`는 qpdf 잡의 입력일 뿐이다 -- 최종 산출물은 [outputPath]이므로 성공/실패
      // 모두 이 임시 파일을 지운다(스테이징 디렉터리 자체는 Workspace.rollbackStaging 책임, Q-D).
      if (imagesPdfPath != null) {
        try {
          await File(imagesPdfPath).delete();
        } catch (_) {
          // 최선 노력.
        }
      }
    }
  }

  /// qpdf 잡 실행 결과를 `SizeGuard` 판정까지 이어 `PdfResult<SaveOutcome>`으로 마무리한다.
  /// merge/split/save의 세 분기가 전부 이 함수를 거친다 -- 게이트 우회 분기가 없다.
  Future<PdfResult<SaveOutcome>> _finishFromJobResult(
    Map<String, Object?> resultMap,
    GuardInput guardInput,
    String outputPath,
  ) async {
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

/// outputPath가 정확히 `<appRoot>/docs/<docId>.tmp/document.pdf` 형태인지 검증하고 `docId`를
/// 뽑는다. 형태가 아니면(루트 불일치·파일명 불일치 포함) null.
///
/// C4(2라운드 실측): 이전 구현은 `.*`(임의 접두사) + `[^/]+`(임의 파일명)를 허용해
/// `/sdcard/Download/docs/<id>.tmp/document.pdf`나 `<root>/docs/<id>.tmp/anything.exe`가
/// 통과했다. 이제 [appRoot]와 정확히 일치하는 접두사, 그리고 파일명 `document.pdf`만 허용한다.
({String docId})? _stagingScope(String outputPath, String appRoot) {
  final normalized = _normalize(outputPath);
  final normalizedRoot = _normalize(appRoot);
  final prefix = '$normalizedRoot/docs/';
  if (!normalized.startsWith(prefix)) return null;
  final rest = normalized.substring(prefix.length);
  final match = RegExp(r'^([^/]+)\.tmp/document\.pdf$').firstMatch(rest);
  if (match == null) return null;
  final docId = match.group(1)!;
  if (docId.isEmpty) return null;
  return (docId: docId);
}

/// outputPath가 `<appRoot>/docs/<docId>.tmp/document.pdf` 형태인지 검증한다(§2.3 계약 불변식 1).
PdfFailure? _validateStagingPath(String outputPath, String appRoot) {
  if (_stagingScope(outputPath, appRoot) == null) {
    return const UnknownFailure('outputPath must be <appRoot>/docs/<docId>.tmp/document.pdf');
  }
  return null;
}

/// `ImagePageRef.imagePath`가 §3.3 화이트리스트 안인지 검증한다.
/// 허용: `<appRoot>/docs/<docId>/sources/pages/` 또는 `<appRoot>/docs/<docId>.tmp/sources/pages/`
/// 하위뿐(같은 저장 요청의 outputPath에서 유도한 docId + 주입된 appRoot에 바인딩 -- V2 + C4).
PdfFailure? _validateImageWhitelist({required String imagePath, required String outputPath, required String appRoot}) {
  final scope = _stagingScope(outputPath, appRoot);
  if (scope == null) {
    return const UnknownFailure('image path outside sources');
  }
  final normalizedImg = _normalize(imagePath);
  final normalizedRoot = _normalize(appRoot);
  final committedPrefix = '$normalizedRoot/docs/${scope.docId}/sources/pages/';
  final stagingPrefix = '$normalizedRoot/docs/${scope.docId}.tmp/sources/pages/';

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
