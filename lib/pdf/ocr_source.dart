/// OCR 엔진 래퍼 진입점. `scan_source.dart`가 문서 스캐너 플러그인을 감싼 것과 **동일한
/// 격리 패턴**을 쓴다 — `google_mlkit_text_recognition`의 타입(`TextRecognizer`,
/// `RecognizedText`, `TextElement` 등)은 이 파일 밖으로 새지 않는다.
/// `_workspace/79_architect_v1.1_v2_design.md` §7.3·§7.5를 그대로 구현한다.
///
/// **isolate 경계(§7.5)**: ML Kit은 플랫폼 채널로 동작해 Dart isolate로 옮길 수 없다.
/// 이 파일은 **메인 isolate에서 호출**되는 것이 맞다 — 새로 isolate로 감싸지 않는다.
/// 워커로 넘어가는 것은 이 파일이 반환하는 [OcrPageResult]를 변환한 `StampPageSpec`뿐이며,
/// 그 변환은 `lib/pdf/ocr_text_layer.dart`(pdf-core 소유, 별도 라운드)가 담당한다.
///
/// **좌표 규약**: [OcrWord.rect]는 이미지 픽셀 크기에 대한 정규화 비율(0.0~1.0, 좌상단
/// 원점)이다 — `stamp_builder.dart`의 [StampRect]와 같은 타입을 그대로 재사용한다(두 번째
/// 좌표 타입을 만들지 않는다).
library;

import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../core/app_error.dart';
import 'stamp_builder.dart';

/// OCR 엔진 래퍼. **플러그인 타입은 이 파일 밖으로 새지 않는다**
/// (`scan_source.dart`와 동일한 격리 규약).
abstract interface class OcrSource {
  /// [imagePath]의 이미지를 인식한다. 좌표는 **이미지 픽셀 크기에 대한 정규화 비율**로
  /// 변환해 반환한다 — 픽셀 좌표를 경계 밖으로 내보내지 않는다(`StampRect`와 같은 규약).
  Future<PdfResult<OcrPageResult>> recognize(String imagePath);

  /// 플러그인 리소스 해제. 화면 이탈 시 호출한다.
  Future<void> dispose();
}

final class OcrPageResult {
  const OcrPageResult({required this.words, required this.fullText});

  /// 비가시 텍스트 레이어 생성용. 빈 리스트면 "인식된 텍스트 없음".
  final List<OcrWord> words;

  /// 클립보드 복사용 전체 텍스트(읽기 순서). Q8 승인 시에만 쓰인다.
  final String fullText;
}

final class OcrWord {
  const OcrWord({required this.text, required this.rect});
  final String text;
  final StampRect rect; // 0.0~1.0, 좌상단 원점 — StampMark와 같은 타입을 쓴다
}

/// `google_mlkit_text_recognition`(한국어+라틴 번들, §7.6) 기반 구현.
class MlKitOcrSource implements OcrSource {
  MlKitOcrSource({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.korean);

  final TextRecognizer _recognizer;

  @override
  Future<PdfResult<OcrPageResult>> recognize(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return PdfErr(SourceMissing(imagePath));
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(await file.readAsBytes());
    } catch (error) {
      return PdfErr(UnknownFailure('OCR 대상 이미지를 열 수 없습니다: $error'));
    }
    if (decoded == null) {
      return PdfErr(SourceCorrupted(imagePath));
    }
    final width = decoded.width.toDouble();
    final height = decoded.height.toDouble();
    if (width <= 0 || height <= 0) {
      return PdfErr(SourceCorrupted(imagePath));
    }

    final RecognizedText recognized;
    try {
      recognized = await _recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
    } catch (error) {
      return PdfErr(UnknownFailure('OCR 인식 실패: $error'));
    }

    final words = <OcrWord>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final box = element.boundingBox;
          final left = (box.left / width).clamp(0.0, 1.0);
          final top = (box.top / height).clamp(0.0, 1.0);
          final right = (box.right / width).clamp(0.0, 1.0);
          final bottom = (box.bottom / height).clamp(0.0, 1.0);
          if (right <= left || bottom <= top) {
            continue; // 폭·높이 0인 결과는 스탬프 마크로 만들 수 없다(StampRect 불변식).
          }
          words.add(
            OcrWord(
              text: element.text,
              rect: StampRect(
                left: left,
                top: top,
                right: right,
                bottom: bottom,
              ),
            ),
          );
        }
      }
    }

    return PdfOk(OcrPageResult(words: words, fullText: recognized.text));
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
