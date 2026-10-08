import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _mapKey = RegExp(r"^\s*'((?:[^'\\]|\\.)*)'\s*:", multiLine: true);
final _appTextKey = RegExp(r"app(?:Text|Count)\(\s*\w+\s*,\s*'((?:[^'\\\n]|\\.)*)'");
final _koreanLiteral = RegExp(
  r"'((?:[^'\\\n]|\\.)*[가-힣](?:[^'\\\n]|\\.)*)'",
);

String _read(String path) => File(path).readAsStringSync();

void main() {
  const mapFiles = [
    'lib/app/app_locale.dart',
    'lib/app/locale_scan_edit.dart',
    'lib/app/locale_viewer_documents.dart',
  ];

  final keys = <String>{};
  final duplicates = <String>[];
  for (final f in mapFiles) {
    for (final m in _mapKey.allMatches(_read(f))) {
      if (!keys.add(m.group(1)!)) duplicates.add(m.group(1)!);
    }
  }

  test('no key is defined in more than one English map', () {
    expect(duplicates, isEmpty);
  });

  test('singular map keys exist in plural maps and keep {count}', () {
    final singular = <String>[];
    for (final m in _mapKey.allMatches(_read('lib/app/locale_singular.dart'))) {
      singular.add(m.group(1)!);
    }
    expect(singular, isNotEmpty);
    expect(singular.toSet().length, singular.length);
    for (final k in singular) {
      expect(keys.contains(k), isTrue, reason: 'no plural entry for $k');
      expect(k.contains('{count}'), isTrue, reason: 'no {count} in $k');
    }
  });

  test('every appCount key has a singular entry', () {
    final singular = _mapKey
        .allMatches(_read('lib/app/locale_singular.dart'))
        .map((m) => m.group(1)!)
        .toSet();
    final countKey = RegExp(r"appCount\(\s*\w+\s*,\s*'((?:[^'\\\n]|\\.)*)'");
    final missing = <String>[];
    // '{count}개 선택' reads the same in singular form.
    const sameForm = {'{count}개 선택'};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m in countKey.allMatches(f.readAsStringSync())) {
        final k = m.group(1)!;
        if (!singular.contains(k) && !sameForm.contains(k)) missing.add(k);
      }
    }
    expect(missing, isEmpty);
  });

  test('every literal appText key has an English translation', () {
    final missing = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !mapFiles.any((m) => f.path.replaceAll(r'\', '/') == m));
    for (final f in files) {
      for (final m in _appTextKey.allMatches(f.readAsStringSync())) {
        if (!keys.contains(m.group(1))) missing.add('${f.path}: ${m.group(1)}');
      }
    }
    expect(missing, isEmpty);
  });

  test('Korean literals in feature screens are translated keys or non-UI', () {
    const allowed = {
      r'약 ${mb}MB가 더 필요합니다', // template handled in failure_ui.dart
      '저장 실패', // developer.log only
    };
    final missing = <String>[];
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        final code = line.split(' // ').first;
        if (code.trimLeft().startsWith('//')) continue;
        if (code.contains('developer.log') ||
            code.contains('StateError') ||
            code.contains('debugPrint') ||
            code.contains('assert(')) {
          continue;
        }
        for (final m in _koreanLiteral.allMatches(code)) {
          final s = m.group(1)!;
          if (!keys.contains(s) &&
              !allowed.contains(s) &&
              !s.startsWith('ViewerScreen:')) {
            missing.add('${f.path}: $s');
          }
        }
      }
    }
    expect(missing, isEmpty);
  });
}
