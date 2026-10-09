import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_viewer_documents.dart';
import 'locale_scan_edit.dart';
import 'locale_singular.dart';
import '../core/platform_features.dart';

enum LanguageChoice { automatic, korean, english }

const _languageKey = 'app_language_choice';

final languageChoiceProvider =
    StateNotifierProvider<LanguageController, LanguageChoice>(
      (ref) => LanguageController()..load(),
    );

class LanguageController extends StateNotifier<LanguageChoice> {
  LanguageController() : super(LanguageChoice.automatic);

  bool _chosenThisSession = false;

  Future<void> load() async {
    String? saved;
    try {
      saved = await SharedPreferencesAsync().getString(_languageKey);
    } catch (_) {
      return;
    }
    if (!mounted || _chosenThisSession) return;
    state = LanguageChoice.values.firstWhere(
      (choice) => choice.name == saved,
      orElse: () => LanguageChoice.automatic,
    );
  }

  Future<void> select(LanguageChoice choice) async {
    _chosenThisSession = true;
    state = choice;
    await SharedPreferencesAsync().setString(_languageKey, choice.name);
  }
}

final playCountryProvider = FutureProvider<String?>((ref) async {
  if (!AppFeatures.billing) return null;
  try {
    return await InAppPurchase.instance.countryCode();
  } catch (_) {
    return null;
  }
});

Locale resolveAppLocale({
  required LanguageChoice choice,
  required String? playCountry,
  required Locale deviceLocale,
}) {
  if (choice == LanguageChoice.korean) return const Locale('ko');
  if (choice == LanguageChoice.english) return const Locale('en');
  if (playCountry != null && playCountry.isNotEmpty) {
    return Locale(playCountry.toUpperCase() == 'KR' ? 'ko' : 'en');
  }
  return Locale(
    deviceLocale.countryCode?.toUpperCase() == 'KR' ||
            deviceLocale.languageCode == 'ko'
        ? 'ko'
        : 'en',
  );
}

final appLocaleProvider = Provider<Locale>((ref) {
  final choice = ref.watch(languageChoiceProvider);
  final country = ref.watch(playCountryProvider).valueOrNull;
  return resolveAppLocale(
    choice: choice,
    playCountry: country,
    deviceLocale: ui.PlatformDispatcher.instance.locale,
  );
});

/// Flutter SDK translations for Material, Cupertino and Widgets controls.
const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// App-owned strings are keyed by their existing Korean copy.
String appText(BuildContext context, String korean) {
  if (Localizations.localeOf(context).languageCode == 'ko') return korean;
  return _english[korean] ??
      viewerDocumentsEnglish[korean] ??
      scanEditEnglish[korean] ??
      korean;
}

/// Count-bearing copy. Korean is unchanged; English uses the singular form
/// from [englishSingular] when n == 1 and falls back to the plural entry.
String appCount(BuildContext context, String korean, int n) {
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  final template = (!isKorean && n == 1)
      ? (englishSingular[korean] ?? appText(context, korean))
      : appText(context, korean);
  return template.replaceAll('{count}', '$n');
}

