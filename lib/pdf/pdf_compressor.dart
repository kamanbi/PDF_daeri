/// 압축 도구. 편집 저장 경로(`pdf_engine.dart`)와 완전히 분리된 별도 진입점이다
/// (`_workspace/15_architect_qpdf_migration.md` §6.1 확정 — "압축은 qpdf와 독립이다").
///
/// **2층 구조 (§6.1) + M-E5(`_workspace/31_architect_external_compress_l2.md`) L2-ext 확장**
/// - L1 무손실 최적화 — 모든 문서(외부 PDF 포함). `qpdf_isolate.dart`에 이미 있는
///   `buildCompressJob`/`runCompressJob`을 그대로 쓴다(새 잡 빌더 불필요).
/// - L2-app 이미지 해상도 감소 — 모든 페이지가 `ImagePageRef`인 앱 생성 문서만(v1, §14 Q15).
///   qpdf는 임베드 이미지를 다운샘플링하지 못하므로(E18), `image_pdf_builder.dart`의
///   `encodeForEmbed`/`build`와 `image_encode_isolate.dart`를 그대로 재사용한다
///   (§6.2 — 새로 설계하지 않는다. 무손실 스킵 A-4·역효과 방지 A-5가 이미 구현돼 있다).
///   [PdfCompressor.compress]의 `imagePagePaths` 파라미터로 실행한다.
/// - L2-ext 외부 PDF 임베디드 이미지 압축(M-E5 신설) — 3-패스 왕복: 패스 A(`runImageExtractJob`,
///   추출) → 패스 B(`runImageEncodeBatch`, 무변경 재사용) → 패스 C(`runImageReplaceJob`, 치환+쓰기)
///   → 패스 D(L1, `runCompressJob`). `embeddedImageStagingDir` 파라미터로 실행하며, `imagePagePaths`와
///   **상호 배타**다(§31 §2.6, 신설 검사24). 적격 이미지가 0개(텍스트 PDF 등)면 L1만 실행된다.
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
  const CompressOutcome({
    required this.originalBytes,
    required this.resultBytes,
    required this.keptOriginal,
  });

  final int originalBytes;
  final int resultBytes;

  /// true면 `resultBytes >= originalBytes`여서 산출물을 버리고 원본을 유지했다는 뜻이다.
  /// 이때 [resultBytes]는 [originalBytes]와 같은 값으로 채워진다(호출부가 감소율을 표시하지
  /// 않도록 `reduction == 0`이 되게 한다, §6.3 "0% 또는 음수 표시 금지").
  final bool keptOriginal;

  double get reduction => 1 - resultBytes / originalBytes;
}

/// 목표 용량 모드의 결과. `CompressOutcome`을 감싼다 — 상속하지 않는다(§76 §3.3).
class TargetCompressOutcome {
  const TargetCompressOutcome({
    required this.outcome,
    required this.targetBytes,
    required this.attempts,
    required this.finalRungIndex,
    required this.reachedTarget,
  });

  /// 최종 채택된 시도의 결과. `keptOriginal` 규칙은 여기서 그대로 유효하다.
  final CompressOutcome outcome;
  final int targetBytes;

  /// 실제로 실행한 압축 횟수(1..maxAttempts). `targetBytes >= 원본`이면 0이다(§3.4 step 0).
  final int attempts;

  /// 채택된 사다리 단 인덱스. 3 이상이면 "프리셋보다 더 낮춘" 결과다.
  /// [attempts]가 0(원본 유지 즉시 반환)이면 어떤 단도 시도하지 않았다는 뜻으로 -1이다
  /// (§3.4가 이 경우의 값을 지정하지 않아 "시도 없음" 센티널로 둔다).
  final int finalRungIndex;

  /// `outcome.resultBytes <= targetBytes`인가. false면 §3.5 미달 흐름.
  final bool reachedTarget;
}

