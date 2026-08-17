// 래스터화 구조적 봉쇄 자동 검사(§3.4). 소스 텍스트를 읽어 금지 패턴을 찾는다 — 빌드 불필요.
//
// 이 테스트는 "통과"가 목적이 아니라 "위반을 실제로 잡는지"가 목적이다. 규칙을 어기는 코드가
// 들어오면 반드시 여기서 실패해야 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _rasterCoreFiles = [
  'lib/pdf/pdf_engine.dart',
  'lib/pdf/pdf_engine_isolate.dart',
  'lib/pdf/image_pdf_builder.dart',
];

String _read(String relativePath) => File(relativePath).readAsStringSync();

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

void main() {
  group('§3.4-1 : 저장 경로 파일이 렌더러·flutter/dart:ui를 import하지 않는다', () {
    for (final path in _rasterCoreFiles) {
      test('$path에 금지 import 문자열이 없다', () {
        final source = _read(path);
        expect(source.contains("import 'package:flutter/"), isFalse, reason: '$path: flutter SDK import 금지');
        expect(source.contains("import 'dart:ui'"), isFalse, reason: '$path: dart:ui import 금지');
        expect(source.contains('pdf_renderer.dart'), isFalse, reason: '$path: pdf_renderer.dart import 금지');
      });
    }
  });

  group('§3.4-2 : 저장 경로 파일에 래스터화 관련 식별자가 없다', () {
    final forbidden = RegExp(r'\b(render|toImage|toByteData|Canvas|PictureRecorder)\b');
    for (final path in _rasterCoreFiles) {
      test('$path에 render/toImage/toByteData/Canvas/PictureRecorder가 없다', () {
        final source = _read(path);
        final matches = forbidden.allMatches(source).map((m) => m.group(0)).toList();
        expect(matches, isEmpty, reason: '$path 위반: $matches');
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
        final source = file.readAsStringSync();
        if (source.contains('AdWidget(')) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: 'banner_host.dart 밖에서 AdWidget 생성: $violations');
    });
  });

  group('§3.4-5 : PdfEngine 인터페이스에 incremental 식별자가 없다', () {
    test("'incremental' 이 코드(주석 제외)에 없다", () {
      final source = _read('lib/pdf/pdf_engine.dart');
      final codeOnly = source
          .split('\n')
          .where((line) => !line.trim().startsWith('///') && !line.trim().startsWith('//'))
          .join('\n');
      expect(RegExp(r'\bincremental\b').hasMatch(codeOnly), isFalse, reason: 'pdf_engine.dart 코드에 incremental 식별자 존재');
    });
  });
}
