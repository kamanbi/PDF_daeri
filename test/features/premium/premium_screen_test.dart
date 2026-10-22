import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/app/app_locale.dart';
import 'package:pdf_daeri/billing/billing_service.dart';
import 'package:pdf_daeri/billing/entitlement.dart';
import 'package:pdf_daeri/features/premium/premium_screen.dart';

class _FakeBilling implements BillingService {
  _FakeBilling(this._state);

  final PurchaseUiState _state;
  final _controller = StreamController<PurchaseUiState>.broadcast();

  @override
  PurchaseUiState get state => _state;

  @override
  Stream<PurchaseUiState> get statusStream => _controller.stream;

  @override
  SubscriptionPlan? get yearlyPlan => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(PurchaseUiState state, {required bool adsRemoved}) {
  return ProviderScope(
    overrides: [
      billingServiceProvider.overrideWithValue(_FakeBilling(state)),
      adsRemovedProvider.overrideWith((ref) => Stream.value(adsRemoved)),
    ],
    child: const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: [Locale('ko'), Locale('en')],
      home: PremiumScreen(),
    ),
  );
}

void main() {
  testWidgets('상품을 불러오지 못하면 안내 문구를 보이고 구독 버튼을 비활성화한다', (tester) async {
    await tester.pumpWidget(_app(PurchaseUiState.notFound, adsRemoved: false));
    await tester.pump();

    expect(find.text('PDF 대리 프리미엄'), findsOneWidget);
    expect(find.text('지금 구독할 수 없습니다'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('활성 구독이면 구독 중 상태와 관리 버튼을 보인다', (tester) async {
    await tester.pumpWidget(_app(PurchaseUiState.available, adsRemoved: true));
    await tester.pump();

    expect(find.text('구독 중입니다'), findsOneWidget);
    expect(find.text('구독 관리'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
