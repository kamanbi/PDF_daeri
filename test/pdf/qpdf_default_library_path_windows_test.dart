// §68(`_workspace/68_architect_windows_port_design.md`) §2.5 W1 — `_defaultLibraryPath()`의
// Windows 분기 회귀 테스트.
//
// `_defaultLibraryPath()`는 private 함수라 직접 호출할 수 없다. 대신 `libraryPathOverride`를
// 넘기지 않고 `runInspect()`를 호출해 그 함수가 실제로 어떤 경로를 계산했는지 **관찰**한다:
// 존재하지 않는 PDF 경로를 주면 qpdf 라이브러리를 먼저 열려고 시도하므로, DLL이 그 계산된
// 경로에 없을 때 던지는 `DynamicLibrary.open` 예외 메시지에 계산된 절대경로 문자열이 그대로
// 나타난다. 수정 전에는 이 호출이 `StateError`("must be supplied explicitly")를 던졌다 —
// 그 문구가 더 이상 나오지 않는 것도 이 테스트가 함께 확인한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';

void main() {
  group('§68 §2.5 W1 : _defaultLibraryPath()의 Windows 분기', () {
    test(
      'Windows에서 libraryPathOverride 없이 호출하면 exe 옆의 qpdf30.dll 절대경로를 계산한다'
      '(StateError를 던지지 않는다)',
      () async {
        if (!Platform.isWindows) {
          markTestSkipped('Windows 전용 분기 -- 이 호스트는 Windows가 아니다');
          return;
        }

        final expectedPath = p.join(p.dirname(Platform.resolvedExecutable), 'qpdf30.dll');

        Object? caught;
        Map<String, Object?>? result;
        try {
          result = await runInspect(pdfPath: 'this_file_does_not_exist_anywhere.pdf');
        } catch (e) {
          caught = e;
        }

        // 기존 계약(override 없을 때 Android 외 플랫폼은 StateError) 회귀 확인: 더 이상
        // "must be supplied explicitly" 문구로 실패하지 않는다.
        expect(
          caught?.toString() ?? '',
          isNot(contains('must be supplied explicitly')),
          reason: 'Windows 분기가 있으면 예전 Android-only StateError가 나오면 안 된다',
        );

        // 테스트 러너 exe 옆에는 실제 qpdf30.dll이 없으므로 DynamicLibrary.open이 실패한다.
        // _inspectIsolateMain의 catch가 이를 흡수해 {'ok': false, ...}로 돌아온다(§68 확인).
        // 실패 상세 문자열에 우리가 독립적으로 계산한 절대경로가 그대로 들어있어야
        // p.join(p.dirname(Platform.resolvedExecutable), 'qpdf30.dll') 계산이 맞다는 증거가 된다.
        expect(caught, isNull, reason: '동기적으로 throw되지 않고 isolate 내부에서 흡수돼야 한다');
        expect(result, isNotNull);
        expect(result!['ok'], isFalse);
        expect(result['detail'].toString(), contains(expectedPath));
      },
    );
  });
}
