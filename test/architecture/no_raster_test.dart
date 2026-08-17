// 래스터화 구조적 봉쇄 자동 검사(§3.4). 소스 텍스트를 읽어 금지 패턴을 찾는다 — 빌드 불필요.
//
// 이 테스트는 "통과"가 목적이 아니라 "위반을 실제로 잡는지"가 목적이다. 규칙을 어기는 코드가
// 들어오면 반드시 여기서 실패해야 한다.
//
// R1(2026-08-18) 감사 반영: §3.4-2 정규식이 접미사 붙은 실제 공개 API 이름(renderPage 등)을
// 전부 통과시키던 사각지대를 막았다(V1). 대상 파일 하드코딩을 동적 수집으로 바꿨다 — 앞으로
// 추가될 `pdf_compressor.dart` 등이 자동으로 검사 대상에 들어온다. 검사기 자체의 회귀 테스트를
// 별도 그룹으로 추가했다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

/// 주석(`///`, `//`)을 제외한 코드 라인만 남긴다. "코드에 없다"를 검사할 때 쓴다.
String _codeOnly(String source) =>
    source.split('\n').where((line) => !line.trim().startsWith('///') && !line.trim().startsWith('//')).join('\n');

/// `lib/` 아래 `.dart` 파일 전체를 재귀 수집한다. 아직 없는 디렉터리는 빈 목록을 낸다.
List<File> _dartFilesUnder(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);
}

/// 저장 경로에 해당하는 파일을 규칙으로 선정한다(하드코딩 금지 — V1 수정 2).
/// `lib/pdf/**` 중 UI 렌더러(`pdf_renderer.dart`)를 제외한 전체다. 새 저장 경로 파일(예: 3주차
/// `pdf_compressor.dart`)이 추가되면 자동으로 이 목록에 들어온다.
///
/// `lib/data/**`는 포함하지 않는다 — `Workspace`는 `MethodChannel`(`package:flutter/services.dart`)로
/// 여유 공간을 조회하는 정당한 이유로 Flutter SDK를 import한다. §3.1 import 표도 flutter/dart:ui
/// 금지 대상을 `pdf_engine.dart`/`pdf_engine_isolate.dart`/`image_pdf_builder.dart`(및 향후 압축기)로
/// 한정한다 — 이 파일들만 PDF 페이지 핸들과 화면 그리기 API를 동시에 쥘 수 없어야 한다.
List<File> _rasterCoreFiles() {
  final files = <File>[];
  for (final f in _dartFilesUnder('lib/pdf')) {
    final normalized = f.path.replaceAll('\\', '/');
    if (normalized.endsWith('lib/pdf/pdf_renderer.dart')) continue;
    files.add(f);
  }
  return files;
}

/// §3.4-2가 쓰는 래스터화 식별자 탐지기. 접두·접미가 붙어도 잡히도록 **단어 경계 없이**
/// 대소문자 무시 부분 문자열로 검사한다(V1 수정 1). `render`가 `renderPage`/`_renderPdfPageToPng`/
/// `renderThumbnail`/`img.toImageSync()`처럼 다른 식별자에 파묻혀도 놓치지 않는다.
final rasterIdentifierPattern = RegExp(
  r'render|toimage|tobytedata|canvas|picturerecorder|bitmap|picture|decodeimagefrom|rasteri',
  caseSensitive: false,
);