const _english = <String, String>{
  'PDF 대리': 'PDF Daeri',
  '{count}쪽': '{count} pages',
  '편집하던 문서가 있습니다': 'You have an unfinished document',
  '버전 정보를 확인할 수 없습니다': 'Version information is unavailable',
  '버전 정보를 확인하는 중입니다': 'Checking version information',
  '버전': 'Version',
  '오픈소스 라이선스': 'Open source licenses',
  '이 앱은 오픈소스 소프트웨어를 사용합니다. 각 항목을 눌러 전문을 확인하세요.':
      'This app uses open source software. Tap an item to read its full license.',
  '이 기기에서는 구독을 사용할 수 없습니다': 'Subscriptions are unavailable on this device',
  '지금 구독할 수 없습니다': 'Subscriptions are unavailable right now',
  '현재 이용할 수 없습니다': 'Currently unavailable',
  '구독 관리': 'Manage subscription',
  'Google Play에서 갱신 또는 취소할 수 있습니다': 'Renew or cancel in Google Play',
  '관리': 'Manage',
  'Google Play 구독 관리 페이지를 열 수 없습니다': 'Could not open Google Play subscriptions',
  'App Store에서 갱신 또는 취소할 수 있습니다': 'Renew or cancel in the App Store',
  'App Store 구독 관리 페이지를 열 수 없습니다': 'Could not open App Store subscriptions',
  'App Store의 활성 구독을 다시 확인합니다':
      'Check your active App Store subscription again',
  '구독 안내': 'Subscription info',
  '구독은 App Store 계정으로 결제되며, 현재 기간이 끝나기 최소 24시간 전에 해지하지 않으면 자동으로 갱신됩니다. 구매 후 설정에서 관리하거나 해지할 수 있습니다.':
      'Payment is charged to your App Store account. The subscription renews automatically unless canceled at least 24 hours before the end of the current period. You can manage or cancel it in your account settings after purchase.',
  '이용 약관': 'Terms of Use',
  '이용 약관을 열 수 없습니다': 'Could not open the Terms of Use',
  '구독 상태 갱신': 'Refresh subscription status',
  'Google Play의 활성 구독을 다시 확인합니다':
      'Check your active Google Play subscription again',
  '갱신': 'Refresh',
  '자동 갱신': 'Auto-renews',
  '년': 'year',
  '기본 저장 화질': 'Default save quality',
  '지금 사용할 수 없습니다': 'Unavailable right now',
  '고화질': 'High quality',
  '기본': 'Standard',
  '최소': 'Minimum',
  '화면 테마': 'Theme',
  '라이트': 'Light',
  '다크': 'Dark',
  '시스템 기본': 'System default',
  '저장 공간': 'Storage',
  '계산 중…': 'Calculating…',
  '사용 중': 'Used',
  '캐시를 비웠습니다': 'Cache cleared',
  '최근 파일 전체 정리': 'Clear recent files',
  '원본 파일은 지워지지 않습니다': 'Original files will not be deleted',
  '정리': 'Clear',
  '최근 연 파일을 정리했습니다': 'Recent files cleared',
  '최근 연 파일': 'Recently opened files',
  '{total}개 중 {used}개': '{used} of {total}',
  '캐시': 'Cache',
  '합계': 'Total',
  '캐시 비우기': 'Clear cache',
  '홈페이지': 'Website',
  'PDF 대리 홈페이지를 엽니다': 'Open the PDF Daeri website',
  '홈페이지를 열 수 없습니다': 'Could not open the website',
  '개인정보처리방침': 'Privacy policy',
  '수집·이용 정보를 확인합니다': 'Review how information is collected and used',
  '개인정보처리방침을 열 수 없습니다': 'Could not open the privacy policy',
  '칭찬하기': 'Rate the app',
  'Google Play에서 별점과 리뷰를 남겨 주세요': 'Leave a rating and review on Google Play',
  'Google Play 리뷰 페이지를 열 수 없습니다': 'Could not open the Google Play review page',
  '설정': 'Settings',
  '언어': 'Language',
  '자동': 'Automatic',
  '한국어': 'Korean',
  '영어': 'English',
  '확인': 'OK',
  '취소': 'Cancel',
  '삭제': 'Delete',
  '저장': 'Save',
  '열기': 'Open',
  '닫기': 'Close',
  '완료': 'Done',
  '다음': 'Next',
  '뒤로': 'Back',
  '종료': 'Exit',
  '앱을 종료할까요?': 'Exit the app?',
  '진행 중인 작업이 없으면 앱을 종료합니다.': 'The app will close if no task is in progress.',
  '작업 시작': 'Get started',
  '스캔': 'Scan',
  'PDF 열기': 'Open PDF',
  '사진 → PDF': 'Photos to PDF',
  '내 문서': 'My documents',
  '변환': 'Convert',
  '보기': 'View',
  '최근 문서': 'Recent documents',
  '전체 보기': 'View all',
  '이어서 편집': 'Continue editing',
  '업데이트가 있습니다': 'Update available',
  '더 안정적인 최신 버전이 있습니다. 지금 업데이트할까요?':
      'A newer, more stable version is available. Update now?',
  '나중에': 'Later',
  '업데이트': 'Update',
  '텍스트 인식 구독': 'OCR subscription',
  'OCR로 글자를 검색·선택·복사하고 광고도 제거할 수 있습니다.':
      'Create PDFs with selectable, searchable text using OCR, and remove ads.',
  '구독하기': 'Subscribe',
  '구독 상태를 확인 중입니다. 잠시 후 다시 시도해 주세요.':
      'Checking your subscription. Please try again shortly.',
  '지금은 연간 구독 상품을 불러올 수 없습니다.':
      'The annual subscription is unavailable right now.',
  '구독이 필요합니다': 'Subscription required',
  '텍스트 인식은 활성 구독이 필요합니다.':
      'An active subscription is required to create OCR PDFs.',
  '광고 제거 + OCR': 'Remove ads + OCR',
  '연간 광고 제거 + OCR': 'Annual ad removal + OCR',
  '구독 중 · 광고 없이 OCR PDF를 만들 수 있습니다': 'Subscribed · Create OCR PDFs without ads',
  '구독 혜택이 적용되었습니다': 'Subscription benefits are active',
  '구독 확인 서버에 연결하지 못했습니다. 기존 구독 혜택은 유지됩니다.':
      'Could not contact the subscription server. Existing benefits remain active.',
  '불러오는 중…': 'Loading…',
  '처리 중…': 'Processing…',
  '구독': 'Subscribe',
  '활성 구독을 확인했습니다': 'Active subscription confirmed',
  '활성 구독이 없습니다': 'No active subscription found',
  '암호로 보호된 문서': 'Password-protected document',
  '열 수 없는 파일': 'Cannot open file',
  '파일을 찾을 수 없음': 'File not found',
  '파일에 접근할 수 없음': 'Cannot access file',
  '저장 공간 부족': 'Not enough storage',
  '저장 중단': 'Save stopped',
  '지원하지 않는 파일': 'Unsupported file',
  '스캐너를 사용할 수 없음': 'Scanner unavailable',
  '처리하지 못했습니다': 'Could not complete the operation',
  '비밀번호를 입력하세요': 'Enter the password',
  '파일이 손상되어 열 수 없습니다': 'This file is damaged and cannot be opened',
  '파일이 더 이상 없습니다': 'The file is no longer available',
  '보낸 앱에서 다시 열어 주세요': 'Open it again from the sending app',
  '페이지를 지웠는데 용량이 줄지 않아 저장을 중단했습니다':
      'Saving stopped because removing pages did not reduce the file size',
  '순서·회전만 바꿨는데 용량이 늘어 저장을 중단했습니다':
      'Saving stopped because reordering or rotating increased the file size',
  '발췌 결과가 예상보다 커서 저장을 중단했습니다':
      'Saving stopped because the extracted file was larger than expected',
  '합친 결과가 원본 합계보다 커서 저장을 중단했습니다':
      'Saving stopped because the merged file was larger than the combined originals',
  '페이지를 추가한 결과가 예상보다 커서 저장을 중단했습니다':
      'Saving stopped because the file with added pages was larger than expected',
  '얹은 내용이 예상보다 커서 저장을 중단했습니다':
      'Saving stopped because the added content was larger than expected',
  '이 파일은 처리할 수 없습니다': 'This file cannot be processed',
  '다시 시도해 주세요': 'Please try again',
  '다시 시도': 'Retry',
  '목록에서 제거': 'Remove from list',
  '홈으로': 'Go home',
  '정리하기': 'Free up space',
  '화질을 낮춰 다시 저장': 'Save again at lower quality',
  '약 {mb}MB가 더 필요합니다': 'About {mb} MB more space is needed',
  '스캔 작업이 이미 진행 중입니다.': 'A scan is already in progress.',
  '스캔 결과를 가져오지 못했습니다. 다시 시도해 주세요.': 'Could not retrieve the scanned document. Please try again.',
};
