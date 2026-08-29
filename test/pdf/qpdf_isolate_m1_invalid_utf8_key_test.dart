// M-1 회귀 테스트(`_workspace/64_security_review_full_app.md` §M-1).
//
// RO 원칙: `/XObject` 딕셔너리 키에 유효하지 않은 UTF-8 바이트가 든 실제 PDF를 합성해 재현한다.
// 수정 전(`toDartString()`을 allowMalformed 없이 호출)에는 `_extractIsolateMain`이 `FormatException`으로
// 죽고, isolate에 `onError`/`onExit`가 없어 `runImageExtractJob`의 `await receivePort.first`가
// 영원히 완료되지 않아 압축/저장이 무한 대기에 빠졌다(§64 M-1). 이 테스트는 수정 전 코드로 실제
// 재현했다(20초 타임아웃 발동, FormatException 스택트레이스 확인) -- 아래는 수정 후 기대 동작.
//
// 수정 후: `allowMalformed: true`로 디코드 자체가 예외를 던지지 않고 U+FFFD로 대체되어 딕셔너리
// 열거가 깨진 키에서 멈추지 않고 끝까지 진행된다(정상 키 이미지가 정상적으로 발견됨). 깨진 키로
// 대체된 문자열은 원본의 실제 바이트열과 더 이상 같지 않으므로(U+FFFD 재인코딩 결과가 원본 바이트와
// 다르다) 그 항목 자체는 `qpdf_oh_get_key` 재조회에서 못 찾아 자연히 스킵된다 -- 이는 허용된
// 결과다(요구사항은 "그 키만 U+FFFD로 대체되고 열거가 계속 진행"이지, 그 항목의 추출 성공이
// 아니다). 설령 다른 경로에서 예외가 나더라도 isolate 진입점의 try/catch + 호출부의
// `Future.any([receivePort.first, errorPort.first])`가 무한 대기를 막는다.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';

import 'raw_pdf_fixture.dart';

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => p.join(Directory.current.path, _dllRelPath);
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();

/// 최소 유효 JPEG 바이트열(디코드하지 않는다 -- qpdf_dl_none으로 원시 바이트만 다루므로
/// 실제 JPEG 코덱 데이터일 필요가 없다. `raw_pdf_fixture.dart`의 다른 부적격 필터 테스트와
/// 동일한 관례).
List<int> _fakeJpeg(int tag) => [0xFF, 0xD8, 0xFF, 0xE0, tag, tag, tag, 0xFF, 0xD9];

void main() {
  group('M-1: /XObject 딕셔너리 키의 유효하지 않은 UTF-8 바이트', () {
    test('무한 대기 대신 정상적으로 완료되고(ok:true), 깨진 키를 건너뛰고도 정상 키의 이미지는 발견된다', () async {
      final tempDir = await Directory.systemTemp.createTemp('m1_invalid_utf8_key_');
      addTearDown(() => tempDir.delete(recursive: true));

      // 0xFF는 UTF-8에서 어떤 시퀀스로도 유효하지 않은 바이트(단독 사용 시 항상 디코드 실패).
      final pdfBytes = buildSinglePageImagePdfWithInvalidUtf8XObjectKey(
        jpegBytesGood: _fakeJpeg(0x11),
        jpegBytesBad: _fakeJpeg(0x22),
        width: 2000,
        height: 1500,
        rawInvalidKeyBytes: const [0xFF, 0xFE],
      );
      final srcPath = p.join(tempDir.path, 'invalid_utf8_key.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      // 수정 전에는 이 await가 영원히 완료되지 않았다(§M-1). 짧은 타임아웃으로 "무한 대기가 아님"을
      // 적극적으로 검증한다 -- 타임아웃 자체가 회귀 재현 증거다.
      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('runImageExtractJob이 M-1 무한 대기 회귀를 재현했다(20초 초과)'),
      );

      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      final images = (result['images'] as List).cast<Map<String, Object?>>();
      // 깨진 키(/Im<0xFF 0xFE>) 항목 자체는 재조회 불일치로 스킵되지만(위 주석 참고), 딕셔너리
      // 열거가 그 지점에서 죽지 않고 계속 진행돼 정상 키(/Im0)의 적격 이미지는 발견돼야 한다.
      expect(images.length, 1, reason: '깨진 키 하나 때문에 딕셔너리 열거 전체가 중단되면 안 된다 -- 정상 키 이미지는 발견돼야 한다');
      expect(images.single['w'], 2000);
      expect(images.single['h'], 1500);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(seconds: 30)));
  });
}