/// 목표 용량 모드의 반복 진행 상황. `PdfProgress`(공유 타입)를 건드리지 않기 위해 별도로 둔다 —
/// `PdfProgress`는 매 시도마다 0부터 다시 올라간다(§76 §3.3).
class TargetAttempt {
  const TargetAttempt({
    required this.attempt,
    required this.maxAttempts,
    required this.rungIndex,
    required this.lastResultBytes,
  });

  /// 1-base.
  final int attempt;
  final int maxAttempts;
  final int rungIndex;

  /// 직전 시도(보존된 최선 결과)의 바이트 수. 첫 시도면 null.
  final int? lastResultBytes;
}

abstract interface class PdfCompressor {
  /// 압축 효과가 있는 문서인지 판별한다. PDF를 파싱하지 않는다 — [pageKinds]는 호출자가
  /// DB `pages.kind`(문서의 페이지 순서대로 `'image'`|`'pdf'`)를 그대로 옮긴 것이다(§6.3).
  Future<PdfResult<CompressTarget>> analyze(
    String pdfPath, {
    required List<String> pageKinds,
  });

  /// [imagePagePaths]는 L2-app(이미지 해상도 감소)을 실행할 때만 넘긴다 — 문서의 페이지 순서대로
  /// `sources/pages/NNN.jpg` 마스터 경로 목록이며(§6.3 2-1), **모든 페이지가 이미지인 문서에만**
  /// 유효하다(길이가 [pdfPath]의 실제 페이지 수와 다르면 거부한다 — 외부 PDF에 대한 이미지
  /// 다운샘플링은 v1.1로 이연됐고 이 경계를 코드로 강제한다, §6.1 Q15). `null`이면 L1만 실행한다.
  ///
  /// [embeddedImageStagingDir]는 L2-ext(외부 PDF 임베디드 이미지 압축, M-E5)를 실행할 때만 넘긴다
  /// (`_workspace/31_architect_external_compress_l2.md` §2.2/§2.6). [imagePagePaths]와 **상호
  /// 배타**다 — 둘 다 non-null이면 즉시 거부한다(§2.6 신설 검사24, §22의 기존 L2-app 경계는
  /// 완화하지 않는다).
  Future<PdfResult<CompressOutcome>> compress({
    required String pdfPath,
    required String outputPath,
    required ImageQuality preset,
    List<String>? imagePagePaths,
    String? embeddedImageStagingDir,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  });

