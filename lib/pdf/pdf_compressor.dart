/// 압축 도구. 편집 저장 경로(`pdf_engine.dart`)와 완전히 분리된 별도 진입점이다
/// (`_workspace/15_architect_qpdf_migration.md` §6.1 확정 — "압축은 qpdf와 독립이다").
///
/// **2층 구조 (§6.1)**
/// - L1 무손실 최적화 — 모든 문서(외부 PDF 포함). `qpdf_isolate.dart`에 이미 있는
///   `buildCompressJob`/`runCompressJob`을 그대로 쓴다(새 잡 빌더 불필요).
/// - L2 이미지 해상도 감소 — 모든 페이지가 `ImagePageRef`인 앱 생성 문서만(v1, §14 Q15).
///   qpdf는 임베드 이미지를 다운샘플링하지 못하므로(E18), `image_pdf_builder.dart`의
///   `encodeForEmbed`/`build`와 `image_encode_isolate.dart`를 그대로 재사용한다
///   (§6.2 — 새로 설계하지 않는다. 무손실 스킵 A-4·역효과 방지 A-5가 이미 구현돼 있다).
///
/// **레이어 경계**: 이 파일은 `lib/data/**`를 import하지 않는다. 대상 판별의 실제 근거인
/// `pages.kind`(DB 컬럼)는 PDF를 파싱해 재계산하지 않고, 호출자(Repository/향후 UI)가
/// [PdfCompressor.analyze]/[PdfCompressor.compress]의 매개변수로 그대로 넘긴다(§6.3).
///
/// **`pdf_engine.dart`와 상호 import하지 않는다**(§6.4 자동 검사 19) — 편집 저장 경로와
/// 압축 경로가 코드 수준에서 서로를 참조하지 못하게 막아, 압축 결과가 저장 경로로 우회하거나
/// 저장 경로가 압축을 호출하는 유인을 원천 차단한다. 두 파일이 공유해야 하는 `ImageQuality`
/// 타입은 `image_quality.dart`(신설)로 옮겼다.
///
/// **`SaveOp`에 압축용 값을 추가하지 않는다**(§6.1 확정) — 압축은 `PdfEngine.save`를 거치지
/// 않으므로 `GuardInput`/`GuardPass`가 개입할 자리가 없다. 결과 검증은 이 파일이 직접
/// [CompressOutcome.keptOriginal]로 수행한다(`SizeGuard`와는 별개의 장치, §6.3).
library;

import 'dart:io';

import '../core/app_error.dart';
import '../core/cancel_token.dart';
import '../core/progress.dart';
import 'image_encode_isolate.dart';
import 'image_pdf_builder.dart';
import 'image_quality.dart';
import 'qpdf_isolate.dart';

/// [analyze] 결과. `_workspace/01_architect_design.md` §2.6 시그니처.
class CompressTarget {
  const CompressTarget({required this.imageDominant, required this.reason});

  /// true면 L1+L2, false면 L1만 제안한다(§6.3 표).
  final bool imageDominant;

  /// `imageDominant=false`일 때 UI 안내 문구 키(`compress.reason.*`). `imageDominant=true`면 빈 문자열.
  final String reason;
}

class CompressOutcome {
  const CompressOutcome({required this.originalBytes, required this.resultBytes, required this.keptOriginal});

  final int originalBytes;
  final int resultBytes;

  /// true면 `resultBytes >= originalBytes`여서 산출물을 버리고 원본을 유지했다는 뜻이다.
  /// 이때 [resultBytes]는 [originalBytes]와 같은 값으로 채워진다(호출부가 감소율을 표시하지
  /// 않도록 `reduction == 0`이 되게 한다, §6.3 "0% 또는 음수 표시 금지").
  final bool keptOriginal;

  double get reduction => 1 - resultBytes / originalBytes;
}

