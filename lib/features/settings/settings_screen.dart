/// 설정 화면. (설계 `_workspace/52_architect_week4_design.md` §6 전체, W4-T9)
///
/// 항목 순서는 §6.1 그대로: [1] 광고 제거 → [2] 기본 저장 화질 → [3] 저장 공간 →
/// [4] 개인정보처리방침 → [5] 오픈소스 라이선스(기존 R10 구현, 그대로 유지) → 배너.
/// 계정·로그인 항목 없음(`screens.md:96`), `sources/` 정리 항목 없음(사용자 확정 —
/// §10.1 문서 모순, `screens.md` 3개 항목 채택).
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ads/banner_host.dart';
import '../../app/providers.dart';
import '../../app/app_locale.dart';
import '../../billing/billing_service.dart';
import '../../billing/entitlement.dart';
import '../../core/platform_features.dart';
import '../../data/repository/recent_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../data/storage/workspace.dart';
import '../../pdf/image_quality.dart';

/// 앱 부팅 시 1회 호출한다(`main.dart`). `LicenseRegistry.addLicense`에 등록된 항목은
/// Flutter 표준 `showLicensePage`/`LicensePage`(이 화면이 여는 것과 동일 위젯, 그리고
/// Flutter가 기본 제공하는 `AboutDialog`의 "라이선스 보기" 버튼)에 자동으로 나타난다.
///
/// 대상(R10 — qpdf 마이그레이션이 새로 끌어들인 네이티브 의존성 + 기존 폰트):
/// - qpdf 12.4.0 — Apache License 2.0 (`tool/qpdf_build_manifest.md`)
/// - libjpeg-turbo 3.0.4 — IJG License + Modified(3-clause) BSD License(공식 LICENSE.md
///   원문을 그대로 자산에 포함, `tool/qpdf_build_manifest.md`가 버전 확인 근거)
/// - zlib(Android NDK 제공, qpdf에 정적 링크) — zlib License
/// - Noto Sans KR — SIL Open Font License 1.1(이미 `assets/fonts/OFL.txt`로 번들돼 있었으나
///   라이선스 화면에는 아직 반영되지 않았던 것을 이번에 연결한다)
void registerOpenSourceLicenses() {
  LicenseRegistry.addLicense(() async* {
    final apache2 = await rootBundle.loadString(
      'assets/licenses/apache-2.0.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['qpdf'], apache2);

    final libjpegTurbo = await rootBundle.loadString(
      'assets/licenses/libjpeg-turbo-LICENSE.md',
    );
    yield LicenseEntryWithLineBreaks(const ['libjpeg-turbo'], libjpegTurbo);

    final zlib = await rootBundle.loadString('assets/licenses/zlib.txt');
    yield LicenseEntryWithLineBreaks(const ['zlib'], zlib);

    final notoSansKr = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Noto Sans KR'], notoSansKr);
  });
}

const String kPrivacyPolicyUrl = 'https://pdf-daeri.netlify.app/privacy.html';
const String kHomepageUrl = 'https://pdf-daeri.netlify.app/';
const String kGooglePlayReviewUrl =
    'https://play.google.com/store/apps/details?id=com.kamanbi.pdf_daeri&showAllReviews=true';

const String kSubscriptionManageUrl =
    'https://play.google.com/store/account/subscriptions?sku=ads_removed&package=com.kamanbi.pdf_daeri';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context, '설정'))),
      body: ListView(
        // 방어 2 — 완충 밴드(§1.3). 마지막 항목(라이선스)이 배너에 가리지 않게 한다.
        padding: EdgeInsets.only(bottom: BannerHost.contentBottomPadding(ref)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _SettingsLayout.screenHorizontalPadding,
              _SettingsLayout.sectionTopPadding,
              _SettingsLayout.screenHorizontalPadding,
              0,
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // 68 §6: AppFeatures.billing이 거짓이면 결제 관련 UI 블록
                  // 전체(광고 제거 구독/구독 관리/구독 상태 갱신)를 렌더하지 않는다.
                  if (AppFeatures.billing) ...const [
                    _AdRemovalSection(),
                    _SettingsDivider(),
                  ],
                  const _DefaultQualityTile(),
                  const _SettingsDivider(),
                  const _ThemeModeTile(),
                  const _SettingsDivider(),
                  const _LanguageTile(),
                  const _SettingsDivider(),
                  const _StorageTile(),
                  const _SettingsDivider(),
                  const _HomepageTile(),
                  const _SettingsDivider(),
                  const _PrivacyPolicyTile(),
                  const _SettingsDivider(),
                  const _AppReviewTile(),
                  const _SettingsDivider(),
                  const _LicenseTile(),
                ],
              ),
            ),
          ),
          const _AppVersionFooter(),
        ],
      ),
      // 배너(§1.1) — 항상 bottomNavigationBar에만 놓는다. 이 라운드는 건드리지 않는다.
      bottomNavigationBar: const BannerHost(slot: BannerSlot.settings),
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(languageChoiceProvider);
    final label = switch (choice) {
      LanguageChoice.automatic => appText(context, '자동'),
      LanguageChoice.korean => appText(context, '한국어'),
      LanguageChoice.english => appText(context, '영어'),
    };
    return _SettingsRow(
      title: appText(context, '언어'),
      subtitle: Text(label),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in LanguageChoice.values)
                ListTile(
                  title: Text(switch (option) {
                    LanguageChoice.automatic => appText(sheetContext, '자동'),
                    LanguageChoice.korean => appText(sheetContext, '한국어'),
                    LanguageChoice.english => appText(sheetContext, '영어'),
                  }),
                  trailing: option == choice ? const Icon(Icons.check) : null,
                  onTap: () {
                    ref.read(languageChoiceProvider.notifier).select(option);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _SettingsLayout {
  static const double screenHorizontalPadding = 16;
  static const double sectionTopPadding = 12;
  static const double rowHorizontalPadding = 20;
  static const double rowVerticalPadding = 16;
  static const double footerTopPadding = 28;
  static const double footerBottomPadding = 20;
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: _SettingsLayout.rowHorizontalPadding,
      endIndent: _SettingsLayout.rowHorizontalPadding,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _SettingsLayout.rowHorizontalPadding,
        vertical: _SettingsLayout.rowVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  DefaultTextStyle.merge(
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

class _AppVersionFooter extends StatefulWidget {
  const _AppVersionFooter();

  @override
  State<_AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<_AppVersionFooter> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final packageInfo = snapshot.data;
        final versionText = switch (snapshot) {
          _ when snapshot.hasError => appText(context, '버전 정보를 확인할 수 없습니다'),
          _ when packageInfo == null => appText(context, '버전 정보를 확인하는 중입니다'),
          _ =>
            '${appText(context, '버전')} ${packageInfo.version} (${packageInfo.buildNumber})',
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            _SettingsLayout.screenHorizontalPadding,
            _SettingsLayout.footerTopPadding,
            _SettingsLayout.screenHorizontalPadding,
            _SettingsLayout.footerBottomPadding,
          ),
          child: Text(
            versionText,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
        );
      },
    );
  }
}

/// §6.1 [5] 오픈소스 라이선스 — 기존 구현(`registerOpenSourceLicenses`) 그대로,
/// 이번 라운드는 건드리지 않는다. `ListView`의 `const` 자식 목록에 넣기 위해
/// 위젯으로 뺐을 뿐 동작은 이전과 동일하다.
class _LicenseTile extends StatelessWidget {
  const _LicenseTile();

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: appText(context, '오픈소스 라이선스'),
      subtitle: const Text('qpdf · libjpeg-turbo · zlib · Noto Sans KR'),
      onTap: () => showLicensePage(
        context: context,
        applicationName: appText(context, 'PDF 대리'),
        applicationLegalese: appText(
          context,
          '이 앱은 오픈소스 소프트웨어를 사용합니다. 각 항목을 눌러 전문을 확인하세요.',
        ),
      ),
    );
  }
}