void main() {
  final rasterCoreFiles = _rasterCoreFiles();

  group('검사기 자체 회귀 테스트 — 알려진 위반 형태를 반드시 잡는가', () {
    // 이번 라운드 감사(06_spec-guardian_report_r1.md V1)가 실측으로 확인한 사각지대 샘플들.
    // 이 목록이 전부 매치되지 않으면 정규식이 다시 약화된 것이다.
    const knownViolationSamples = <String>[
      'page.render(w)',
      'renderer.renderPage(x)',
      'renderThumbnail(x)',
      '_renderPdfPageToPng(p)',
      'img.toImageSync()',
      'createBitmap()',
      'Bitmap',
      'PictureRecorder',
      'Canvas(',
    ];
    for (final sample in knownViolationSamples) {
      test('"$sample" 은(는) rasterIdentifierPattern에 매치된다', () {
        expect(rasterIdentifierPattern.hasMatch(sample), isTrue, reason: '사각지대 재발: "$sample"이 검출되지 않는다');
      });
    }

    test('무해한 코드는 오탐하지 않는다(참고용 — 실패해도 빌드를 막지 않지만 과오탐 감시)', () {
      const benign = ['final x = 1;', 'class Foo {}', 'void save() {}'];
      for (final s in benign) {
        expect(rasterIdentifierPattern.hasMatch(s), isFalse, reason: '무해한 코드 "$s"가 오탐됨');
      }
    });
  });

  group('§3.4-1 : 저장 경로 파일이 렌더러·flutter/dart:ui를 import하지 않는다', () {
    for (final file in rasterCoreFiles) {
      test('${file.path}에 금지 import 문자열이 없다', () {
        final source = file.readAsStringSync();
        expect(source.contains("import 'package:flutter/"), isFalse, reason: '${file.path}: flutter SDK import 금지');
        expect(source.contains("import 'dart:ui'"), isFalse, reason: '${file.path}: dart:ui import 금지');
        expect(source.contains('pdf_renderer.dart'), isFalse, reason: '${file.path}: pdf_renderer.dart import 금지');
      });
    }
  });

  group('§3.4-2 : 저장 경로 파일에 래스터화 관련 식별자가 없다(접두·접미 포함)', () {
    for (final file in rasterCoreFiles) {
      test('${file.path}에 render/toImage/toByteData/Canvas/PictureRecorder/Bitmap/Picture가 없다', () {
        final matches = rasterIdentifierPattern.allMatches(file.readAsStringSync()).map((m) => m.group(0)).toList();
        expect(matches, isEmpty, reason: '${file.path} 위반: $matches');
      });
    }
  });

  group('§3.4-3 : lib/features/**에서 PDF 라이브러리 직접 import 금지', () {
    test('pdfrx/pdf/image 직접 import가 0회다', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/features')) {
        final source = file.readAsStringSync();
        if (source.contains("import 'package:pdfrx") ||
            source.contains("import 'package:pdf/") ||
            source.contains("import 'package:image/")) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'features가 PDF 라이브러리를 직접 import함: $violations');
    });
  });

  group('§3.4-4 : AdWidget 생성은 banner_host.dart 안에서만', () {
    test("'AdWidget(' 이 lib/ads/banner_host.dart 밖에 없다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (normalized.endsWith('lib/ads/banner_host.dart')) continue;
        if (file.readAsStringSync().contains('AdWidget(')) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'banner_host.dart 밖에서 AdWidget 생성: $violations');
    });
  });

  group('§3.4-5 : PdfEngine 인터페이스에 incremental 식별자가 없다', () {
    test("'incremental' 이 코드(주석 제외)에 없다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/pdf_engine.dart'));
      expect(RegExp(r'\bincremental\b').hasMatch(codeOnly), isFalse, reason: 'pdf_engine.dart 코드에 incremental 식별자 존재');
    });
  });

  // 6·7은 코드 라인만 검사한다(주석 제외) — 이 규칙을 설명하는 doc comment 자체가 금지 토큰을
  // 언급해야 하므로(예: "package:image를 쥐지 않는다"), 주석까지 포함하면 검사기가 자기 문서화에
  // 걸려 오탐한다. §3.4-5와 같은 방식(_codeOnly)을 재사용한다.
  group('§3.4-6 : pdf_engine_isolate.dart는 이미지 인코딩 API를 쥐지 않는다(2-키 분리)', () {
    test("코드(주석 제외)에 'package:image', 'package:pdf/' 문자열이 0회다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/pdf_engine_isolate.dart'));
      expect(codeOnly.contains('package:image'), isFalse, reason: 'pdf_engine_isolate.dart가 package:image를 참조함');
      expect(codeOnly.contains('package:pdf/'), isFalse, reason: 'pdf_engine_isolate.dart가 package:pdf/를 참조함');
    });
  });

  group('§3.4-7 : image_pdf_builder.dart는 PDF 문서·페이지 객체·파일 접근을 쥐지 않는다(2-키 분리)', () {
    test("코드(주석 제외)에 'pdfrx', PdfDocument, PdfPage, 'dart:io', 'File(' 이 없다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/image_pdf_builder.dart'));
      // 부분 문자열 토큰(파일 접근 관련) — 오탐 위험이 낮다.
      for (final token in const ['pdfrx', 'dart:io', 'File(']) {
        expect(codeOnly.contains(token), isFalse, reason: 'image_pdf_builder.dart에 금지 토큰 "$token" 존재');
      }
      // 식별자 토큰(pdfrx 타입명) — 단어 경계로 검사한다. `package:pdf`의 자체 타입인
      // `PdfPageFormat`/`PdfDocument`(package:pdf에는 이 이름의 클래스가 없다) 같은 합성
      // 식별자를 오탐하지 않게 하면서, 실제 pdfrx `PdfPage`/`PdfDocument` 타입 사용은 잡는다.
      for (final identifier in const ['PdfDocument', 'PdfPage']) {
        final matched = RegExp('\\b$identifier\\b').hasMatch(codeOnly);
        expect(matched, isFalse, reason: 'image_pdf_builder.dart에 금지 식별자 "$identifier" 존재');
      }
    });
  });

  group('§3.4-8 : image_pdf_builder.dart의 public 시그니처는 경로(String path류)를 받지 않는다', () {
    test("파일 경로로 보이는 'String ...[Pp]ath...' 파라미터가 코드에 없다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/image_pdf_builder.dart'));
      final matches = RegExp(r'String\??\s+\w*[Pp]ath\w*').allMatches(codeOnly).map((m) => m.group(0)).toList();
      expect(matches, isEmpty, reason: 'image_pdf_builder.dart가 경로 문자열 파라미터를 받음: $matches (바이트만 주고받아야 한다)');
    });
  });

  group('§3.4-9 : 저장 경로 프리셋 상수는 image_pdf_builder.dart에만 있다', () {
    test('프리셋 리터럴이 다른 lib/ 파일에 나타나지 않는다', () {
      final presetLiterals = RegExp(r'\b(2480|1754|1240|85|75|60)\b');
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (normalized.endsWith('lib/pdf/image_pdf_builder.dart')) continue;
        final codeOnly = _codeOnly(file.readAsStringSync());
        if (presetLiterals.hasMatch(codeOnly)) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'image_pdf_builder.dart 밖에서 프리셋 리터럴 발견(상수 참조로 바꿀 것): $violations');
    });
  });

  group('§3.4-10 : 엔진 파일은 Directory API를 쓰지 않는다(Q-D)', () {
    const engineFiles = ['lib/pdf/pdf_engine.dart', 'lib/pdf/pdf_engine_isolate.dart'];
    for (final path in engineFiles) {
      test("$path에 'Directory(', 'delete(recursive', 'deleteSync(recursive'가 없다", () {
        final source = _read(path);
        for (final token in const ['Directory(', 'delete(recursive', 'deleteSync(recursive']) {
          expect(source.contains(token), isFalse, reason: '$path가 디렉터리 삭제 API "$token"를 사용함 — Workspace의 단독 책임이다');
        }
      });
    }
  });
}
