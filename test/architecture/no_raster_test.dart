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

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) => File(relativePath).readAsStringSync();

/// 주석(`///`, `//`)을 제외한 코드 라인만 남긴다. "코드에 없다"를 검사할 때 쓴다.
String _codeOnly(String source) => source
    .split('\n')
    .where(
      (line) => !line.trim().startsWith('///') && !line.trim().startsWith('//'),
    )
    .join('\n');

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
        expect(
          rasterIdentifierPattern.hasMatch(sample),
          isTrue,
          reason: '사각지대 재발: "$sample"이 검출되지 않는다',
        );
      });
    }

    test('무해한 코드는 오탐하지 않는다(참고용 — 실패해도 빌드를 막지 않지만 과오탐 감시)', () {
      const benign = ['final x = 1;', 'class Foo {}', 'void save() {}'];
      for (final s in benign) {
        expect(
          rasterIdentifierPattern.hasMatch(s),
          isFalse,
          reason: '무해한 코드 "$s"가 오탐됨',
        );
      }
    });

    // R1(§2.4-R1 T11) : 검사2-b의 `PdfTextRenderingMode` 마스킹이 인접 위반을 함께 삼키지
    // 않는지 확인한다 — 이 개정의 유일한 실패 지점.
    group('검사2-b 마스킹 회귀(§2.4-R1) — 인접 위반을 삼키지 않는다', () {
      String masked(String s) => s.replaceAll('PdfTextRenderingMode', '');

      test('"PdfTextRenderingMode.invisible; page.render(x);" 는 마스킹 후에도 매치된다(반드시 실패해야 함)', () {
        const sample = 'final m = PdfTextRenderingMode.invisible; page.render(x);';
        expect(
          rasterIdentifierPattern.hasMatch(masked(sample)),
          isTrue,
          reason: '인접한 render 위반이 마스킹에 함께 삼켜짐: $sample',
        );
      });

      test('"PdfTextRenderingModeRenderPage" 는 마스킹 후에도 매치된다(반드시 실패해야 함, 우회 시도)', () {
        const sample = 'PdfTextRenderingModeRenderPage';
        expect(
          rasterIdentifierPattern.hasMatch(masked(sample)),
          isTrue,
          reason: '식별자를 붙여 쓰는 우회 시도가 마스킹을 통과함: $sample',
        );
      });

      test('"PdfTextRenderingMode.invisible" 단독은 마스킹 후 매치되지 않는다(유일한 허용)', () {
        const sample = 'PdfTextRenderingMode.invisible';
        expect(
          rasterIdentifierPattern.hasMatch(masked(sample)),
          isFalse,
          reason: '유일하게 허용돼야 할 식별자가 마스킹 후에도 위반으로 남음: $sample',
        );
      });
    });
  });

  group('§3.4-1 : 저장 경로 파일이 렌더러·flutter/dart:ui를 import하지 않는다', () {
    for (final file in rasterCoreFiles) {
      test('${file.path}에 금지 import 문자열이 없다', () {
        final source = file.readAsStringSync();
        expect(
          source.contains("import 'package:flutter/"),
          isFalse,
          reason: '${file.path}: flutter SDK import 금지',
        );
        expect(
          source.contains("import 'dart:ui'"),
          isFalse,
          reason: '${file.path}: dart:ui import 금지',
        );
        expect(
          source.contains('pdf_renderer.dart'),
          isFalse,
          reason: '${file.path}: pdf_renderer.dart import 금지',
        );
      });
    }
  });

  // R1(2026-09-22, `79_architect_v1.1_v2_design.md` §2.4-R1) : `stamp_builder.dart`는
  // `PdfTextRenderingMode.invisible`(Tr 3 -- OCR/텍스트 주석 비가시 레이어의 유일한 구현 수단)을
  // 쓴다. 그 식별자가 `render`를 부분 문자열로 포함해 검사2와 오탐 충돌한다. `stamp_builder.dart`를
  // **검사2 그룹에서만** 빼고(검사1은 그대로 받는다 -- 위 `rasterCoreFiles`는 무변경), 대신
  // 검사2-b(아래)가 이 파일을 전용 축소 검사로 검증한다. `_rasterCoreFiles()` 자체를 고치지
  // 않는다 -- 고치면 검사1까지 함께 풀려 봉쇄가 무너진다(`81_spec-guardian_r1_reverify.md` V1).
  final rasterCoreFilesExceptStampBuilder = rasterCoreFiles.where((f) {
    final normalized = f.path.replaceAll('\\', '/');
    return !normalized.endsWith('lib/pdf/stamp_builder.dart');
  }).toList(growable: false);

  group('§3.4-2 : 저장 경로 파일에 래스터화 관련 식별자가 없다(접두·접미 포함)', () {
    for (final file in rasterCoreFilesExceptStampBuilder) {
      test(
        '${file.path}에 render/toImage/toByteData/Canvas/PictureRecorder/Bitmap/Picture가 없다',
        () {
          final matches = rasterIdentifierPattern
              .allMatches(file.readAsStringSync())
              .map((m) => m.group(0))
              .toList();
          expect(matches, isEmpty, reason: '${file.path} 위반: $matches');
        },
      );
    }
  });

  // R1 신설 검사2-b : `stamp_builder.dart` 전용 축소 래스터 검사(§2.4-R1). `rasterIdentifierPattern`
  // 자체는 한 글자도 바꾸지 않는다 -- 정확히 `PdfTextRenderingMode` 문자열 1개만 마스킹한 뒤 같은
  // 패턴을 그대로 적용한다. 허용되는 것은 이 식별자 하나뿐이다.
  group('§2.4-R1 검사2-b : stamp_builder.dart는 PdfTextRenderingMode 오탐 1건 외 래스터 식별자가 없다', () {
    test('PdfTextRenderingMode만 마스킹한 뒤에도 다른 래스터 식별자가 0건이다', () {
      final codeOnly = _codeOnly(_read('lib/pdf/stamp_builder.dart'));
      final masked = codeOnly.replaceAll('PdfTextRenderingMode', '');
      final matches = rasterIdentifierPattern.allMatches(masked).map((m) => m.group(0)).toList();
      expect(
        matches,
        isEmpty,
        reason: 'stamp_builder.dart 위반(PdfTextRenderingMode 마스킹 후에도 래스터 식별자 존재): $matches',
      );
    });
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
      expect(
        violations,
        isEmpty,
        reason: 'features가 PDF 라이브러리를 직접 import함: $violations',
      );
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
      expect(
        violations,
        isEmpty,
        reason: 'banner_host.dart 밖에서 AdWidget 생성: $violations',
      );
    });
  });

  group('T10 : EditCornersScreen 산발 신설 금지', () {
    test("'EditCornersScreen' 이 lib/ 전체에 없다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.readAsStringSync().contains('EditCornersScreen')) {
          violations.add(file.path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '자체 크롭 화면(EditCornersScreen) 신설 발견: $violations',
      );
    });
  });

  group('§3.4-5 : PdfEngine 인터페이스에 incremental 식별자가 없다', () {
    test("'incremental' 이 코드(주석 제외)에 없다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/pdf_engine.dart'));
      expect(
        RegExp(r'\bincremental\b').hasMatch(codeOnly),
        isFalse,
        reason: 'pdf_engine.dart 코드에 incremental 식별자 존재',
      );
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
      expect(
        codeOnly.contains('package:image'),
        isFalse,
        reason: 'pdf_engine.dart가 package:image를 참조함',
      );
      expect(
        codeOnly.contains('package:pdf/'),
        isFalse,
        reason: 'pdf_engine.dart가 package:pdf/를 참조함',
      );
    });
  });

  // R1(§2.4-R1, `79_architect_v1.1_v2_design.md` 검사7) : `stamp_builder.dart`도 §2.2 doc
  // comment대로 `pdfrx`/`dart:io`/`File(`/`PdfPageRef`를 쥐지 않는 2-키 분리 파일이다.
  // `image_pdf_builder.dart`와 같은 금지 토큰을 그대로 적용한다.
  const pdfImageOwnerFiles = ['lib/pdf/image_pdf_builder.dart', 'lib/pdf/stamp_builder.dart'];

  group(
    '§3.4-7(+R1 stamp_builder.dart 확장) : PDF 문서·페이지 객체·파일 접근을 쥐지 않는다(2-키 분리)',
    () {
      for (final path in pdfImageOwnerFiles) {
        test(
          "$path의 코드(주석 제외)에 'pdfrx', PdfDocument, PdfPage, 'dart:io', 'File(' 이 없다",
          () {
            final codeOnly = _codeOnly(_read(path));
            // 부분 문자열 토큰(파일 접근 관련) — 오탐 위험이 낮다.
            for (final token in const ['pdfrx', 'dart:io', 'File(']) {
              expect(
                codeOnly.contains(token),
                isFalse,
                reason: '$path에 금지 토큰 "$token" 존재',
              );
            }
            // 식별자 토큰(pdfrx 타입명) — 단어 경계로 검사한다. `package:pdf`의 자체 타입인
            // `PdfPageFormat`/`PdfDocument`(package:pdf에는 이 이름의 클래스가 없다) 같은 합성
            // 식별자를 오탐하지 않게 하면서, 실제 pdfrx `PdfPage`/`PdfDocument` 타입 사용은 잡는다.
            for (final identifier in const ['PdfDocument', 'PdfPage']) {
              final matched = RegExp('\\b$identifier\\b').hasMatch(codeOnly);
              expect(
                matched,
                isFalse,
                reason: '$path에 금지 식별자 "$identifier" 존재',
              );
            }
          },
        );
      }
    },
  );

  group(
    '§3.4-8(+R1 stamp_builder.dart 확장) : public 시그니처는 경로(String path류)를 받지 않는다',
    () {
      for (final path in pdfImageOwnerFiles) {
        test("$path -- 파일 경로로 보이는 'String ...[Pp]ath...' 파라미터가 코드에 없다", () {
          final codeOnly = _codeOnly(_read(path));
          final matches = RegExp(
            r'String\??\s+\w*[Pp]ath\w*',
          ).allMatches(codeOnly).map((m) => m.group(0)).toList();
          expect(
            matches,
            isEmpty,
            reason: '$path가 경로 문자열 파라미터를 받음: $matches (바이트만 주고받아야 한다)',
          );
        });
      }
    },
  );

  group('§3.4-9 : 저장·압축 화질 프리셋 상수는 image_quality.dart에만 있다', () {
    test('프리셋 리터럴이 다른 lib/ 파일에 나타나지 않는다', () {
      final presetLiterals = RegExp(r'\b(2480|1754|1240|85|75|60)\b');
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (normalized.endsWith('lib/pdf/image_quality.dart')) continue;
        final codeOnly = _codeOnly(file.readAsStringSync());
        if (presetLiterals.hasMatch(codeOnly)) {
          violations.add(file.path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'image_quality.dart 밖에서 프리셋 리터럴 발견(프로필 참조로 바꿀 것): $violations',
      );
    });
  });

  group('§3.4-10 : 엔진 파일은 Directory API를 쓰지 않는다(Q-D)', () {
    const engineFiles = ['lib/pdf/pdf_engine.dart'];
    for (final path in engineFiles) {
      test(
        "$path에 'Directory(', 'delete(recursive', 'deleteSync(recursive'가 없다",
        () {
          final source = _read(path);
          for (final token in const [
            'Directory(',
            'delete(recursive',
            'deleteSync(recursive',
          ]) {
            expect(
              source.contains(token),
              isFalse,
              reason: '$path가 디렉터리 삭제 API "$token"를 사용함 — Workspace의 단독 책임이다',
            );
          }
        },
      );
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
        reason:
            'lib/pdf/** 밖에서 ImagePdfBuilder.build( 호출: $violations -- SizeGuard를 우회하는 두 번째 저장 경로다',
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
      expect(
        violations,
        isEmpty,
        reason:
            'dart:isolate와 pdfrx를 함께 import한 파일: $violations -- 같은 프로세스에서 pdfrx를 건드는 isolate가 둘이 되면 VM이 죽는다',
      );
    });
  });

  // qpdf 마이그레이션(§15 §5.7)으로 정당한 Isolate.spawn( 호출부가 2개로 늘었다: 기존
  // image_encode_isolate.dart(이미지 인코딩)에 더해 qpdf_isolate.dart(§5.7 개정 -- qpdfjob_run이
  // 동기 블로킹 FFI라 워커 isolate로 옮겨야 한다). §3.4-12(dart:isolate ∩ pdfrx = ∅)는 그대로
  // 유효하다 -- qpdf_isolate.dart는 pdfrx를 import하지 않는다(§3.4-15에서 별도 확인).
  group('§3.4-13 : Isolate.spawn( 호출부는 정해진 워커 파일에만 있다', () {
    test(
      'lib/pdf/**에서 Isolate.spawn(이 image_encode_isolate.dart·qpdf_isolate.dart에만 있다',
      () {
        const allowed = {'image_encode_isolate.dart', 'qpdf_isolate.dart'};
        final callers = <String>[];
        for (final file in _dartFilesUnder('lib/pdf')) {
          if (file.readAsStringSync().contains('Isolate.spawn(')) {
            callers.add(file.path.replaceAll('\\', '/'));
          }
        }
        final unexpected = callers
            .where((c) => !allowed.any(c.endsWith))
            .toList();
        expect(
          unexpected,
          isEmpty,
          reason: 'Isolate.spawn(이 허용 목록 밖에서 호출됨: $unexpected',
        );
        expect(
          callers.map((c) => c.split('/').last).toSet(),
          allowed,
          reason: '허용된 2개 워커 파일이 실제로 전부 Isolate.spawn(을 쓰는지 확인(실측: $callers)',
        );
      },
    );
  });

  group('§3.4-14 : stopBackgroundWorker를 호출하지 않는다', () {
    test("lib/ 전체에 'stopBackgroundWorker' 문자열이 0회다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.readAsStringSync().contains('stopBackgroundWorker')) {
          violations.add(file.path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'stopBackgroundWorker 호출 발견: $violations -- 살아있는 문서 핸들이 있으면 UB다(FPDF_DestroyLibrary)',
      );
    });
  });

  // ── §15(`_workspace/15_architect_qpdf_migration.md`) §5.7 "§3.4 자동 검사 추가분"(검사 14~18) ──
  // 문서의 번호(14~18)를 그대로 쓰면 위 §3.4-14(stopBackgroundWorker)와 충돌하므로, 이 파일
  // 내에서는 "§15 §5.7 검사 N" 이름으로 구분한다.
  group(
    '§15 §5.7 검사14 : dart:ffi import는 qpdf_ffi.dart·qpdf_isolate.dart에만 있다',
    () {
      test("lib/**에서 \"import 'dart:ffi'\"가 이 2개 파일에만 있다", () {
        const allowed = {'qpdf_ffi.dart', 'qpdf_isolate.dart'};
        final callers = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          if (file.readAsStringSync().contains("import 'dart:ffi'")) {
            callers.add(file.path.replaceAll('\\', '/'));
          }
        }
        final unexpected = callers
            .where((c) => !allowed.any(c.endsWith))
            .toList();
        expect(
          unexpected,
          isEmpty,
          reason: "dart:ffi import가 허용 목록 밖에서 발견됨: $unexpected",
        );
      });
    },
  );

  group(
    '§15 §5.7 검사15 : qpdf_isolate.dart는 pdfrx·이미지 인코딩 API를 쥐지 않는다(2-키 분리)',
    () {
      test("코드(주석 제외)에 'pdfrx', 'package:image', 'package:pdf/' 문자열이 0회다", () {
        final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
        for (final token in const ['pdfrx', 'package:image', 'package:pdf/']) {
          expect(
            codeOnly.contains(token),
            isFalse,
            reason: 'qpdf_isolate.dart가 금지 토큰 "$token"을 참조함',
          );
        }
      });
    },
  );

  group('§15 §5.7 검사16 : qpdf_isolate.dart의 잡 스펙에 금지 키가 없다(§5.3 화이트리스트)', () {
    test("코드(주석 제외)에 금지 키가 Map 키/값 리터럴로 등장하지 않는다", () {
      final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
      // 정확히 "Map 키 리터럴"(따옴표 직후 콜론) 형태만 검사한다 -- 단순 부분 문자열 검사는
      // qpdf-c.h의 정당한 API 식별자(qpdf_is_encrypted)·우리 자체 에러 코드('encrypted')·
      // 에러 텍스트 휴리스틱(text.contains('encrypt'))까지 오탐해 이 잡 자체를 구현 불가능하게
      // 만든다 -- inspect가 암호화 PDF를 판별하려면 "encrypt"라는 글자 자체는 불가피하게 코드에
      // 등장한다. 화이트리스트가 실제로 막아야 하는 것은 "이 단어를 job 스펙의 키로 쓰는 것"이다.
      final bannedKeyPattern = RegExp(
        r"""['"](replaceInput|splitPages|qdf|encrypt|linearize)['"]\s*:""",
      );
      final bannedValuePattern = RegExp(r"""[:]\s*['"]uncompress['"]""");
      expect(
        bannedKeyPattern.hasMatch(codeOnly),
        isFalse,
        reason:
            '금지 키가 Map 리터럴로 등장함: ${bannedKeyPattern.allMatches(codeOnly).map((m) => m.group(0)).toList()}',
      );
      expect(
        bannedValuePattern.hasMatch(codeOnly),
        isFalse,
        reason: 'streamData: uncompress 패턴 등장',
      );
    });
  });

  group('§15 §5.7 검사17 : lib/**에서 Process.run/Process.start를 쓰지 않는다', () {
    test("CLI 실행 경로(§2.1 (B) 기각안)가 부활하지 않았다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final source = file.readAsStringSync();
        if (source.contains('Process.run(') ||
            source.contains('Process.start(')) {
          violations.add(file.path.replaceAll('\\', '/'));
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Process.run/Process.start 호출 발견: $violations',
      );
    });
  });

  group(
    '§15 §5.7 검사18 : qpdf_isolate.dart가 노출하는 공개 함수는 임의 JSON/argv 문자열을 받지 않는다',
    () {
      test('공개 함수 시그니처에 String 타입의 잡스펙/JSON/argv 파라미터가 없다', () {
        final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
        // "jobSpec"/"jobJson"/"argv" 류 이름의 String 파라미터가 톱레벨(비-`_` 접두) 함수 시그니처에
        // 있는지 본다. 내부(`_` 접두) 헬퍼는 제외 -- 그건 공개 API가 아니다.
        final publicFnPattern = RegExp(
          r'^(Future<[^>]+>|Map<[^>]+>|String|void)\s+([a-zA-Z][a-zA-Z0-9]*)\s*\(',
          multiLine: true,
        );
        final suspiciousParamPattern = RegExp(
          r'String\??\s+(jobSpec|jobJson|argv)\w*',
          caseSensitive: false,
        );
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
          final openParenIndex =
              match.end - 1; // publicFnPattern 자체가 '\(' 로 끝나므로 그 위치.
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
          final signature = closeParenIndex == -1
              ? codeOnly.substring(start)
              : codeOnly.substring(start, closeParenIndex + 1);
          expect(
            suspiciousParamPattern.hasMatch(signature),
            isFalse,
            reason: '공개 함수 "$name"가 임의 JSON/argv 문자열을 받는 것으로 보임: $signature',
          );
        }
      });
    },
  );

  // ── §15 §6.4 "자동 검사 추가분"(검사 19~21) — pdf_compressor.dart(M-Q6) 경계 강제 ──────────
  group(
    '§15 §6.4 검사19 : pdf_compressor.dart ↔ pdf_engine.dart 상호 import가 0회다',
    () {
      test('pdf_compressor.dart가 pdf_engine.dart를 import하지 않는다', () {
        final source = _read('lib/pdf/pdf_compressor.dart');
        expect(
          source.contains("import 'pdf_engine.dart'"),
          isFalse,
          reason: 'pdf_compressor.dart가 pdf_engine.dart를 import함',
        );
      });
      test('pdf_engine.dart가 pdf_compressor.dart를 import하지 않는다', () {
        final source = _read('lib/pdf/pdf_engine.dart');
        expect(
          source.contains("import 'pdf_compressor.dart'"),
          isFalse,
          reason: 'pdf_engine.dart가 pdf_compressor.dart를 import함',
        );
      });
    },
  );

  group('§15 §6.4 검사20 : 저장 경로 프리셋 리터럴이 pdf_compressor.dart에 없다', () {
    test('pdf_compressor.dart에 2480/1754/1240/85/75/60 리터럴이 0회다', () {
      final presetLiterals = RegExp(r'\b(2480|1754|1240|85|75|60)\b');
      final codeOnly = _codeOnly(_read('lib/pdf/pdf_compressor.dart'));
      expect(
        presetLiterals.hasMatch(codeOnly),
        isFalse,
        reason: 'pdf_compressor.dart에 프리셋 리터럴 발견 -- ImagePdfBuilder 상수를 참조할 것',
      );
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
      expect(
        violations,
        isEmpty,
        reason:
            'SaveOp.compress 식별자 발견: $violations -- 압축 결과를 저장 경로로 우회시키는 유인이 된다(§6.3)',
      );
    });
  });

  // ── §31(`_workspace/31_architect_external_compress_l2.md`) §2.7 "신설 자동 검사"(검사22~25) ──
  // L2-ext(외부 PDF 임베디드 이미지 압축, M-E2~M-E5)가 §5.7 2-키 분리·절대 규칙2(래스터화 금지)·
  // §2.6 L2-app/L2-ext 상호 배타 경계를 코드 수준에서 유지하는지 검증한다. 이 4종 전부 실효성을
  // "위반 코드 주입 → 실패 확인 → 원복" 절차로 확인했다(`_workspace/33_pdf-core_l2ext_impl.md` 기록,
  // 이 파일 자체는 정상 상태만 담는다).
  group(
    '§31 §2.7 검사22 : qpdf_isolate.dart에 package:image/decodeJpg/encodeJpg가 0회다(검사15의 명시적 확장)',
    () {
      test("코드(주석 제외)에 'package:image', 'decodeJpg', 'encodeJpg' 문자열이 0회다", () {
        final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
        for (final token in const ['package:image', 'decodeJpg', 'encodeJpg']) {
          expect(
            codeOnly.contains(token),
            isFalse,
            reason:
                'qpdf_isolate.dart가 이미지 코덱 토큰 "$token"을 참조함 -- §5.7 2-키 분리 위반',
          );
        }
      });
    },
  );

  group('§31 §2.7 검사23 : qpdf_isolate.dart에 JPEG 마커 리터럴·픽셀 크기 계산이 0회다', () {
    test("코드(주석 제외)에 '0xFFD8', 'SOF' 문자열이 0회다(코덱 지식이 이 파일로 새는 첫 증상)", () {
      final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
      for (final token in const ['0xFFD8', 'SOF']) {
        expect(
          codeOnly.contains(token),
          isFalse,
          reason:
              'qpdf_isolate.dart에 JPEG 헤더 파싱 토큰 "$token" 발견 -- 픽셀 크기 계산은 image_pdf_builder.dart의 단일 소유다',
        );
      }
    });
  });

  group(
    '§31 §2.7 검사24 : imagePagePaths·embeddedImageStagingDir 동시 지정 시 런타임 거부 가드가 존재한다',
    () {
      test('pdf_compressor.dart의 compress()가 두 파라미터를 함께 검사하는 코드를 포함한다', () {
        final codeOnly = _codeOnly(_read('lib/pdf/pdf_compressor.dart'));
        // 두 식별자가 하나의 조건식(&&)으로 함께 등장하는지 -- 이 패턴이 사라지면 상호 배타 가드가
        // 삭제된 것이다. 실제 거부 동작 자체는 test/pdf/pdf_compressor_test.dart의 런타임 테스트가
        // 단언한다(이 검사는 그 가드가 소스에서 조용히 사라지는 것을 막는 정적 안전망이다).
        final guardPattern = RegExp(
          r'imagePagePaths\s*!=\s*null\s*&&\s*embeddedImageStagingDir\s*!=\s*null',
        );
        expect(
          guardPattern.hasMatch(codeOnly),
          isTrue,
          reason:
              'pdf_compressor.dart에서 imagePagePaths/embeddedImageStagingDir 상호 배타 가드를 찾지 못함(§2.6)',
        );
      });
    },
  );

  group(
    '§31 §2.7 검사25 : L2-ext 경로에 qpdf_oh_get_page_content_data가 없고, normalizeContent가 켜지지 않는다(절대 규칙2 봉쇄)',
    () {
      test(
        "qpdf_isolate.dart·pdf_compressor.dart 코드(주석 제외)에 콘텐츠 스트림 접근 API가 없다",
        () {
          // qpdf_oh_get_page_content_data는 실제 콘텐츠 스트림(텍스트·벡터·연산자)을 읽는 API다 --
          // L2-ext는 이미지 XObject 스트림만 다루므로 이 심볼이 등장할 이유가 없다(§2.5).
          for (final path in const [
            'lib/pdf/qpdf_isolate.dart',
            'lib/pdf/pdf_compressor.dart',
          ]) {
            final codeOnly = _codeOnly(_read(path));
            expect(
              codeOnly.contains('qpdf_oh_get_page_content_data'),
              isFalse,
              reason: '$path가 콘텐츠 스트림 접근 API를 참조함 -- 절대 규칙2(래스터화 금지) 봉쇄선 위반 소지',
            );
          }
        },
      );

      test("_commonWriteOptions의 normalizeContent 값이 켜지지 않는다('y' 리터럴이 없다)", () {
        // normalizeContent는 §5.2부터 이미 존재하는 정당한 L1 쓰기 옵션 키이며 항상 'n'(끔)으로
        // 고정돼 있다(qpdf_isolate.dart:45) -- 토큰 자체를 금지하면 그 기존 정당한 사용과 충돌한다.
        // 이 검사가 실제로 막아야 하는 것은 "L2-ext가 콘텐츠 정규화를 켜는 것"이므로 값이 'y'로
        // 바뀌는 것만 잡는다.
        final codeOnly = _codeOnly(_read('lib/pdf/qpdf_isolate.dart'));
        final enabledPattern = RegExp(
          r"""['"]normalizeContent['"]\s*:\s*['"]y['"]""",
        );
        expect(
          enabledPattern.hasMatch(codeOnly),
          isFalse,
          reason:
              'qpdf_isolate.dart가 normalizeContent를 켬(y) -- 콘텐츠 스트림 재작성은 절대 규칙2 위반',
        );
      });
    },
  );

  // ── §49(`_workspace/49_architect_split_merge_verdict_and_week3_final.md`) "기준 ② 중복 점검"
  // (179~210줄) — W3-R1 잔여 작업. T6(문서 36 §7.2)이 요구한 자동 검사 2종을 여기서 신설한다.
  // 검사②는 문서 49가 정정한 명세를 그대로 따른다: `.inspect(`는 읽기 전용 호출이라 예외다
  // (open_pdf_flow.dart:92, edit_screen.dart:90가 정당하게 이 메서드를 쓴다).
  group('§49 검사26(+R1 stamp_builder.dart 확장) : PdfPageRef 식별자가 없다(2-키 분리의 연장)', () {
    for (final path in pdfImageOwnerFiles) {
      test("$path -- 코드(주석 제외)에 'PdfPageRef' 문자열이 0회다", () {
        final codeOnly = _codeOnly(_read(path));
        expect(
          codeOnly.contains('PdfPageRef'),
          isFalse,
          reason: '$path가 qpdf의 PageRef 개념(PdfPageRef)을 참조함 -- 이 파일은 이를 몰라야 한다',
        );
      });
    }
  });

  group(
    '§49 검사27 : lib/features/**에서 PdfEngine의 save(/merge(/split( 호출이 0회다(.inspect(는 예외)',
    () {
      test(
        "'engine' 계열 수신자의 .save(/.merge(/.split( 호출이 없다 -- 화면이 저장 파이프라인을 직접 조립하지 못한다",
        () {
          // PdfEngine 타입 변수는 현재 코드베이스 전체에서 `engine`이라는 이름으로만 쓰인다(전수
          // grep 확인: lib/features/viewer/open_pdf_flow.dart:92 `required PdfEngine engine`). 수신자
          // 이름에 'engine'을 포함하는 호출로 좁혀 무관한 .save(/.merge(/.split( 호출(다른 클래스의
          // 동명 메서드)을 오탐하지 않는다. `.inspect(`는 검사 대상에서 아예 제외한다(문서 49 정정).
          final violationPattern = RegExp(
            r'\b\w*[Ee]ngine\w*\.(save|merge|split)\(',
          );
          final violations = <String>[];
          for (final file in _dartFilesUnder('lib/features')) {
            final codeOnly = _codeOnly(file.readAsStringSync());
            if (violationPattern.hasMatch(codeOnly)) {
              violations.add(file.path.replaceAll('\\', '/'));
            }
          }
          expect(
            violations,
            isEmpty,
            reason:
                'lib/features/**에서 PdfEngine의 save/merge/split 직접 호출 발견: $violations -- 저장 파이프라인은 화면에서 조립하지 않는다(inspect만 허용)',
          );
        },
      );
    },
  );

  // ── §52(`_workspace/52_architect_week4_design.md`) §4.3 "자동 검사"(검사28~30) — 4주차
  // 광고·인앱결제 단일 게이트 계약(§4.1)을 고정하는 회귀 방지 검사. 문서 60(R3 중간 판정)의
  // 소스 전수 실사가 이미 준수 상태를 확인했으므로, 그 상태를 여기서 고정한다.
  group(
    '§52 검사28 : adsRemoved 판단 로직은 lib/ads/ad_gate.dart 등 지정 파일 밖에 있으면 안 된다(단일 게이트)',
    () {
      test(
        "'adsRemoved' 식별자가 허용 목록(lib/ads/**·lib/billing/**·settings_screen.dart·데이터 계층) 밖에 없다",
        () {
          // 데이터 계층(Drift 컬럼/생성 코드/설정 리포지토리)은 판단 로직이 아니라 컬럼·필드
          // 정의이므로 예외다(문서 60 §4 F-5 인접 지적, 문서 56 §3.3이 먼저 제기) — 여기서 판단
          // 로직과 데이터 계층을 구분하지 않으면 tables.dart/app_database.g.dart(drift 생성 코드)/
          // settings_repository.dart의 정당한 컬럼 정의까지 위반으로 오탐한다(실측: 3파일 모두
          // 코드 레벨에서 'adsRemoved'를 갖고 있다).
          const allowedDataLayerFiles = {
            'lib/data/db/tables.dart',
            'lib/data/db/app_database.g.dart',
            'lib/data/repository/settings_repository.dart',
          };
          final violations = <String>[];
          for (final file in _dartFilesUnder('lib')) {
            final normalized = file.path.replaceAll('\\', '/');
            if (normalized.contains('lib/ads/')) continue;
            if (normalized.contains('lib/billing/')) continue;
            if (normalized.endsWith(
              'lib/features/settings/settings_screen.dart',
            ))
              continue;
            if (allowedDataLayerFiles.any(normalized.endsWith)) continue;
            // main.dart는 §3.6 부팅 게이트(구매 시 MobileAds.instance.initialize()조차 호출하지
            // 않는다, §4.2)를 위해 부팅 1회만 adsRemoved를 읽는다 -- 화면 코드가 아니라 부팅
            // 배선이므로 단일 게이트 원칙의 예외로 명시한다(§3.6-2).
            if (normalized.endsWith('lib/main.dart')) continue;
            final codeOnly = _codeOnly(file.readAsStringSync());
            if (codeOnly.contains('adsRemoved')) {
              violations.add(normalized);
            }
          }
          expect(
            violations,
            isEmpty,
            reason:
                '허용 목록 밖에서 adsRemoved 식별자 발견: $violations -- 광고 판단은 ad_gate.dart 하나로 끝나야 한다(§4.1)',
          );
        },
      );
    },
  );

  group(
    '§52 검사29 : 배너 위젯(AdWidget/BannerAd/AdSize)은 lib/ads/** 밖에서 쓰지 않는다(단일 구현)',
    () {
      test("'AdWidget'/'BannerAd'/'AdSize' 식별자가 lib/ads/** 밖에 없다", () {
        final violations = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final normalized = file.path.replaceAll('\\', '/');
          if (normalized.contains('lib/ads/')) continue;
          final codeOnly = _codeOnly(file.readAsStringSync());
          for (final token in const ['AdWidget', 'BannerAd', 'AdSize']) {
            if (codeOnly.contains(token)) {
              violations.add('$normalized ($token)');
            }
          }
        }
        expect(
          violations,
          isEmpty,
          reason:
              'lib/ads/** 밖에서 배너 관련 식별자 발견: $violations -- 배너 배치의 단일 소유는 banner_host.dart다(§1.0)',
        );
      });
    },
  );

  group('§52 검사30 : 전면광고 실제 노출은 앱 페이지 전환 한 곳에서만 이뤄진다', () {
    test('페이지 전환 소비 호출부가 app.dart 밖에 없다', () {
      const allowed = {'lib/app/app.dart'};
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        // ad_gate.dart(showIfEligible의 유일한 구현부)·interstitial_controller.dart(정의부)는
        // 노출 "호출"이 아니라 정의/내부 위임이므로 대상에서 제외한다.
        if (normalized.contains('lib/ads/')) continue;
        final codeOnly = _codeOnly(file.readAsStringSync());
        final hasCall = codeOnly.contains('consumePendingOnPageTransition(');
        if (!hasCall) continue;
        if (allowed.contains(normalized)) continue;
        violations.add(normalized);
      }
      expect(
        violations,
        isEmpty,
        reason: 'app.dart 밖에서 전면광고 전환 소비 호출 발견: $violations',
      );
    });

    test('작업 흐름은 광고 대기만 등록하고 직접 표시하지 않는다', () {
      const taskFlows = {
        'lib/features/edit/save_dialog.dart',
        'lib/features/viewer/compress_sheet.dart',
        'lib/features/common/share_flow.dart',
      };
      for (final path in taskFlows) {
        final codeOnly = _codeOnly(_read(path));
        expect(
          codeOnly.contains('registerCompletedTask('),
          isTrue,
          reason: '$path에 광고 대기 등록이 없다',
        );
        expect(
          codeOnly.contains('showIfEligible('),
          isFalse,
          reason: '$path가 전면광고를 직접 표시한다',
        );
      }
    });
  });

  // ── 68_architect_windows_port_design.md §5.4 검사31~33(W4, pdf-core 담당) ──

  group(
    '§68 검사31 : Platform.isWindows/Platform.isAndroid 식별자는 화이트리스트 밖에서 0회다',
    () {
      test("'Platform.isWindows'/'Platform.isAndroid' 식별자가 화이트리스트 밖에 없다", () {
        // 화이트리스트 근거(설계 §4.3·§5.4 + 전수 grep 재확인):
        //  - lib/core/platform_features.dart : AppFeatures 단일 소유자, 이 식별자의 정의처
        //  - lib/data/storage/workspace.dart : 저장 루트 계산은 "경로 계산의 소유자가
        //    판단한다"는 기존 원칙(§2.9)을 지키기 위한 의도된 예외(§3.1) — AppFeatures가
        //    아니라 이 파일이 Platform.isWindows를 직접 읽는다
        //  - lib/pdf/qpdf_isolate.dart : qpdf 네이티브 라이브러리 경로의 단일 소유자(§2.5)
        //  - lib/features/scan/local_document_scan_source.dart : doclens 스캔 지원 여부를
        //    이미 Platform.isAndroid로 판정하던 기존 코드(포팅 이전부터 존재, §3.7)
        //  - lib/billing/billing_service.dart : `:237`·`:303`이 이미 Platform.isAndroid를
        //    쓰고 있었다(Play 전용 offerToken 처리·구독 동기화) — 이번 포팅이 추가한 것이
        //    아니라 포팅 이전부터 존재하던 사용이므로 기존 코드를 건드리지 않기 위해
        //    화이트리스트에 등재한다(설계 §5.4 각주)
        //  - lib/app/providers.dart : [화이트리스트 확장 · 설계 문서 작성 이후 실제 코드로
        //    확인] publicPdfExporterProvider/publicImageExporterProvider(§3.4)가 MediaStore
        //    유무라는 "플랫폼 능력"에 따라 구현체를 갈아끼우는 지점이다. AppFeatures(기능
        //    on/off) 문제가 아니라 workspace.dart와 같은 유형의 "그 provider를 소유한
        //    파일이 직접 판단"하는 예외이며, 실제로 이 provider 정의 자체가 유일한 판단
        //    지점이라 여기서 널리 퍼진 판단이 재발하지 않는다. 설계 문서 §5.4 표에는 없었으나
        //    전수 grep 결과 실제 코드가 이렇게 배선돼 있어 화이트리스트를 넓혔다.
        const allowed = {
          'lib/core/platform_features.dart',
          'lib/data/storage/workspace.dart',
          'lib/pdf/qpdf_isolate.dart',
          'lib/features/scan/local_document_scan_source.dart',
          'lib/billing/billing_service.dart',
          'lib/app/providers.dart',
        };
        final violations = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final normalized = file.path.replaceAll('\\', '/');
          if (allowed.any(normalized.endsWith)) continue;
          final codeOnly = _codeOnly(file.readAsStringSync());
          for (final token in const ['Platform.isWindows', 'Platform.isAndroid']) {
            if (codeOnly.contains(token)) {
              violations.add('$normalized ($token)');
            }
          }
        }
        expect(
          violations,
          isEmpty,
          reason:
              '화이트리스트 밖에서 Platform.isWindows/Platform.isAndroid 발견: $violations -- 플랫폼 기능 가용성 판단은 AppFeatures(platform_features.dart) 하나로 끝나야 한다(68 §4.3)',
        );
      });
    },
  );

  group('§68 검사32 : AppFeatures.ads 식별자는 lib/ads/**와 lib/main.dart 밖에서 0회다', () {
    test("'AppFeatures.ads' 식별자가 화이트리스트 밖에 없다", () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        final normalized = file.path.replaceAll('\\', '/');
        if (normalized.contains('lib/ads/')) continue;
        if (normalized.endsWith('lib/main.dart')) continue;
        final codeOnly = _codeOnly(file.readAsStringSync());
        if (codeOnly.contains('AppFeatures.ads')) {
          violations.add(normalized);
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'lib/ads/**, lib/main.dart 밖에서 AppFeatures.ads 발견: $violations -- 광고 단일 게이트의 연장(검사28과 같은 취지, 68 §5.4)',
      );
    });
  });

  group(
    '§68 검사33 : test/native/qpdf30.dll과 native/qpdf/windows-x64/qpdf30.dll의 SHA-256이 동일하다',
    () {
      test('두 DLL의 SHA-256 해시가 일치한다', () {
        final testDll = File('test/native/qpdf30.dll');
        final deployDll = File('native/qpdf/windows-x64/qpdf30.dll');
        expect(
          testDll.existsSync(),
          isTrue,
          reason: 'test/native/qpdf30.dll이 없다',
        );
        expect(
          deployDll.existsSync(),
          isTrue,
          reason: 'native/qpdf/windows-x64/qpdf30.dll이 없다',
        );
        final testHash = sha256.convert(testDll.readAsBytesSync()).toString();
        final deployHash = sha256.convert(deployDll.readAsBytesSync()).toString();
        expect(
          deployHash,
          equals(testHash),
          reason:
              '테스트용/배포용 qpdf30.dll의 SHA-256이 다르다(68 §2.4) -- 두 파일은 항상 동일한 바이너리여야 한다',
        );
      });
    },
  );

  // ── `79_architect_v1.1_v2_design.md` §2.4(R1 개정) "검사 개정안"(신설 검사34·검사35) ──
  group(
    '§2.4 검사34(R1) : PdfTextRenderingMode는 stamp_builder.dart 단 한 파일에만 존재한다',
    () {
      test("'PdfTextRenderingMode' 식별자가 lib/pdf/stamp_builder.dart 밖에 없다", () {
        final violations = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final normalized = file.path.replaceAll('\\', '/');
          if (normalized.endsWith('lib/pdf/stamp_builder.dart')) continue;
          if (file.readAsStringSync().contains('PdfTextRenderingMode')) {
            violations.add(normalized);
          }
        }
        expect(
          violations,
          isEmpty,
          reason: 'lib/pdf/stamp_builder.dart 밖에서 PdfTextRenderingMode 발견: $violations',
        );
      });

      test("'MemoryImage(' 식별자가 lib/pdf/** 밖에 없다", () {
        final violations = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final normalized = file.path.replaceAll('\\', '/');
          if (normalized.contains('lib/pdf/')) continue;
          if (file.readAsStringSync().contains('MemoryImage(')) {
            violations.add(normalized);
          }
        }
        expect(
          violations,
          isEmpty,
          reason: 'lib/pdf/** 밖에서 MemoryImage( 발견: $violations',
        );
      });

      test("'PdfBlendMode' 식별자가 lib/pdf/** 밖에 없다", () {
        final violations = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final normalized = file.path.replaceAll('\\', '/');
          if (normalized.contains('lib/pdf/')) continue;
          if (file.readAsStringSync().contains('PdfBlendMode')) {
            violations.add(normalized);
          }
        }
        expect(
          violations,
          isEmpty,
          reason: 'lib/pdf/** 밖에서 PdfBlendMode 발견: $violations',
        );
      });
    },
  );

  group(
    '§2.4 검사35(R1) : StampBuilder.build( 호출부는 lib/pdf/** 안에만 있다(화면이 직접 스탬프를 만들지 않는다)',
    () {
      test('lib/pdf/** 밖에서 StampBuilder.build( 를 호출하지 않는다', () {
        final violations = <String>[];
        for (final file in _dartFilesUnder('lib')) {
          final normalized = file.path.replaceAll('\\', '/');
          if (normalized.contains('lib/pdf/')) continue;
          if (file.readAsStringSync().contains('StampBuilder.build(')) {
            violations.add(normalized);
          }
        }
        expect(
          violations,
          isEmpty,
          reason: 'lib/pdf/** 밖에서 StampBuilder.build( 호출: $violations -- 스탬프 조립은 엔진 내부의 책임이다',
        );
      });
    },
  );

  // ── `79_architect_v1.1_v2_design.md` §7.6.3 "신설 검사39" — OCR 오프라인 강제(절대 규칙 1).
  // 대상은 정확히 android/app/build.gradle.kts · pubspec.yaml 이 두 파일뿐이다. android/ 전체나
  // third_party/doclens/**는 대상이 아니다(§7.6.2 판단 — doclens의 기존
  // play-services-mlkit-text-recognition:19.0.1은 이번 라운드 범위 밖).
  group('§7.6.3 검사39 : OCR 한국어 모델 번들 강제(절대 규칙 1)', () {
    test('검사39-a : build.gradle.kts에 text-recognition-korean 번들 좌표가 1건 이상이다', () {
      final source = _read('android/app/build.gradle.kts');
      final matches = 'com.google.mlkit:text-recognition-korean'
          .allMatches(source)
          .length;
      expect(
        matches,
        greaterThanOrEqualTo(1),
        reason:
            'android/app/build.gradle.kts에 com.google.mlkit:text-recognition-korean 번들 좌표가 없다'
            ' -- 이 줄이 없으면 한국어 인식이 런타임에 실패한다(§7.6.1)',
      );
    });

    test('검사39-b : build.gradle.kts에 다운로드 변형(play-services-mlkit-text-recognition)이 0건이다', () {
      final source = _read('android/app/build.gradle.kts');
      expect(
        source.contains('play-services-mlkit-text-recognition'),
        isFalse,
        reason:
            'android/app/build.gradle.kts가 play-services-mlkit-text-recognition(다운로드 변형)을 끌어옴'
            ' -- 런타임에 모델을 내려받아 절대 규칙 1을 위반한다',
      );
    });

    test('검사39-c : pubspec.yaml의 google_mlkit* 의존성이 google_mlkit_text_recognition 하나뿐이다', () {
      final source = _read('pubspec.yaml');
      final matches = RegExp(
        r'^\s{2}(google_mlkit\w*):',
        multiLine: true,
      ).allMatches(source).map((m) => m.group(1)!).toSet();
      expect(
        matches,
        equals({'google_mlkit_text_recognition'}),
        reason:
            'pubspec.yaml의 google_mlkit* 의존성이 하나가 아니다(실측: $matches)'
            ' -- google_mlkit_document_scanner 등 과거 제거된 플러그인의 부활을 막는 검사다',
      );
    });
  });

  // T15(개정, §9) : OcrSource 격리 + 오프라인 강제. ①만으로는 규칙 1을 검증하지 못하므로(가드언
  // C2) 위 검사39와 짝을 이룬다.
  group('T15(개정) : OcrSource 격리 — google_mlkit 플러그인 import가 ocr_source.dart 1파일뿐이다', () {
    test("lib/** 전체에서 'package:google_mlkit' import가 lib/pdf/ocr_source.dart에만 있다", () {
      final callers = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (file.readAsStringSync().contains('package:google_mlkit')) {
          callers.add(file.path.replaceAll('\\', '/'));
        }
      }
      expect(
        callers,
        equals(['lib/pdf/ocr_source.dart']),
        reason: 'google_mlkit 플러그인 import가 예상 밖에서 발견됨(실측: $callers)'
            ' -- 플러그인 타입 격리는 ocr_source.dart 하나로 끝나야 한다',
      );
    });
  });
}
