import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/ads/ads_bootstrap.dart';

void main() {
  test('runtime height activates a banner after a subscribed boot', () {
    final container = ProviderContainer(
      overrides: [bootBannerHeightProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    expect(container.read(bannerHeightProvider), isNull);
    container.read(runtimeBannerHeightProvider.notifier).state = 50;
    expect(container.read(bannerHeightProvider), 50);
  });

  test('boot height remains available without a runtime replacement', () {
    final container = ProviderContainer(
      overrides: [bootBannerHeightProvider.overrideWithValue(48)],
    );
    addTearDown(container.dispose);

    expect(container.read(bannerHeightProvider), 48);
  });
}
