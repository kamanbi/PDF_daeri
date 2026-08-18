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
  // qpdf 마이그레이션(M-Q3)으로 `pdf_engine_isolate.dart`(PDF 문서 핸들을 쥐던 파일)는 삭제되고
  // `pdf_engine.dart`가 오케스트레이터로서 그 역할(2-키 분리 준수 의무)을 물려받았다 -- 이미지
  // 코덱 API는 여전히 `image_pdf_builder.dart`/`image_encode_isolate.dart`에만 있어야 한다.
  group('§3.4-6 : pdf_engine.dart는 이미지 인코딩 API를 직접 쥐지 않는다(2-키 분리)', () {
    test("코드(주석 제외)에 'package:image', 'package:pdf/' 문자열이 0회다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/pdf_engine.dart'));
      expect(codeOnly.contains('package:image'), isFalse, reason: 'pdf_engine.dart가 package:image를 참조함');
      expect(codeOnly.contains('package:pdf/'), isFalse, reason: 'pdf_engine.dart가 package:pdf/를 참조함');
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
    const engineFiles = ['lib/pdf/pdf_engine.dart'];
    for (final path in engineFiles) {
      test("$path에 'Directory(', 'delete(recursive', 'deleteSync(recursive'가 없다", () {
        final source = _read(path);
        for (final token in const ['Directory(', 'delete(recursive', 'deleteSync(recursive']) {
          expect(source.contains(token), isFalse, reason: '$path가 디렉터리 삭제 API "$token"를 사용함 — Workspace의 단독 책임이다');
        }
      });
    }
  });

  // I2 (07_spec-guardian_report_r2.md): ImagePdfBuilder.build()는 SizeGuard를 거치지 않는 두 번째
  // PDF 바이트 생산자다. 호출부가 lib/pdf/**(엔진 내부) 밖으로 새면, 화면·Repository가
  // 엔진을 우회해 직접 PDF 바이트를 만들어 저장하는 경로가 생긴다 -- 그 경로는 게이트를
  // 거치지 않는다. lib/pdf/** 안에서만 참조를 허용해 우회로를 원천 차단한다.
  group('§3.4-11 : ImagePdfBuilder.build( 참조는 lib/pdf/** 안에서만 허용한다', () {
    test('lib/pdf/** 밖에서 ImagePdfBuilder.build( 를 호출하지 않는다', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        // `_dartFilesUnder('lib')`가 돌려주는 경로는 상대 경로('lib/pdf/x.dart')일 수 있어
        // 선행 슬래시가 없다 -- '/lib/pdf/'로만 검사하면 정당한 lib/pdf/** 내부 호출까지
        // 전부 위반으로 오탐한다(M-Q3 감사에서 실측: pdf_engine.dart 자신이 걸렸다). 선행
        // 슬래시 유무와 무관하게 매치되도록 좁힌다.
        if (normalized.contains('lib/pdf/')) continue;
        if (file.readAsStringSync().contains('ImagePdfBuilder.build(')) {
          violations.add(file.path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'lib/pdf/** 밖에서 ImagePdfBuilder.build( 호출: $violations -- SizeGuard를 우회하는 두 번째 저장 경로다',
      );
    });
  });

  group('§3.4-12 : dart:isolate를 import하는 파일과 pdfrx를 import하는 파일의 교집은 공집이다', () {
    test('같은 파일이 dart:isolate와 pdfrx를 동시에 import하지 않는다', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final source = file.readAsStringSync();
        final importsIsolate = source.contains("import 'dart:isolate'");
        final importsPdfrx = source.contains("import 'package:pdfrx");
        if (importsIsolate && importsPdfrx) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'dart:isolate와 pdfrx를 함께 import한 파일: $violations -- 같은 프로세스에서 pdfrx를 건드는 isolate가 둘이 되면 VM이 죽는다');
    });
  });

  // qpdf 마이그레이션(§15 §5.7)으로 정당한 Isolate.spawn( 호출부가 2개로 늘었다: 기존
  // image_encode_isolate.dart(이미지 인코딩)에 더해 qpdf_isolate.dart(§5.7 개정 -- qpdfjob_run이
  // 동기 블로킹 FFI라 워커 isolate로 옮겨야 한다). §3.4-12(dart:isolate ∩ pdfrx = ∅)는 그대로
  // 유효하다 -- qpdf_isolate.dart는 pdfrx를 import하지 않는다(§3.4-15에서 별도 확인).
  group('§3.4-13 : Isolate.spawn( 호출부는 정해진 워커 파일에만 있다', () {
    test('lib/pdf/**에서 Isolate.spawn(이 image_encode_isolate.dart·qpdf_isolate.dart에만 있다', () {
      const allowed = {'image_encode_isolate.dart', 'qpdf_isolate.dart'};
      final callers = <String>[];
      for (final file in _dartFilesUnder('lib/pdf')) {
        if (file.readAsStringSync().contains('Isolate.spawn(')) {
          callers.add(file.path.replaceAll('\\', '/'));
        }
      }
      final unexpected = callers.where((c) => !allowed.any(c.endsWith)).toList();
      expect(unexpected, isEmpty, reason: 'Isolate.spawn(이 허용 목록 밖에서 호출됨: $unexpected');
      expect(
        callers.map((c) => c.split('/').last).toSet(),
        allowed,
        reason: '허용된 2개 워커 파일이 실제로 전부 Isolate.spawn(을 쓰는지 확인(실측: $callers)',
      );
    });
  });

  group('§3.4-14 : stopBackgroundWorker를 호출하지 않는다', () {
    test("lib/ 전체에 'stopBackgroundWorker' 문자열이 0회다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.readAsStringSync().contains('stopBackgroundWorker')) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'stopBackgroundWorker 호출 발견: $violations -- 살아있는 문서 핸들이 있으면 UB다(FPDF_DestroyLibrary)');
    });
  });

  // ── §15(`_workspace/15_architect_qpdf_migration.md`) §5.7 "§3.4 자동 검사 추가분"(검사 14~18) ──
  // 문서의 번호(14~18)를 그대로 쓰면 위 §3.4-14(stopBackgroundWorker)와 충돌하므로, 이 파일
  // 내에서는 "§15 §5.7 검사 N" 이름으로 구분한다.
  group('§15 §5.7 검사14 : dart:ffi import는 qpdf_ffi.dart·qpdf_isolate.dart에만 있다', () {
    test("lib/**에서 \"import 'dart:ffi'\"가 이 2개 파일에만 있다", () {
      const allowed = {'qpdf_ffi.dart', 'qpdf_isolate.dart'};
      final callers = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.readAsStringSync().contains("import 'dart:ffi'")) {
          callers.add(file.path.replaceAll('\\', '/'));
        }
      }
      final unexpected = callers.where((c) => !allowed.any(c.endsWith)).toList();
      expect(unexpected, isEmpty, reason: "dart:ffi import가 허용 목록 밖에서 발견됨: $unexpected");
    });
  });

  group('§15 §5.7 검사15 : qpdf_isolate.dart는 pdfrx·이미지 인코딩 API를 쥐지 않는다(2-키 분리)', () {
    test("코드(주석 제외)에 'pdfrx', 'package:image', 'package:pdf/' 문자열이 0회다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
      for (final token in const ['pdfrx', 'package:image', 'package:pdf/']) {
        expect(codeOnly.contains(token), isFalse, reason: 'qpdf_isolate.dart가 금지 토큰 "$token"을 참조함');
      }
    });
  });

  group('§15 §5.7 검사16 : qpdf_isolate.dart의 잡 스펙에 금지 키가 없다(§5.3 화이트리스트)', () {
    test("코드(주석 제외)에 금지 키가 Map 키/값 리터럴로 등장하지 않는다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
      // 정확히 "Map 키 리터럴"(따옴표 직후 콜론) 형태만 검사한다 -- 단순 부분 문자열 검사는
      // qpdf-c.h의 정당한 API 식별자(qpdf_is_encrypted)·우리 자체 에러 코드('encrypted')·
      // 에러 텍스트 휴리스틱(text.contains('encrypt'))까지 오탐해 이 잡 자체를 구현 불가능하게
      // 만든다 -- inspect가 암호화 PDF를 판별하려면 "encrypt"라는 글자 자체는 불가피하게 코드에
      // 등장한다. 화이트리스트가 실제로 막아야 하는 것은 "이 단어를 job 스펙의 키로 쓰는 것"이다.
      final bannedKeyPattern = RegExp(r"""['"](replaceInput|splitPages|qdf|encrypt|linearize)['"]\s*:""");
      final bannedValuePattern = RegExp(r"""[:]\s*['"]uncompress['"]""");
      expect(bannedKeyPattern.hasMatch(codeOnly), isFalse, reason: '금지 키가 Map 리터럴로 등장함: ${bannedKeyPattern.allMatches(codeOnly).map((m) => m.group(0)).toList()}');
      expect(bannedValuePattern.hasMatch(codeOnly), isFalse, reason: 'streamData: uncompress 패턴 등장');
    });
  });

  group('§15 §5.7 검사17 : lib/**에서 Process.run/Process.start를 쓰지 않는다', () {
    test("CLI 실행 경로(§2.1 (B) 기각안)가 부활하지 않았다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final source = file.readAsStringSync();
        if (source.contains('Process.run(') || source.contains('Process.start(')) {
          violations.add(file.path.replaceAll('\\', '/'));
        }
      }
      expect(violations, isEmpty, reason: 'Process.run/Process.start 호출 발견: $violations');
    });
  });

  group('§15 §5.7 검사18 : qpdf_isolate.dart가 노출하는 공개 함수는 임의 JSON/argv 문자열을 받지 않는다', () {
    test('공개 함수 시그니처에 String 타입의 잡스펙/JSON/argv 파라미터가 없다', () {
      final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
      // "jobSpec"/"jobJson"/"argv" 류 이름의 String 파라미터가 톱레벨(비-`_` 접두) 함수 시그니처에
      // 있는지 본다. 내부(`_` 접두) 헬퍼는 제외 -- 그건 공개 API가 아니다.
      final publicFnPattern = RegExp(r'^(Future<[^>]+>|Map<[^>]+>|String|void)\s+([a-zA-Z][a-zA-Z0-9]*)\s*\(', multiLine: true);
      final suspiciousParamPattern = RegExp(r'String\??\s+(jobSpec|jobJson|argv)\w*', caseSensitive: false);
      for (final match in publicFnPattern.allMatches(codeOnly)) {
        final name = match.group(2)!;
        if (name.startsWith('_')) continue;
        // 함수 시그니처(파라미터 목록) 전체를 스캔한다. 이 코드베이스는 named parameter
        // (`{required ...}`)가 표준 스타일이다 -- 예전 구현은 "다음 '{' 또는 '=>' 까지"를
        // 시그니처로 잘랐는데, named parameter 블록 자체가 '{'로 시작하므로 파라미터 목록을
        // 전혀 못 보고 항상 빈 문자열만 검사하는 사각지대가 있었다(M-Q3 감사에서 실측: 위반을
        // 주입해도 이 검사가 통과했다). `(`부터 괄호 짝이 맞는 `)`까지 깊이 추적으로 정확히
        // 파라미터 목록 구간만 뽑는다.
        final start = match.start;
        final openParenIndex = match.end - 1; // publicFnPattern 자체가 '\(' 로 끝나므로 그 위치.
        var depth = 0;
        var closeParenIndex = -1;
        for (var i = openParenIndex; i < codeOnly.length; i++) {
          final ch = codeOnly[i];
          if (ch == '(') depth++;
          if (ch == ')') {
            depth--;
            if (depth == 0) {
              closeParenIndex = i;
              break;
            }
          }
        }
        final signature = closeParenIndex == -1 ? codeOnly.substring(start) : codeOnly.substring(start, closeParenIndex + 1);
        expect(
          suspiciousParamPattern.hasMatch(signature),
          isFalse,
          reason: '공개 함수 "$name"가 임의 JSON/argv 문자열을 받는 것으로 보임: $signature',
        );
      }
    });
  });

  // ── §15 §6.4 "자동 검사 추가분"(검사 19~21) — pdf_compressor.dart(M-Q6) 경계 강제 ──────────
  group('§15 §6.4 검사19 : pdf_compressor.dart ↔ pdf_engine.dart 상호 import가 0회다', () {
    test('pdf_compressor.dart가 pdf_engine.dart를 import하지 않는다', () {
      final source = _read('lib/pdf/pdf_compressor.dart');
      expect(source.contains("import 'pdf_engine.dart'"), isFalse, reason: 'pdf_compressor.dart가 pdf_engine.dart를 import함');
    });
    test('pdf_engine.dart가 pdf_compressor.dart를 import하지 않는다', () {
      final source = _read('lib/pdf/pdf_engine.dart');
      expect(source.contains("import 'pdf_compressor.dart'"), isFalse, reason: 'pdf_engine.dart가 pdf_compressor.dart를 import함');
    });
  });

  group('§15 §6.4 검사20 : 저장 경로 프리셋 리터럴이 pdf_compressor.dart에 없다', () {
    test('pdf_compressor.dart에 2480/1754/1240/85/75/60 리터럴이 0회다', () {
      final presetLiterals = RegExp(r'\b(2480|1754|1240|85|75|60)\b');
      final codeOnly = _codeOnly(_read('lib/pdf/pdf_compressor.dart'));
      expect(presetLiterals.hasMatch(codeOnly), isFalse, reason: 'pdf_compressor.dart에 프리셋 리터럴 발견 -- ImagePdfBuilder 상수를 참조할 것');
    });
  });

  group('§15 §6.4 검사21 : lib/**에서 SaveOp.compress 식별자가 0회다', () {
    test("'SaveOp.compress' 문자열이 lib/ 전체에 없다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.readAsStringSync().contains('SaveOp.compress')) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'SaveOp.compress 식별자 발견: $violations -- 압축 결과를 저장 경로로 우회시키는 유인이 된다(§6.3)');
    });
  });
}