abstract interface class PdfCompressor {
  /// 압축 효과가 있는 문서인지 판별한다. PDF를 파싱하지 않는다 — [pageKinds]는 호출자가
  /// DB `pages.kind`(문서의 페이지 순서대로 `'image'`|`'pdf'`)를 그대로 옮긴 것이다(§6.3).
  Future<PdfResult<CompressTarget>> analyze(String pdfPath, {required List<String> pageKinds});

  /// [imagePagePaths]는 L2(이미지 해상도 감소)를 실행할 때만 넘긴다 — 문서의 페이지 순서대로
  /// `sources/pages/NNN.jpg` 마스터 경로 목록이며(§6.3 2-1), **모든 페이지가 이미지인 문서에만**
  /// 유효하다(길이가 [pdfPath]의 실제 페이지 수와 다르면 거부한다 — 외부 PDF에 대한 이미지
  /// 다운샘플링은 v1.1로 이연됐고 이 경계를 코드로 강제한다, §6.1 Q15). `null`이면 L1만 실행한다.
  Future<PdfResult<CompressOutcome>> compress({
    required String pdfPath,
    required String outputPath,
    required ImageQuality preset,
    List<String>? imagePagePaths,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });
}

/// qpdf(L1) + `ImagePdfBuilder`(L2) 기반 구현체.
class QpdfCompressor implements PdfCompressor {
  /// [libraryPathOverride]는 호스트 테스트 전용이다(`qpdf_isolate.dart`의 동명 파라미터와 같은 규약
  /// — Android에서는 `null`로 두면 기본값 `libqpdf.so`를 쓰고, 다른 플랫폼은 명시가 필수다).
  const QpdfCompressor({this.libraryPathOverride});

  final String? libraryPathOverride;

  @override
  Future<PdfResult<CompressTarget>> analyze(String pdfPath, {required List<String> pageKinds}) async {
    if (!File(pdfPath).existsSync() || pageKinds.isEmpty) {
      return const PdfOk(CompressTarget(imageDominant: false, reason: 'compress.reason.unavailable'));
    }
    if (pageKinds.every((k) => k == 'image')) {
      return const PdfOk(CompressTarget(imageDominant: true, reason: ''));
    }
    if (pageKinds.every((k) => k == 'pdf')) {
      return const PdfOk(CompressTarget(imageDominant: false, reason: 'compress.reason.textDominant'));
    }
    return const PdfOk(CompressTarget(imageDominant: false, reason: 'compress.reason.mixed'));
  }

