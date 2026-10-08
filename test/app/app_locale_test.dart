import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/app/app_locale.dart';

void main() {
  testWidgets('Korean locale also localizes Flutter controls', (tester) async {
    late MaterialLocalizations materialLabels;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: appLocalizationDelegates,
        home: Builder(
          builder: (context) {
            materialLabels = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(materialLabels.cancelButtonLabel, '취소');
  });

  test('manual language overrides Play country', () {
    expect(
      resolveAppLocale(
        choice: LanguageChoice.english,
        playCountry: 'KR',
        deviceLocale: const Locale('ko', 'KR'),
      ).languageCode,
      'en',
    );
  });

  test('automatic language follows Play country', () {
    expect(
      resolveAppLocale(
        choice: LanguageChoice.automatic,
        playCountry: 'KR',
        deviceLocale: const Locale('en', 'US'),
      ).languageCode,
      'ko',
    );
    expect(
      resolveAppLocale(
        choice: LanguageChoice.automatic,
        playCountry: 'US',
        deviceLocale: const Locale('ko', 'KR'),
      ).languageCode,
      'en',
    );
  });

  test('device locale is used when Play country is unavailable', () {
    expect(
      resolveAppLocale(
        choice: LanguageChoice.automatic,
        playCountry: null,
        deviceLocale: const Locale('ko', 'KR'),
      ).languageCode,
      'ko',
    );
  });
}
