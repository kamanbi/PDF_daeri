/// 프리미엄(연간 구독) 안내·구매 화면.
///
/// 설정의 구독 항목과 뷰어의 OCR 잠금이 모두 이 화면 하나로 모인다. 구매·복원·상태는
/// `billing_service.dart`(구매/복원)와 `entitlement.dart`(`adsRemovedProvider`)를 그대로
/// 소비하며, 이 화면은 상태를 만들지 않는다. 배너 광고를 두지 않는다(`ads.md` 배치 지점 아님).
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_locale.dart';
import '../../billing/billing_service.dart';
import '../../billing/entitlement.dart';
import '../settings/settings_screen.dart'
    show
        kAppStoreSubscriptionManageUrl,
        kAppleStandardEulaUrl,
        kPrivacyPolicyUrl,
        kSubscriptionManageUrl;

Future<void> showPremiumScreen(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const PremiumScreen()));
}

bool get _isIosStore => defaultTargetPlatform == TargetPlatform.iOS;

const _billingChannel = MethodChannel('com.kamanbi.pdf_daeri/billing');

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  late final BillingService _billing;
  late PurchaseUiState _uiState;
  StreamSubscription<PurchaseUiState>? _sub;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _billing = ref.read(billingServiceProvider);
    _uiState = _billing.state;
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

  /// iOS는 Apple의 구독 관리 시트를 먼저 띄운다(TestFlight 테스트 구독도 여기서 취소할 수 있다).
  /// 시트를 띄우지 못하면 구독 관리 웹 링크로 대신한다.
  Future<void> _manageSubscription() async {
    if (_isIosStore) {
      try {
        final shown = await _billingChannel.invokeMethod<bool>(
          'showManageSubscriptions',
        );
        if (shown == true) return;
      } catch (_) {
        // 채널 오류는 아래 웹 링크로 대신한다.
      }
      if (!mounted) return;
    }
    await _open(
      _isIosStore ? kAppStoreSubscriptionManageUrl : kSubscriptionManageUrl,
      _isIosStore
          ? 'App Store 구독 관리 페이지를 열 수 없습니다'
          : 'Google Play 구독 관리 페이지를 열 수 없습니다',
    );
  }

  Future<void> _open(String url, String failureMessage) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appText(context, failureMessage))));
  }

  @override
  Widget build(BuildContext context) {
    // 광고 제거와 OCR은 같은 검증된 구독이 허용한다 -- 같은 값을 `ocrEntitlementProvider`로 읽는다.
    final subscribed = ref.watch(ocrEntitlementProvider).valueOrNull ?? false;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context, '프리미엄'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: 56,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              appText(context, 'PDF 대리 프리미엄'),
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appText(context, '광고 없이 쓰고, 스캔한 문서의 글자까지 인식합니다'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            _BenefitTile(
              icon: Icons.block_rounded,
              title: appText(context, '광고 제거'),
              description: appText(context, '앱 어디에서도 광고가 표시되지 않습니다'),
            ),
            const SizedBox(height: 12),
            _BenefitTile(
              icon: Icons.text_snippet_outlined,
              title: appText(context, 'OCR PDF 만들기'),
              description: appText(
                context,
                '스캔·사진 문서의 글자를 인식해 검색·선택·복사할 수 있습니다',
              ),
            ),
            const SizedBox(height: 28),
            if (subscribed)
              _buildActive(context)
            else
              _buildPurchase(context),
            const SizedBox(height: 24),
            Text(
              appText(
                context,
                _isIosStore
                    ? '구독은 App Store 계정으로 결제되며, 현재 기간이 끝나기 최소 24시간 전에 해지하지 않으면 자동으로 갱신됩니다. 구매 후 설정에서 관리하거나 해지할 수 있습니다.'
                    : '구독은 Google Play 계정으로 결제되며, 현재 기간이 끝나기 최소 24시간 전에 해지하지 않으면 자동으로 갱신됩니다. Google Play에서 언제든 관리하거나 해지할 수 있습니다.',
              ),
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (_isIosStore)
                  TextButton(
                    onPressed: () =>
                        _open(kAppleStandardEulaUrl, '이용 약관을 열 수 없습니다'),
                    child: Text(appText(context, '이용 약관')),
                  ),
                TextButton(
                  onPressed: () =>
                      _open(kPrivacyPolicyUrl, '개인정보처리방침을 열 수 없습니다'),
                  child: Text(appText(context, '개인정보처리방침')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActive(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appText(context, '구독 중입니다'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _manageSubscription,
                child: Text(appText(context, '구독 관리')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchase(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final plan = _billing.yearlyPlan;
    final canBuy = _uiState == PurchaseUiState.available && plan != null;
    final pending = _uiState == PurchaseUiState.purchasePending;
    final canRestore =
        _uiState != PurchaseUiState.unavailable &&
        _uiState != PurchaseUiState.loading;

    final priceText = switch (_uiState) {
      PurchaseUiState.loading => appText(context, '불러오는 중…'),
      PurchaseUiState.unavailable => appText(
        context,
        '이 기기에서는 구독을 사용할 수 없습니다',
      ),
      PurchaseUiState.notFound => appText(context, '지금 구독할 수 없습니다'),
      _ when plan != null =>
        '${plan.product.price} / ${appText(context, plan.billingPeriod)} · ${appText(context, '자동 갱신')}',
      _ => appText(context, '현재 이용할 수 없습니다'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              appText(context, '연간 구독'),
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              priceText,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: canBuy ? colorScheme.primary : null,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canBuy && !pending ? () => _billing.buy(plan) : null,
                child: pending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(appText(context, '구독하기')),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: canRestore && !_restoring ? _restore : null,
              child: _restoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(appText(context, '구독 상태 갱신')),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                description,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
