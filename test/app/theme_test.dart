import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/app/theme.dart';

void main() {
  test('AppTheme.light()는 유효한 라이트 ThemeData를 반환한다', () {
    final theme = AppTheme.light();
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
  });

  test('AppTheme.dark()는 유효한 다크 ThemeData를 반환한다', () {
    final theme = AppTheme.dark();
    expect(theme.brightness, Brightness.dark);
    expect(theme.useMaterial3, isTrue);
  });

  test('라이트·다크는 같은 시드에서 파생되지만 서피스 색이 다르다', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.colorScheme.surface, isNot(equals(dark.colorScheme.surface)));
  });
}
