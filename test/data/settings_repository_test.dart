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
    int minIntervalSeconds = 300,
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

  test('isInterstitialEligible: 초기 상태(행 없음)는 true(하루 상한 미달)', () async {
    final repo = repoWith();
    expect(await repo.isInterstitialEligible(), isTrue);
  });

  test('§2.4 하루 상한: 같은 날 3회 표시 후 4번째는 false', () async {
    final fixedNow = DateTime(2026, 8, 26, 10, 0, 0);
    final repo = repoWith(minIntervalSeconds: 0, now: () => fixedNow);

    for (var i = 0; i < 3; i++) {
      expect(await repo.isInterstitialEligible(), isTrue, reason: '${i + 1}번째는 허용');
      await repo.recordInterstitialShown();
    }

    expect(await repo.isInterstitialEligible(), isFalse); // 4번째는 상한 소진

    final settings = await repo.load();
    expect(settings.interstitialCountToday, 3);
    expect(settings.lastAdDate, 20260826);
  });

  test('§2.4 자정 리셋: 날짜가 바뀌면(yyyyMMdd 다름) 카운트가 리셋된 것처럼 판정한다', () async {
    var current = DateTime(2026, 8, 26, 23, 59, 0);
    final repo = repoWith(minIntervalSeconds: 0, now: () => current);

    for (var i = 0; i < 3; i++) {
      await repo.recordInterstitialShown();
    }
    expect(await repo.isInterstitialEligible(), isFalse); // 상한 소진 상태

    // 다음날로 시계를 넘긴다.
    current = DateTime(2026, 8, 27, 0, 5, 0);
    expect(await repo.isInterstitialEligible(), isTrue); // 리셋되어 다시 허용

    await repo.recordInterstitialShown();
    final settings = await repo.load();
    expect(settings.interstitialCountToday, 1); // 리셋 후 1부터
    expect(settings.lastAdDate, 20260827);
  });

  test('§2.4 판정은 부작용이 없다: isInterstitialEligible만 호출해선 DB가 바뀌지 않는다', () async {
    var current = DateTime(2026, 8, 26, 23, 59, 0);
    final repo = repoWith(minIntervalSeconds: 0, now: () => current);
    await repo.recordInterstitialShown();
    await repo.recordInterstitialShown();
    await repo.recordInterstitialShown();

    current = DateTime(2026, 8, 27, 9, 0, 0);
    // 여러 번 판정만 해도 카운트가 바뀌지 않아야 한다(리셋은 표시 확정 시에만).
    await repo.isInterstitialEligible();
    await repo.isInterstitialEligible();

    final settings = await repo.load();
    expect(settings.interstitialCountToday, 3); // 여전히 전날 값 그대로
    expect(settings.lastAdDate, 20260826);
  });

  test(
    '§2.5 연타 방지(5분=300초, 2026-08-26 사용자 결정): 최근 표시 직후 재판정은 false',
    () async {
      final fixedNow = DateTime(2026, 8, 26, 10, 0, 0);
      final repo = repoWith(minIntervalSeconds: 300, now: () => fixedNow);

      await repo.recordInterstitialShown();
      expect(await repo.isInterstitialEligible(), isFalse); // 0초 경과
    },
  );

  test('§2.5 연타 방지: 300초 이상 지나면 다시 허용된다', () async {
    var current = DateTime(2026, 8, 26, 10, 0, 0);
    final repo = repoWith(minIntervalSeconds: 300, now: () => current);

    await repo.recordInterstitialShown();
    current = current.add(const Duration(seconds: 299));
    expect(await repo.isInterstitialEligible(), isFalse); // 아직 미달

    current = current.add(const Duration(seconds: 1)); // 정확히 300초
    expect(await repo.isInterstitialEligible(), isTrue);
  });

  test('recordInterstitialShown: onAdShowedFullScreenContent 확인 후에만 증가(표시 실패는 증가 없음)', () async {
    final repo = repoWith();
    // showIfEligible에 해당하는 판정만 하고 표시 콜백(recordInterstitialShown)을
    // 부르지 않으면 카운트가 그대로여야 한다.
    await repo.isInterstitialEligible();
    await repo.isInterstitialEligible();

    final settings = await repo.load();
    expect(settings.interstitialCountToday, 0);
  });
}