  /// 목표 용량에 맞춰 사다리를 내려가며 반복 압축한다(§76 §3.3~§3.4).
  ///
  /// - [targetBytes] > 0. `targetBytes >= 원본 바이트`면 압축을 **한 번도 실행하지 않고**
  ///   `reachedTarget: true, attempts: 0, outcome.keptOriginal: true`로 즉시 반환한다.
  /// - [imagePagePaths] / [embeddedImageStagingDir]의 상호 배타 규약은 [compress]와 동일하며
  ///   매 시도에 그대로 전달된다. 새 경로를 만들지 않는다.
  /// - 최대 시도 횟수는 [maxAttempts](기본 3). 사다리 끝에 먼저 닿으면 그보다 적게 끝난다.
  /// - 어떤 경우에도 **페이지를 래스터화하지 않는다**(절대 규칙 2). 목표 미달은 실패가 아니라
  ///   `reachedTarget: false`로 보고되며, 그때까지의 최선 결과가 [outputPath]에 남는다.
  Future<PdfResult<TargetCompressOutcome>> compressToTarget({
    required String pdfPath,
    required String outputPath,
    required int targetBytes,
    List<String>? imagePagePaths,
    String? embeddedImageStagingDir,
    int maxAttempts = 3,
    void Function(PdfProgress)? onProgress,
    void Function(TargetAttempt)? onAttempt,
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
  Future<PdfResult<CompressTarget>> analyze(
    String pdfPath, {
    required List<String> pageKinds,
  }) async {
    if (!File(pdfPath).existsSync() || pageKinds.isEmpty) {
      return const PdfOk(
        CompressTarget(
          imageDominant: false,
          reason: 'compress.reason.unavailable',
        ),
      );
    }
    if (pageKinds.every((k) => k == 'image')) {
      return const PdfOk(CompressTarget(imageDominant: true, reason: ''));
    }
    if (pageKinds.every((k) => k == 'pdf')) {
      return const PdfOk(
        CompressTarget(
          imageDominant: false,
          reason: 'compress.reason.textDominant',
        ),
      );
    }
    return const PdfOk(
      CompressTarget(imageDominant: false, reason: 'compress.reason.mixed'),
    );
  }

  @override
  Future<PdfResult<CompressOutcome>> compress({
    required String pdfPath,
    required String outputPath,
    required ImageQuality preset,
    List<String>? imagePagePaths,
    String? embeddedImageStagingDir,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // §76 §1.5: "원본"은 저장 화질이지 압축 강도가 아니다. 패스스루 프리셋으로 압축을
    // 요청하면 재인코딩 없이 원본을 그대로 베끼는 셈이라 압축 기능 자체가 무의미해진다 --
    // 진입 즉시 거부한다(호출부가 UI를 잘못 배선해도 여기서 봉쇄된다). 이 판별은 `preset`에만
    // 의존하므로 `_compressOnce`(rung 기반)로 넘기지 않고 공개 진입점에서 처리한다.
    if (ImageQualityProfile.of(preset).isPassthrough) {
      return const PdfErr(
        UnknownFailure(
          'passthrough preset is a save-path quality, not a compression strength (§76 §1.5)',
        ),
      );
    }
    final rung = CompressLadder.rungs[CompressLadder.indexOf(preset)];
    return _compressOnce(
      pdfPath: pdfPath,
      outputPath: outputPath,
      rung: rung,
      imagePagePaths: imagePagePaths,
      embeddedImageStagingDir: embeddedImageStagingDir,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<PdfResult<TargetCompressOutcome>> compressToTarget({
    required String pdfPath,
    required String outputPath,
    required int targetBytes,
    List<String>? imagePagePaths,
    String? embeddedImageStagingDir,
    int maxAttempts = 3,
    void Function(PdfProgress)? onProgress,
    void Function(TargetAttempt)? onAttempt,
    CancelToken? cancelToken,
  }) async {
    final inputFile = File(pdfPath);
    if (!inputFile.existsSync()) {
      return PdfErr(SourceMissing(pdfPath));
    }
    final originalBytes = inputFile.lengthSync();

    // §3.4 step 0: targetBytes >= originalBytes -- 압축을 한 번도 실행하지 않는다.
    if (targetBytes >= originalBytes) {
      return PdfOk(
        TargetCompressOutcome(
          outcome: CompressOutcome(
            originalBytes: originalBytes,
            resultBytes: originalBytes,
            keptOriginal: true,
          ),
          targetBytes: targetBytes,
          attempts: 0,
          finalRungIndex: -1,
          reachedTarget: true,
        ),
      );
    }

    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    // §3.4: <cur>/<prev>는 outputPath와 outputPath+'.prev'를 번갈아 쓴다.
    final altPath = '$outputPath.prev';
    var curPath = outputPath;

    var i = CompressLadder.startIndexFor(
      originalBytes: originalBytes,
      targetBytes: targetBytes,
    );
    var attempt = 1;

    // 직전 시도 중 보존된 최선 결과(있으면). 매 루프에서 <prev> 역할을 한다.
    String? keptPrevPath;
    int? keptPrevBytes;
    int? keptPrevRungIndex;

    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        await _bestEffortDeletePath(keptPrevPath);
        return const PdfErr(Cancelled());
      }

      onAttempt?.call(
        TargetAttempt(
          attempt: attempt,
          maxAttempts: maxAttempts,
          rungIndex: i,
          lastResultBytes: keptPrevBytes,
        ),
      );

      final r = await _compressOnce(
        pdfPath: pdfPath,
        outputPath: curPath,
        rung: CompressLadder.rungs[i],
        imagePagePaths: imagePagePaths,
        embeddedImageStagingDir: embeddedImageStagingDir,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      if (r is PdfErr<CompressOutcome>) {
        // 취소·실패 -- 즉시 반환한다. 보존해 둔 <prev>와 이번 시도의 잔여물을 정리한다.
        await _bestEffortDeletePath(keptPrevPath);
        await _bestEffortDeletePath(curPath == outputPath ? null : curPath);
        return PdfErr(r.failure);
      }

      final outcome = (r as PdfOk<CompressOutcome>).value;

      if (outcome.keptOriginal) {
        // 이 단은 효과가 없었다(`_compressOnce`가 이미 curPath 파일을 지웠다).
        if (keptPrevPath != null) {
          if (keptPrevPath != outputPath) {
            await File(keptPrevPath).rename(outputPath);
          }
          return PdfOk(
            TargetCompressOutcome(
              outcome: CompressOutcome(
                originalBytes: originalBytes,
                resultBytes: keptPrevBytes!,
                keptOriginal: false,
              ),
              targetBytes: targetBytes,
              attempts: attempt,
              finalRungIndex: keptPrevRungIndex!,
              reachedTarget: keptPrevBytes <= targetBytes,
            ),
          );
        }
        return PdfOk(
          TargetCompressOutcome(
            outcome: outcome,
            targetBytes: targetBytes,
            attempts: attempt,
            finalRungIndex: i,
            reachedTarget: false,
          ),
        );
      }

      if (outcome.resultBytes <= targetBytes) {
        // 채택. 더 내려가지 않는다.
        await _bestEffortDeletePath(keptPrevPath);
        if (curPath != outputPath) {
          await File(curPath).rename(outputPath);
        }
        return PdfOk(
          TargetCompressOutcome(
            outcome: outcome,
            targetBytes: targetBytes,
            attempts: attempt,
            finalRungIndex: i,
            reachedTarget: true,
          ),
        );
      }

      // 미달 -- 최선 결과를 보존하고 다음 단으로 내려간다.
      await _bestEffortDeletePath(keptPrevPath);
      keptPrevPath = curPath;
      keptPrevBytes = outcome.resultBytes;
      keptPrevRungIndex = i;

      i += 1;
      attempt += 1;

      if (i >= CompressLadder.rungs.length || attempt > maxAttempts) {
        // 사다리 끝 또는 시도 소진 -- <prev>(마지막으로 보존한 결과)를 채택한다.
        // 절대 규칙 2: 여기서 새 rung을 즉흥 생성하지 않는다.
        if (keptPrevPath != outputPath) {
          await File(keptPrevPath).rename(outputPath);
        }
        return PdfOk(
          TargetCompressOutcome(
            outcome: CompressOutcome(
              originalBytes: originalBytes,
              resultBytes: keptPrevBytes,
              keptOriginal: false,
            ),
            targetBytes: targetBytes,
            attempts: attempt - 1,
            finalRungIndex: keptPrevRungIndex,
            reachedTarget: false,
          ),
        );
      }

      // 다음 <cur>는 번갈아 쓴다.
      curPath = (curPath == outputPath) ? altPath : outputPath;
    }
  }

  /// [compress]/[compressToTarget]가 공유하는 단일 압축 실행 본체(§76 §3.3 리팩터).
  /// [rung]은 이미 해상도 상한·JPEG 품질로 확정된 값이다 -- 프리셋 매핑은 호출자가 끝낸다.
  Future<PdfResult<CompressOutcome>> _compressOnce({
    required String pdfPath,
    required String outputPath,
    required CompressRung rung,
    List<String>? imagePagePaths,
    String? embeddedImageStagingDir,
    void Function(PdfProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // §2.6 신설 검사24: L2-app/L2-ext는 상호 배타다. 둘 다 지정되면 어느 쪽도 실행하지 않고 즉시
    // 거부한다 -- §22가 코드로 강제한 "외부 PDF에 imagePagePaths 금지" 경계를 완화하지 않는다.
    if (imagePagePaths != null && embeddedImageStagingDir != null) {
      return const PdfErr(
        UnknownFailure(
          'imagePagePaths and embeddedImageStagingDir are mutually exclusive (§31 §2.6)',
        ),
      );
    }

    final inputFile = File(pdfPath);
    if (!inputFile.existsSync()) {
      return PdfErr(SourceMissing(pdfPath));
    }
    if (_samePath(outputPath, pdfPath)) {
      // 절대 규칙 6(원본 미수정): 압축도 스테이징에 쓰고 호출자(Workspace)가 커밋한다.
      return const PdfErr(
        UnknownFailure('outputPath must differ from pdfPath'),
      );
    }
    final originalBytes = inputFile.lengthSync();
    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    var l1Input = pdfPath;
    String? imagesPdfPath;
    try {
      if (embeddedImageStagingDir != null) {
        final l2ExtResult = await _runEmbeddedImagePasses(
          pdfPath: pdfPath,
          stagingDir: embeddedImageStagingDir,
          rung: rung,
          cancelToken: cancelToken,
        );
        if (l2ExtResult is PdfErr<String?>) {
          return PdfErr(l2ExtResult.failure);
        }
        final intermediatePath = (l2ExtResult as PdfOk<String?>).value;
        if (intermediatePath != null) {
          // 패스 C(치환) 산출물 -- L1(패스 D) 입력으로만 쓰는 임시 파일. 최종 산출물은
          // outputPath 하나뿐이다(§2.2, imagesPdfPath 정리 규약과 동일).
          imagesPdfPath = intermediatePath;
          l1Input = intermediatePath;
        }
        // intermediatePath == null: 적격 이미지 0개(텍스트 PDF 등) -- L1만 실행한다(원본 그대로
        // l1Input 유지, §31 §2.5 "아무 일도 일어나지 않고 L1만 실행된다").
      }

      if (imagePagePaths != null && imagePagePaths.isNotEmpty) {
        // v1.1 경계 강제(§6.1 Q15): L2는 "모든 페이지가 이미지"인 앱 생성 문서에만 허용된다.
        // pdfPath의 실제 페이지 수와 imagePagePaths 길이가 다르면(외부 PDF 오적용·혼합 문서
        // 오적용) 재인코딩을 실행하지 않고 즉시 거부한다.
        final inspectResult = await runInspect(
          pdfPath: pdfPath,
          libraryPathOverride: libraryPathOverride,
        );
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

        // 압축 경로는 크롭 개념이 없다 -- 전부 cropEncoded: null(설계 §2.5, ImageEncodeItem 전환).
        final encodeResult = await runImageEncodeBatch(
          items: [
            for (final p in imagePagePaths)
              ImageEncodeItem(imagePath: p, cropEncoded: null),
          ],
          longEdgeMaxPx: rung.longEdgeMaxPx,
          jpegQuality: rung.jpegQuality,
          cancelToken: cancelToken,
        );
        if (encodeResult['ok'] != true)
          return PdfErr(_failureFromErrorMap(encodeResult));
        if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

        final encodedImages = (encodeResult['images']! as List)
            .cast<EncodedImage>();
        onProgress?.call(
          PdfProgress(
            phase: PdfPhase.composing,
            done: encodedImages.length,
            total: imagePagePaths.length,
          ),
        );

        final builtBytes = await ImagePdfBuilder.build(
          jpegPages: [for (final e in encodedImages) e.bytes],
          title: null,
        );

        // qpdf(L1) 입력으로만 쓰는 임시 파일. 성공/실패 모두 finally에서 지운다(pdf_engine.dart의
        // `_images.pdf` 처리와 같은 규약 — 최종 산출물은 [outputPath] 하나뿐이다).
        imagesPdfPath =
            '${File(outputPath).parent.path}${Platform.pathSeparator}_compress_images.pdf';
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
        return PdfOk(
          CompressOutcome(
            originalBytes: originalBytes,
            resultBytes: originalBytes,
            keptOriginal: true,
          ),
        );
      }
      return PdfOk(
        CompressOutcome(
          originalBytes: originalBytes,
          resultBytes: resultBytes,
          keptOriginal: false,
        ),
      );
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

  /// **M-E5** — L2-ext 3-패스 왕복(패스 A/B/C, `_workspace/31_...md` §2.2). [pdfPath]는 읽기
  /// 전용으로만 다룬다(절대 규칙 6) -- 치환은 [stagingDir]에 별도로 쓴 중간 파일에 일어난다.
  ///
  /// 반환 `PdfOk(null)`: 적격 이미지 0개(텍스트 PDF 등, §2.3 규칙 6종 어느 것도 통과 못 했거나
  /// 전부 R2/A-5 가드에 걸려 스킵됨) -- 호출자는 L1만 실행하면 된다(원본 그대로, 절대 규칙 2
  /// 봉쇄와 일치: "아무 일도 일어나지 않는다"). 반환 `PdfOk(path)`: [path]가 패스 C 산출물(치환된
  /// 중간 PDF) -- 호출자가 L1 입력으로 쓰고 정리한다.
  Future<PdfResult<String?>> _runEmbeddedImagePasses({
    required String pdfPath,
    required String stagingDir,
    required CompressRung rung,
    CancelToken? cancelToken,
  }) async {
    final longEdgeMaxPx = rung.longEdgeMaxPx;
    final jpegQuality = rung.jpegQuality;

    // 패스 A(M-E2): 추출. pdfPath는 읽기 전용으로만 열린다.
    final extractResult = await runImageExtractJob(
      pdfPath: pdfPath,
      stagingDir: stagingDir,
      longEdgeMaxPx: longEdgeMaxPx,
      cancelToken: cancelToken,
      libraryPathOverride: libraryPathOverride,
    );
    if (extractResult['ok'] != true)
      return PdfErr(_failureFromErrorMap(extractResult));
    final manifest = (extractResult['images']! as List)
        .cast<Map<String, Object?>>();
    if (manifest.isEmpty) {
      // 절대 규칙 2 봉쇄(§31 §2.5): 텍스트 PDF 등 적격 0개면 여기서 끝 -- 추출 I/O 이외의 아무
      // 일도 하지 않는다(콘텐츠 스트림·페이지는 이 경로 어디에서도 건드리지 않았다).
      return const PdfOk(null);
    }
    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    // 패스 B: image_encode_isolate.dart를 그대로 재사용한다(§2.2). 3주차 T2에서 시그니처가
    // `List<String>` -> `List<ImageEncodeItem>`으로 바뀌었으나(설계 §2.5), 이 경로는 크롭이 없으므로
    // 전부 cropEncoded: null로 감싸 넘긴다 -- 로직 자체는 무변경이다.
    final imagePaths = [for (final m in manifest) m['path']! as String];
    final encodeResult = await runImageEncodeBatch(
      items: [
        for (final p in imagePaths)
          ImageEncodeItem(imagePath: p, cropEncoded: null),
      ],
      longEdgeMaxPx: longEdgeMaxPx,
      jpegQuality: jpegQuality,
      cancelToken: cancelToken,
    );
    if (encodeResult['ok'] != true) {
      await _bestEffortDeleteAll(imagePaths);
      return PdfErr(_failureFromErrorMap(encodeResult));
    }
    if (cancelToken?.isCancelled ?? false) {
      await _bestEffortDeleteAll(imagePaths);
      return const PdfErr(Cancelled());
    }
    final encodedImages = (encodeResult['images']! as List)
        .cast<EncodedImage>();

    // 재검증 + R2 가드(§2.3 규칙5, 절대 규칙 "색공간이 다르면 통째로 스킵") + A-5(역효과 방지).
    // 성분 수 비교는 재인코딩 결과(항상 `ImagePdfBuilder.jpegPixelSize`가 계산, M-E4 실측대로
    // 그레이스케일 입력도 encodeJpg가 3성분으로 낸다)와 패스 A가 `/ColorSpace`에서 읽은 원본
    // 성분 수를 대조한다 -- 다르면 `/ColorSpace`를 추측해 고쳐 쓰지 않고 그 이미지를 통째로
    // 건너뛴다(추측 금지, 설계 확정 사항).
    final replacements = <ImageReplacement>[];
    for (var i = 0; i < manifest.length; i++) {
      final entry = manifest[i];
      final encoded = encodedImages[i];
      final origLen = File(entry['path']! as String).lengthSync();
      if (encoded.bytes.length >= origLen)
        continue; // A-5: 역효과면 이 이미지는 손대지 않는다.

      final newDims = ImagePdfBuilder.jpegPixelSize(encoded.bytes);
      if (newDims == null) continue; // 재인코딩 결과 헤더를 못 읽으면 스킵(있을 수 없지만 방어적).
      final (newWidth, newHeight, newComponents) = newDims;
      if (newComponents != entry['comps']! as int)
        continue; // R2: 성분 수 불일치 -> 통째로 스킵.

      replacements.add(
        ImageReplacement(
          objid: entry['objid']! as int,
          gen: entry['gen']! as int,
          newBytes: encoded.bytes,
          newWidth: newWidth,
          newHeight: newHeight,
          expectedWidth: entry['w']! as int,
          expectedHeight: entry['h']! as int,
        ),
      );
    }

    // 패스 A가 stagingDir에 쓴 추출 임시 JPEG은 더 이상 필요 없다(원본이 아니라 이 함수가 만든
    // 파일들이다 -- 절대 규칙 6과 무관, 정리 대상).
    await _bestEffortDeleteAll(imagePaths);

    if (replacements.isEmpty) return const PdfOk(null); // 전부 스킵됐다 -- L1만 실행한다.
    if (cancelToken?.isCancelled ?? false) return const PdfErr(Cancelled());

    // 패스 C(M-E3): 치환 + 쓰기. sourcePath는 원본 pdfPath 그대로(읽기 전용, 절대 규칙 6) --
    // 패스 A 이후 이 파일은 한 번도 쓰기로 열리지 않았다.
    final intermediatePath =
        '$stagingDir${Platform.pathSeparator}_compress_l2ext_intermediate.pdf';
    final replaceResult = await runImageReplaceJob(
      sourcePath: pdfPath,
      outputPath: intermediatePath,
      replacements: replacements,
      cancelToken: cancelToken,
      libraryPathOverride: libraryPathOverride,
    );
    if (replaceResult['ok'] != true)
      return PdfErr(_failureFromErrorMap(replaceResult));

    return PdfOk(intermediatePath);
  }

  Future<void> _bestEffortDeleteAll(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (_) {
        // 최선 노력 -- 상위(Workspace.rollbackStaging)가 스테이징 디렉터리 전체를 정리한다.
      }
    }
  }

  /// [compressToTarget]의 `<prev>`/`<cur>` 파일 정리 전용 헬퍼. `path`가 null이면 아무것도
  /// 하지 않는다(보존된 이전 결과가 없는 경우).
  Future<void> _bestEffortDeletePath(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // 최선 노력.
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

/// 대소문자·구분자만 다른 같은 경로인지 가볍게 비교한다(§7.4 절대 규칙 6 방어용). 심볼릭 링크·
/// 상대경로 등 완전한 정규화는 하지 않는다 -- 호출자(Repository/Workspace)가 항상 절대경로를
/// 넘긴다는 전제이며, 이 검사는 "명백히 같은 문자열"을 잡는 안전망이다.
bool _samePath(String a, String b) =>
    a.replaceAll('\\', '/') == b.replaceAll('\\', '/');
