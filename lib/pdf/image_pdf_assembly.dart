/// 이미지 페이지 배치를 인코딩해 단일 PDF 바이트로 조립하는 공유 스텝.
///
/// `pdf_engine.dart`(저장, `_saveCompose`)와 `pdf_compressor.dart`(압축, `_compressOnce`) 양쪽에
/// "인코딩(`runImageEncodeBatch`) → 취소 확인 → 진행률 보고(`PdfPhase.composing`) →
/// `ImagePdfBuilder.build` 호출" 패턴이 그대로 중복돼 있던 것을 여기로 뽑았다(전체 앱 재감사 L-5).
///
/// 이 파일은 조립 직전 단계까지만 공유한다 — 인코딩된 바이트를 어떻게 쓰는지는 호출자마다
/// 다르다: 저장 경로는 (allImages && !anyRotation)면 그대로 최종 산출물로 쓰고 아니면 qpdf
/// compose 입력으로 넘기며, 압축 경로는 항상 임시 파일로 써서 L1(qpdf) 입력으로만 쓴다. 그
/// 분기·정책(§6.3 "저장은 게이트 미통과 시 중단" vs "압축은 원본보다 커지면 원본 유지")은 각
/// 파일에 그대로 남겨두고 건드리지 않는다.
///
/// `pdf_engine.dart` <-> `pdf_compressor.dart` 상호 import 금지(§15 §6.4 검사19)는 이 파일과
/// 무관하게 그대로 유지된다 — 이 파일은 두 파일 중 어느 쪽도 import하지 않는, 둘이 함께
/// import하는 제3의 순수 헬퍼다.
library;

import 'dart:typed_data';

import '../core/app_error.dart';
import '../core/cancel_token.dart';
import '../core/progress.dart';
import 'image_encode_isolate.dart';
import 'image_pdf_builder.dart';

/// [encodeAndAssembleImagePdf]의 결과. 정확히 하나만 채워진다: 성공([bytes]),
/// 인코딩 실패([failure]), 또는 취소([cancelled]).
class ImagePdfAssemblyResult {
  const ImagePdfAssemblyResult._({
    this.bytes,
    this.failure,
    this.cancelled = false,
  });

  const ImagePdfAssemblyResult.ok(Uint8List bytes) : this._(bytes: bytes);

  const ImagePdfAssemblyResult.err(PdfFailure failure)
    : this._(failure: failure);

  const ImagePdfAssemblyResult.cancelledResult() : this._(cancelled: true);

  final Uint8List? bytes;
  final PdfFailure? failure;
  final bool cancelled;
}

/// [items]를 [longEdgeMaxPx]/[jpegQuality]로 인코딩한 뒤 `ImagePdfBuilder.build`로 단일 PDF
/// 바이트를 만든다.
///
/// [progressTotal]은 진행률 표시값일 뿐 정책이 아니다 — 저장 경로(`pdf_engine.dart`)는 혼합
/// 문서에서 전체 페이지 수를 넘기고, 압축 경로(`pdf_compressor.dart`)는 이미지 개수를 넘긴다.
/// 그 차이를 이 헬퍼가 고르지 않도록 호출자가 명시적으로 넘긴다.
///
/// [onErrorMap]은 `runImageEncodeBatch`의 에러 맵을 [PdfFailure]로 바꾸는 기존
/// `_failureFromErrorMap` 로직을 그대로 쓴다 (두 파일 모두 동일 구현을 이미 갖고 있어 여기서
/// 새로 만들지 않고 호출자 쪽 구현을 그대로 위임받는다).
Future<ImagePdfAssemblyResult> encodeAndAssembleImagePdf({
  required List<ImageEncodeItem> items,
  required int longEdgeMaxPx,
  required int jpegQuality,
  required int progressTotal,
  required PdfFailure Function(Map<String, Object?> map) onErrorMap,
  void Function(PdfProgress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final encodeResult = await runImageEncodeBatch(
    items: items,
    longEdgeMaxPx: longEdgeMaxPx,
    jpegQuality: jpegQuality,
    cancelToken: cancelToken,
  );
  if (encodeResult['ok'] != true) {
    return ImagePdfAssemblyResult.err(onErrorMap(encodeResult));
  }
  if (cancelToken?.isCancelled ?? false) {
    return const ImagePdfAssemblyResult.cancelledResult();
  }

  final encodedImages = (encodeResult['images']! as List)
      .cast<EncodedImage>();
  onProgress?.call(
    PdfProgress(
      phase: PdfPhase.composing,
      done: encodedImages.length,
      total: progressTotal,
    ),
  );

  final builtBytes = await ImagePdfBuilder.build(
    jpegPages: [for (final e in encodedImages) e.bytes],
    title: null,
  );
  return ImagePdfAssemblyResult.ok(builtBytes);
}