  @override
  Future<PdfResult<CompressOutcome>> compress({
    required String pdfPath,
    required String outputPath,
    required ImageQuality preset,
    List<String>? imagePagePaths,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final inputFile = File(pdfPath);
    if (!inputFile.existsSync()) {
      return PdfErr(SourceMissing(pdfPath));
    }
    if (_samePath(outputPath, pdfPath)) {
      // 절대 규칙 6(원본 미수정): 압축도 스테이징에 쓰고 호출자(Workspace)가 커밋한다.
      return const PdfErr(UnknownFailure('outputPath must differ from pdfPath'));
    }
    final originalBytes = inputFile.lengthSync();
    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    var l1Input = pdfPath;
    String? imagesPdfPath;
    try {
      if (imagePagePaths != null && imagePagePaths.isNotEmpty) {
        // v1.1 경계 강제(§6.1 Q15): L2는 "모든 페이지가 이미지"인 앱 생성 문서에만 허용된다.
        // pdfPath의 실제 페이지 수와 imagePagePaths 길이가 다르면(외부 PDF 오적용·혼합 문서
        // 오적용) 재인코딩을 실행하지 않고 즉시 거부한다.
        final inspectResult = await runInspect(pdfPath: pdfPath, libraryPathOverride: libraryPathOverride);
        if (inspectResult['ok'] != true) {
          return PdfErr(_failureFromErrorMap(inspectResult));
        }
        if (inspectResult['pageCount'] != imagePagePaths.length) {
          return const PdfErr(
            UnknownFailure(
              'imagePagePaths length must equal pdfPath page count -- L2 is app-generated all-image docs only (v1, §6.1 Q15)',
            ),
          );
        }

        final (longEdgeMaxPx, jpegQuality) = _presetFor(preset);
        final encodeResult = await runImageEncodeBatch(
          imagePaths: imagePagePaths,
          longEdgeMaxPx: longEdgeMaxPx,
          jpegQuality: jpegQuality,
          cancelToken: cancelToken,
        );
        if (encodeResult['ok'] != true) return PdfErr(_failureFromErrorMap(encodeResult));
        if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

        final encodedImages = (encodeResult['images']! as List).cast<EncodedImage>();
        onProgress?.call(PdfProgress(phase: PdfPhase.composing, done: encodedImages.length, total: imagePagePaths.length));

        final builtBytes = await ImagePdfBuilder.build(
          jpegPages: [for (final e in encodedImages) e.bytes],
          title: null,
        );

        // qpdf(L1) 입력으로만 쓰는 임시 파일. 성공/실패 모두 finally에서 지운다(pdf_engine.dart의
        // `_images.pdf` 처리와 같은 규약 — 최종 산출물은 [outputPath] 하나뿐이다).
        imagesPdfPath = '${File(outputPath).parent.path}${Platform.pathSeparator}_compress_images.pdf';
        await File(imagesPdfPath).writeAsBytes(builtBytes, flush: true);
        l1Input = imagesPdfPath;
      }

      if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

      // L1: 모든 문서(외부 PDF 포함) 공통. L2를 거쳤다면 입력은 방금 만든 임시 이미지 PDF다.
      final resultMap = await runCompressJob(
        sourcePath: l1Input,
        outputPath: outputPath,
        onProgress: onProgress,
        cancelToken: cancelToken,
        libraryPathOverride: libraryPathOverride,
      );
      if (resultMap['ok'] != true) {
        return PdfErr(_failureFromErrorMap(resultMap));
      }

      final resultBytes = resultMap['bytes']! as int;
      if (resultBytes >= originalBytes) {
        // §6.3 keptOriginal 규칙: 압축 효과가 없으면 산출물을 버리고 원본 유지를 알린다.
        // SizeGuard와는 별개의 장치다 — 압축은 SaveOp/GuardInput을 거치지 않는다.
        try {
          await File(outputPath).delete();
        } catch (_) {
          // 최선 노력.
        }
        return PdfOk(CompressOutcome(originalBytes: originalBytes, resultBytes: originalBytes, keptOriginal: true));
      }
      return PdfOk(CompressOutcome(originalBytes: originalBytes, resultBytes: resultBytes, keptOriginal: false));
    } finally {
      if (imagesPdfPath != null) {
        try {
          await File(imagesPdfPath).delete();
        } catch (_) {
          // 최선 노력.
        }
      }
    }
  }

  /// [preset] -> (longEdgeMaxPx, jpegQuality). 리터럴 숫자는 여기 없다 -- `image_pdf_builder.dart`의
  /// 프리셋 상수를 참조만 한다(§6.2, §6.4 자동 검사 20).
  (int, int) _presetFor(ImageQuality preset) => switch (preset) {
    ImageQuality.high => (ImagePdfBuilder.highLongEdgeMaxPx, ImagePdfBuilder.highJpegQuality),
    ImageQuality.standard => (ImagePdfBuilder.standardLongEdgeMaxPx, ImagePdfBuilder.standardJpegQuality),
    ImageQuality.min => (ImagePdfBuilder.minLongEdgeMaxPx, ImagePdfBuilder.minJpegQuality),
  };

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

/// 대소문자·구분자만 다른 같은 경로인지 가볍게 비교한다(§7.4 절대 규칙 6 방어용). 심볼릭 링크·
/// 상대경로 등 완전한 정규화는 하지 않는다 -- 호출자(Repository/Workspace)가 항상 절대경로를
/// 넘긴다는 전제이며, 이 검사는 "명백히 같은 문자열"을 잡는 안전망이다.
bool _samePath(String a, String b) => a.replaceAll('\\', '/') == b.replaceAll('\\', '/');
