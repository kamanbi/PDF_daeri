/// OCR 결과를 스탬프 마크로 옮기는 변환 전담. **그리지 않는다** — 그리는 것은
/// `stamp_builder.dart`(`StampBuilder`/`buildStampInIsolate`)의 몫이다.
/// `_workspace/79_architect_v1.1_v2_design.md` §7.4를 그대로 구현한다.
///
/// 이 파일이 담당하는 OCR 도메인 지식은 세 가지뿐이다:
/// - 좌표 변환: [OcrWord.rect]([StampRect], 정규화 비율) → [TextMark] (같은 타입을 그대로 옮긴다)
/// - 폰트 크기 추정: 단어 박스의 높이 비율 × 페이지 실제 높이(pt)의 단순 비례식
/// - 빈 단어(공백만 있거나 길이 0인 인식 결과) 스킵
///
/// **한글 폰트 필수(§7.4 경고)**: `invisible: true`라도 폰트가 없으면 글리프가 없어 텍스트
/// 추출이 깨진다. 그래서 [koreanFontBytes]가 없고 변환할 단어가 하나라도 있으면, 조용히
/// 스킵하지 않고 `stamp_builder.dart`의 기존 [StampBuildError.fontMissing] 계약을 그대로
/// 반환한다(예외를 던지지 않는다).
///
/// **새 저장 경로 없음**: 이 파일이 만드는 것은 [StampPageSpec] 하나뿐이다. 이후 흐름은
/// `buildStampInIsolate` → `PdfEngine.stamp`로, §2의 스탬프 메커니즘을 그대로 탄다.
library;

import 'dart:typed_data';

import 'ocr_source.dart';
import 'stamp_builder.dart';

/// [ocrResultToStampSpec]의 반환값. 성공이면 [spec]이 채워지고 [error]는 null이다.
/// 실패([error]가 non-null)면 [spec]은 null이다 — `StampBuildResult`와 같은 형태의 계약.
final class OcrTextLayerResult {
  const OcrTextLayerResult({this.spec, this.error});
  final StampPageSpec? spec;
  final StampBuildError? error; // null이면 성공
}

/// [OcrPageResult.words]를 페이지 한 장분의 [StampPageSpec]으로 변환한다.
///
/// [widthPt]/[heightPt]는 스탬프를 얹을 **대상 페이지의 실제 크기(pt)**여야 한다
/// (페이지 크기 조회 API가 주는 `PdfPageSize`를 그대로 넘긴다 — `stamp_builder.dart`의
/// `StampPageSpec` 계약과 동일).
///
/// [koreanFontBytes]는 `ocrResult.words`에 텍스트 마크로 옮길 단어가 하나라도 있으면
/// **필수**다. null이면 [StampBuildError.fontMissing]을 담은 결과를 반환한다(예외를 던지지
/// 않는다 — `stamp_builder.dart`의 기존 계약을 그대로 재사용한다). 호출부가 이 조건을 잊지
/// 않도록 시그니처에서 nullable로 강제 노출한다.
OcrTextLayerResult ocrResultToStampSpec({
  required OcrPageResult ocrResult,
  required double widthPt,
  required double heightPt,
  Uint8List? koreanFontBytes,
}) {
  final marks = <TextMark>[];
  for (final word in ocrResult.words) {
    final text = word.text.trim();
    if (text.isEmpty) {
      continue; // 공백만 있는 인식 결과는 스탬프 마크로 만들 가치가 없다.
    }
    marks.add(
      TextMark(
        rect: word.rect,
        text: word.text,
        fontSizePt: _estimateFontSizePt(rect: word.rect, pageHeightPt: heightPt),
        invisible: true,
      ),
    );
  }

  if (marks.isNotEmpty && koreanFontBytes == null) {
    return const OcrTextLayerResult(spec: null, error: StampBuildError.fontMissing);
  }

  return OcrTextLayerResult(
    spec: StampPageSpec(widthPt: widthPt, heightPt: heightPt, marks: marks),
    error: null,
  );
}

/// 단어 박스의 높이 비율을 페이지 실제 높이(pt)에 곱하는 단순 비례식으로 폰트 크기를 추정한다.
/// OCR 박스는 글자 상단 여백(어센더 위)을 포함해 실제 글자 높이보다 다소 크게 잡히는 경향이
/// 있어, 과대 추정을 보정하는 경험적 계수를 곱한다. 그 이상의 정교한 모델(행간·스크립트별
/// 보정 등)은 과설계이므로 두지 않는다.
double _estimateFontSizePt({required StampRect rect, required double pageHeightPt}) {
  const boundingBoxCorrectionFactor = 0.8;
  return rect.heightFraction * pageHeightPt * boundingBoxCorrectionFactor;
}