/// §6.2 [1] 광고 제거. `billing_service.dart`(구매/복원 흐름)·`entitlement.dart`
/// (`adsRemovedProvider`, 신뢰의 최종 상태)를 그대로 소비한다 — 이 위젯은 상태를
/// 만들지 않는다.
class _AdRemovalSection extends ConsumerStatefulWidget {
  const _AdRemovalSection();

  @override
  ConsumerState<_AdRemovalSection> createState() => _AdRemovalSectionState();
}

class _AdRemovalSectionState extends ConsumerState<_AdRemovalSection> {
  late final BillingService _billing;
  late PurchaseUiState _uiState;
  StreamSubscription<PurchaseUiState>? _sub;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _billing = ref.read(billingServiceProvider);
    _uiState = _billing.state;
    // §3.3: purchased/restored 이벤트에서 "광고가 제거되었습니다" 스낵바.
    // 부팅 시 자동 복원(§3.6)처럼 이 화면이 열리기 전에 이미 반영된 상태는
    // 여기서 다시 알리지 않는다 — 이 구독은 화면이 열려 있는 동안의 이벤트만 본다.
    _sub = _billing.statusStream.listen((state) {
      if (!mounted) return;
      setState(() => _uiState = state);
      if (state == PurchaseUiState.purchased) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText(context, '구독 혜택이 적용되었습니다'))),
        );
      }
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final outcome = await _billing.restoreManually();
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          appText(context, switch (outcome) {
            RestoreOutcome.restored => '활성 구독을 확인했습니다',
            RestoreOutcome.nothingToRestore => '활성 구독이 없습니다',
            RestoreOutcome.verificationUnavailable =>
              '구독 확인 서버에 연결하지 못했습니다. 기존 구독 혜택은 유지됩니다.',
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adsRemoved = ref.watch(adsRemovedProvider).valueOrNull ?? false;

    // 활성 구독이면 상태와 관리 진입점만 보여 준다.
    if (adsRemoved) {
      return _buildActiveSubscriptionRows();
    }

    switch (_uiState) {
      case PurchaseUiState.loading:
        return _SettingsRow(
          title: appText(context, '광고 제거 + OCR'),
          subtitle: Text(appText(context, '불러오는 중…')),
        );
      case PurchaseUiState.unavailable:
        // §3.6: 구매·복원 항목을 비활성 + 안내 문구로 둔다. 항목 자체는 숨기지 않는다.
        return _buildPurchaseRows(
          yearlyPlan: null,
          unavailableMessage: appText(context, '이 기기에서는 구독을 사용할 수 없습니다'),
          buyEnabled: false,
          restoreEnabled: false,
        );
      case PurchaseUiState.notFound:
        return _buildPurchaseRows(
          yearlyPlan: null,
          unavailableMessage: appText(context, '지금 구독할 수 없습니다'),
          buyEnabled: false,
          restoreEnabled: true,
        );
      case PurchaseUiState.available:
        return _buildPurchaseRows(
          yearlyPlan: _billing.yearlyPlan,
          unavailableMessage: appText(context, '현재 이용할 수 없습니다'),
          buyEnabled: true,
          restoreEnabled: true,
        );
      case PurchaseUiState.purchasePending:
        // §6.2: 버튼 자리에 16dp 스피너, 재탭 차단.
        return _SettingsRow(
          title: appText(context, '광고 제거 + OCR'),
          subtitle: Text(appText(context, '처리 중…')),
          trailing: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case PurchaseUiState.purchased:
        return _buildActiveSubscriptionRows();
    }
  }

  Widget _buildActiveSubscriptionRows() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SettingsRow(
          title: appText(context, '광고 제거 + OCR'),
          subtitle: Text(appText(context, '구독 중 · 광고 없이 OCR PDF를 만들 수 있습니다')),
        ),
        const _SettingsDivider(),
        _SettingsRow(
          title: appText(context, '구독 관리'),
          subtitle: Text(appText(context, 'Google Play에서 갱신 또는 취소할 수 있습니다')),
          trailing: OutlinedButton(
            onPressed: _openSubscriptionManagement,
            child: Text(appText(context, '관리')),
          ),
        ),
      ],
    );
  }

  Future<void> _openSubscriptionManagement() async {
    final opened = await launchUrl(
      Uri.parse(kSubscriptionManageUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appText(context, 'Google Play 구독 관리 페이지를 열 수 없습니다')),
      ),
    );
  }

  Widget _buildPurchaseRows({
    required SubscriptionPlan? yearlyPlan,
    required String unavailableMessage,
    required bool buyEnabled,
    required bool restoreEnabled,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPlanPurchaseRow(
          title: appText(context, '연간 광고 제거 + OCR'),
          plan: yearlyPlan,
          unavailableMessage: unavailableMessage,
          buyEnabled: buyEnabled,
        ),
        const _SettingsDivider(),
        _SettingsRow(
          title: appText(context, '구독 상태 갱신'),
          subtitle: Text(appText(context, 'Google Play의 활성 구독을 다시 확인합니다')),
          trailing: OutlinedButton(
            onPressed: (restoreEnabled && !_restoring) ? _restore : null,
            child: _restoring
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(appText(context, '갱신')),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanPurchaseRow({
    required String title,
    required SubscriptionPlan? plan,
    required String unavailableMessage,
    required bool buyEnabled,
  }) {
    final subtitle = plan == null
        ? unavailableMessage
        : '${plan.product.price} / ${appText(context, plan.billingPeriod)} · ${appText(context, '자동 갱신')}';
    return _SettingsRow(
      title: title,
      subtitle: Text(subtitle),
      trailing: FilledButton(
        onPressed: buyEnabled && plan != null ? () => _billing.buy(plan) : null,
        child: Text(appText(context, '구독')),
      ),
    );
  }
}

/// §6.4 [2] 기본 저장 화질. `SettingsRepository.default_quality`를 읽고 쓴다.
/// `ImageQuality` ↔ 문자열 매핑의 단일 소유자는 `settings_repository.dart`다 — 이
/// 화면은 도메인 값(`ImageQuality`)만 받고 문자열을 직접 다루지 않는다.
class _DefaultQualityTile extends ConsumerWidget {
  const _DefaultQualityTile();

  // save_dialog.dart `_QualityTile`과 동일한 라벨(§5.1 문구 통일).
  static const _labels = {
    ImageQuality.high: '고화질',
    ImageQuality.standard: '기본',
    ImageQuality.min: '최소',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(settingsRepositoryProvider);
    if (repo == null) {
      return _SettingsRow(
        title: appText(context, '기본 저장 화질'),
        subtitle: Text(appText(context, '지금 사용할 수 없습니다')),
      );
    }
    return StreamBuilder<Settings>(
      stream: repo.watch(),
      builder: (context, snapshot) {
        final quality = snapshot.data?.defaultQuality ?? ImageQuality.standard;
        return _SettingsRow(
          title: appText(context, '기본 저장 화질'),
          subtitle: Text(appText(context, _labels[quality]!)),
          onTap: () => _pick(context, repo, quality),
        );
      },
    );
  }

  Future<void> _pick(
    BuildContext context,
    SettingsRepository repo,
    ImageQuality current,
  ) async {
    final selected = await showModalBottomSheet<ImageQuality>(
      context: context,
      builder: (ctx) => SafeArea(
        child: RadioGroup<ImageQuality>(
          groupValue: current,
          onChanged: (value) => Navigator.of(ctx).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // §1.6: S5 기본값 목록에는 `original`을 노출하지 않는다(Q2 미결).
              // `ImageQuality.values` 순회 대신 명시적 3종 리스트를 쓴다.
              for (final q in const [
                ImageQuality.high,
                ImageQuality.standard,
                ImageQuality.min,
              ])
                RadioListTile<ImageQuality>(
                  title: Text(appText(ctx, _labels[q]!)),
                  value: q,
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != current) {
      await repo.setDefaultQuality(selected);
    }
  }
}

/// [82 최종검증 M1 해소 · §5.5] 화면 테마. `_DefaultQualityTile`과 동일한 패턴
/// (모달 바텀시트 + RadioGroup) — 새 위젯 스타일을 만들지 않는다.
/// `SettingsRepository.watchThemeMode()`/`setThemeMode()`를 그대로 소비한다.
class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile();

  static const _labels = {
    AppThemeMode.light: '라이트',
    AppThemeMode.dark: '다크',
    AppThemeMode.system: '시스템 기본',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(settingsRepositoryProvider);
    if (repo == null) {
      return _SettingsRow(
        title: appText(context, '화면 테마'),
        subtitle: Text(appText(context, '지금 사용할 수 없습니다')),
      );
    }
    return StreamBuilder<AppThemeMode>(
      stream: repo.watchThemeMode(),
      builder: (context, snapshot) {
        final mode = snapshot.data ?? AppThemeMode.system;
        return _SettingsRow(
          title: appText(context, '화면 테마'),
          subtitle: Text(appText(context, _labels[mode]!)),
          onTap: () => _pick(context, repo, mode),
        );
      },
    );
  }

  Future<void> _pick(
    BuildContext context,
    SettingsRepository repo,
    AppThemeMode current,
  ) async {
    final selected = await showModalBottomSheet<AppThemeMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: RadioGroup<AppThemeMode>(
          groupValue: current,
          onChanged: (value) => Navigator.of(ctx).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in const [
                AppThemeMode.light,
                AppThemeMode.dark,
                AppThemeMode.system,
              ])
                RadioListTile<AppThemeMode>(
                  title: Text(appText(ctx, _labels[m]!)),
                  value: m,
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != current) {
      await repo.setThemeMode(selected);
    }
  }
}

/// §6.3 [3] 저장 공간. 목록 UI를 만들지 않는다는 판정 그대로 — 요약 항목은 진입점
/// 하나뿐이고, 실제 숫자 4줄 + 버튼 2개는 `_StorageDetailScreen`(별도 화면)에 있다.
class _StorageTile extends ConsumerWidget {
  const _StorageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    if (workspace == null) {
      return _SettingsRow(
        title: appText(context, '저장 공간'),
        subtitle: Text(appText(context, '지금 사용할 수 없습니다')),
      );
    }
    return _SettingsRow(
      title: appText(context, '저장 공간'),
      subtitle: FutureBuilder<StorageUsage>(
        future: workspace.usage(),
        builder: (context, snapshot) {
          final usage = snapshot.data;
          if (usage == null) return Text(appText(context, '계산 중…'));
          return Text(
            '${appText(context, '사용 중')} ${_formatMb(usage.totalBytes)}',
          );
        },
      ),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const _StorageDetailScreen())),
    );
  }
}

String _formatMb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

/// §6.3 본문 그대로: 숫자 4줄(내 문서/최근 연 파일/캐시/합계) + 버튼 2개.
/// 두 번째 파일 목록 UI를 만들지 않는다 — 개별 삭제는 홈에 이미 있다(설계 근거 1·2).
class _StorageDetailScreen extends ConsumerStatefulWidget {
  const _StorageDetailScreen();

  @override
  ConsumerState<_StorageDetailScreen> createState() =>
      _StorageDetailScreenState();
}

class _StorageDetailScreenState extends ConsumerState<_StorageDetailScreen> {
  Future<StorageUsage>? _usageFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final workspace = ref.read(workspaceProvider);
    setState(() {
      _usageFuture = workspace?.usage();
    });
  }

  Future<void> _clearCache() async {
    final workspace = ref.read(workspaceProvider);
    if (workspace == null) return;
    setState(() => _busy = true);
    // §6.3: "항상 삭제해도 안전"이 계약이다 — 확인 창을 두지 않는다.
    await workspace.clearCache();
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appText(context, '캐시를 비웠습니다'))));
  }

  Future<void> _clearRecent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appText(ctx, '최근 파일 전체 정리')),
        content: Text(appText(ctx, '원본 파일은 지워지지 않습니다')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(appText(ctx, '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(appText(ctx, '정리')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(recentRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    await repo.clearAll();
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(appText(context, '최근 연 파일을 정리했습니다'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appText(context, '저장 공간'))),
      body: FutureBuilder<StorageUsage>(
        future: _usageFuture,
        builder: (context, snapshot) {
          if (_usageFuture == null ||
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final usage = snapshot.data;
          if (usage == null) {
            return Center(child: Text(appText(context, '지금 사용할 수 없습니다')));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _UsageRow(
                label: appText(context, '내 문서'),
                bytes: usage.docsBytes,
              ),
              _UsageRow(
                label: appText(context, '최근 연 파일'),
                bytes: usage.recentBytes,
                trailing: appText(context, '{total}개 중 {used}개')
                    .replaceAll(
                      '{total}',
                      '${DriftRecentRepository.quotaCount}',
                    )
                    .replaceAll('{used}', '${usage.recentCount}'),
              ),
              _UsageRow(
                label: appText(context, '캐시'),
                bytes: usage.cacheBytes + usage.thumbsBytes,
              ),
              const Divider(height: 24),
              _UsageRow(
                label: appText(context, '합계'),
                bytes: usage.totalBytes,
                emphasize: true,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: _busy ? null : _clearCache,
                child: Text(appText(context, '캐시 비우기')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _clearRecent,
                child: Text(appText(context, '최근 파일 전체 정리')),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.label,
    required this.bytes,
    this.trailing,
    this.emphasize = false,
  });

  final String label;
  final int bytes;
  final String? trailing;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(_formatMb(bytes), style: style),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _HomepageTile extends StatelessWidget {
  const _HomepageTile();

  @override
  Widget build(BuildContext context) {
    return _ExternalLinkTile(
      title: appText(context, '홈페이지'),
      subtitle: appText(context, 'PDF 대리 홈페이지를 엽니다'),
      url: kHomepageUrl,
      failureMessage: appText(context, '홈페이지를 열 수 없습니다'),
    );
  }
}

class _PrivacyPolicyTile extends StatelessWidget {
  const _PrivacyPolicyTile();

  @override
  Widget build(BuildContext context) {
    return _ExternalLinkTile(
      title: appText(context, '개인정보처리방침'),
      subtitle: appText(context, '수집·이용 정보를 확인합니다'),
      url: kPrivacyPolicyUrl,
      failureMessage: appText(context, '개인정보처리방침을 열 수 없습니다'),
    );
  }
}

class _AppReviewTile extends StatelessWidget {
  const _AppReviewTile();

  @override
  Widget build(BuildContext context) {
    return _ExternalLinkTile(
      title: appText(context, '칭찬하기'),
      subtitle: appText(context, 'Google Play에서 별점과 리뷰를 남겨 주세요'),
      url: kGooglePlayReviewUrl,
      failureMessage: appText(context, 'Google Play 리뷰 페이지를 열 수 없습니다'),
    );
  }
}

class _ExternalLinkTile extends StatelessWidget {
  const _ExternalLinkTile({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.failureMessage,
  });

  final String title;
  final String subtitle;
  final String url;
  final String failureMessage;

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: title,
      subtitle: Text(subtitle),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage)));
  }
}
