import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/data/db/app_database.dart';
import 'package:pdf_daeri/data/repository/settings_repository.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  DriftSettingsRepository repoWith({
    int minIntervalSeconds = 600,
    DateTime Function()? now,
  }) {
    return DriftSettingsRepository(
      database: db,
      minIntervalSeconds: minIntervalSeconds,
      now: now ?? DateTime.now,
    );
  }

  test('load: 행이 없으면 컬럼 기본값과 동일한 스냅샷을 반환한다', () async {
    final repo = repoWith();
    final settings = await repo.load();

    expect(settings.defaultQuality, ImageQuality.standard);
    expect(settings.adsRemoved, isFalse);
    expect(settings.interstitialCountToday, 0);
    expect(settings.lastAdDate, 0);
  });

  test('setDefaultQuality: 행이 없어도 upsert로 생성하고 저장한다', () async {
    final repo = repoWith();
    await repo.setDefaultQuality(ImageQuality.high);

    final settings = await repo.load();
    expect(settings.defaultQuality, ImageQuality.high);
    // 다른 컬럼은 기본값을 유지한다.
    expect(settings.adsRemoved, isFalse);
  });

  test('setAdsRemoved: true로 쓰면 즉시 반영되고 다른 컬럼은 보존된다', () async {
    final repo = repoWith();
    await repo.setDefaultQuality(ImageQuality.min);
    await repo.setAdsRemoved(true);

    final settings = await repo.load();
    expect(settings.adsRemoved, isTrue);
    expect(settings.defaultQuality, ImageQuality.min); // 보존
  });

  test('watch: 쓰기 이후 스트림이 최신 스냅샷을 방출한다', () async {
    final repo = repoWith();
    final future = repo.watch().firstWhere((s) => s.adsRemoved);
    await repo.setAdsRemoved(true);

    final settings = await future;
    expect(settings.adsRemoved, isTrue);
  });

  test('isInterstitialEligible: 초기 상태(행 없음)는 true', () async {
    final repo = repoWith();
    expect(await repo.isInterstitialEligible(), isTrue);
  });

  test('같은 날 광고를 여러 번 본 이력이 있어도 일일 상한으로 차단하지 않는다', () async {
    final fixedNow = DateTime(2026, 8, 26, 10, 0, 0);
    final repo = repoWith(minIntervalSeconds: 0, now: () => fixedNow);

    for (var i = 0; i < 4; i++) {
      expect(
        await repo.isInterstitialEligible(),
        isTrue,
        reason: '${i + 1}번째도 일일 상한 없이 허용',
      );
      await repo.recordInterstitialShown();
    }

    final settings = await repo.load();
    expect(settings.interstitialCountToday, 0);
    expect(settings.lastAdDate, 0);
  });

  test('§2.5 연타 방지(10분=600초): 최근 표시 직후 재판정은 false', () async {
    final fixedNow = DateTime(2026, 8, 26, 10, 0, 0);
    final repo = repoWith(minIntervalSeconds: 600, now: () => fixedNow);

    await repo.recordInterstitialShown();
    expect(await repo.isInterstitialEligible(), isFalse); // 0초 경과
  });

  test('§2.5 연타 방지: 600초 이상 지나면 다시 허용된다', () async {
    var current = DateTime(2026, 8, 26, 10, 0, 0);
    final repo = repoWith(minIntervalSeconds: 600, now: () => current);

    await repo.recordInterstitialShown();
    current = current.add(const Duration(seconds: 599));
    expect(await repo.isInterstitialEligible(), isFalse); // 아직 미달

    current = current.add(const Duration(seconds: 1)); // 정확히 600초
    expect(await repo.isInterstitialEligible(), isTrue);
  });
}
