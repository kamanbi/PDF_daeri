/// `settings` 단일 행 접근 리포지토리. (설계 `_workspace/52_architect_week4_design.md`
/// §2.3·§2.4·§2.5·§3.5, 4주차 D-1)
///
/// `SettingsRows`(`ads_removed`·`interstitial_count_today`·`last_ad_date`·
/// `default_quality`, `lib/data/db/tables.dart:80-98`)의 **유일한 접근자**다.
/// 다른 파일이 `SettingsRows`를 직접 쿼리하지 않는다.
///
/// **[2026-08-26 · 사용자 결정]** 전면광고 최소 연타 방지 간격은 설계서 §2.5가
/// 제안한 60초가 아니라 **600초(10분)**로 확정됐다. §2.5 원문대로 DB 컬럼을 추가하지
/// 않고 **메모리 변수**로만 유지한다(앱 재시작 시 초기화 = 관대한 쪽).
library;

import 'package:drift/drift.dart' as drift;

import '../../pdf/image_quality.dart';
import '../db/app_database.dart' as db;

/// 설정 스냅샷(읽기 전용 값 객체). `SettingsRows`의 도메인 표현.
class Settings {
  const Settings({
    required this.defaultQuality,
    required this.adsRemoved,
    required this.interstitialCountToday,
    required this.lastAdDate,
  });

  /// 컬럼 기본값과 동일한 스냅샷(§2.3 컬럼 의미 확정 표). 행이 아직 없을 때 쓴다.
  factory Settings.defaults() => const Settings(
    defaultQuality: ImageQuality.standard,
    adsRemoved: false,
    interstitialCountToday: 0,
    lastAdDate: 0,
  );

  final ImageQuality defaultQuality;

  /// **캐시.** 진실의 원천은 서버가 확인한 Google Play 상태다(§3.5). 이 값 자체는 저장된 그대로를
  /// 반영할 뿐 신뢰 순서를 판단하지 않는다 — 판단은 `lib/billing/entitlement.dart`
  /// (다음 라운드)의 책임이다.
  final bool adsRemoved;

  /// 이전 버전의 일일 광고 횟수 기록. 현재 광고 적격 판정에는 사용하지 않는다.
  final int interstitialCountToday;

  /// 이전 버전의 광고 노출 날짜 기록. 현재 광고 적격 판정에는 사용하지 않는다.
  final int lastAdDate;
}

abstract interface class SettingsRepository {
  /// 현재 설정 1회 조회. 행이 없으면(DB 초기 상태) 컬럼 기본값과 동일한
  /// 스냅샷을 반환한다.
  Future<Settings> load();

  /// 설정 변경 실시간 반영(S5 설정 화면이 구독, 다음 라운드).
  Stream<Settings> watch();

  Future<void> setDefaultQuality(ImageQuality quality);

  /// **캐시 쓰기.** "한 번 true가 되면 사용자가 기기를 초기화하거나 앱 데이터를
  /// 지우기 전까지 자동으로 false가 되지 않는다"(§3.5)는 규칙은 호출자의 책임이다
  /// — 이 메서드 자체는 순수 쓰기이며 호출 여부를 스스로 판단하지 않는다.
  Future<void> setAdsRemoved(bool removed);

  /// 전면광고를 지금 띄워도 되는가 — 최소 연타 방지 간격(600초)만 판정한다.
  Future<bool> isInterstitialEligible();

  /// 전면광고가 **실제로 표시된 직후**(`onAdShowedFullScreenContent`) 호출한다.
  /// 최소 연타 방지 간격의 기준 시각을 이 호출 시점으로 갱신한다. `show()` 호출만으로
  /// 갱신하지 않아 표시 실패가 다음 광고를 막지 않는다.
  Future<void> recordInterstitialShown();
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository({
    required db.AppDatabase database,
    int minIntervalSeconds = 600, // §2.5 확정값(600초=10분). 사유는 클래스 상단 doc 참조.
    DateTime Function() now = DateTime.now,
  }) : _db = database,
       _minIntervalSeconds = minIntervalSeconds,
       _now = now;

  final db.AppDatabase _db;
  final int _minIntervalSeconds;
  final DateTime Function() _now;

  /// §2.5: DB 컬럼이 아니라 메모리 변수로만 유지한다. 리포지토리 인스턴스는
  /// 앱 전역 1개(Provider, 다음 라운드)를 전제한다.
  DateTime? _lastShownAt;

  ImageQuality _qualityFromString(String value) {
    for (final q in ImageQuality.values) {
      if (q.name == value) return q;
    }
    // 알 수 없는 값 방어(수동 DB 편집 등) — 기본값으로 폴백한다.
    return ImageQuality.standard;
  }

  Settings _toDomain(db.SettingsRow row) => Settings(
    defaultQuality: _qualityFromString(row.defaultQuality),
    adsRemoved: row.adsRemoved,
    interstitialCountToday: row.interstitialCountToday,
    lastAdDate: row.lastAdDate,
  );

  Future<db.SettingsRow?> _readRow() => (_db.select(
    _db.settingsRows,
  )..where((t) => t.id.equals(0))).getSingleOrNull();

  @override
  Future<Settings> load() async {
    final row = await _readRow();
    return row == null ? Settings.defaults() : _toDomain(row);
  }

  @override
  Stream<Settings> watch() {
    final query = _db.select(_db.settingsRows)..where((t) => t.id.equals(0));
    return query.watchSingleOrNull().map(
      (row) => row == null ? Settings.defaults() : _toDomain(row),
    );
  }

  /// 행이 없으면 만들고(나머지 컬럼은 DB 기본값), 있으면 present한 필드만 갱신한다.
  Future<void> _upsert({
    drift.Value<String> defaultQuality = const drift.Value.absent(),
    drift.Value<bool> adsRemoved = const drift.Value.absent(),
    drift.Value<int> interstitialCountToday = const drift.Value.absent(),
    drift.Value<int> lastAdDate = const drift.Value.absent(),
  }) {
    return _db
        .into(_db.settingsRows)
        .insertOnConflictUpdate(
          db.SettingsRowsCompanion(
            id: const drift.Value(0),
            defaultQuality: defaultQuality,
            adsRemoved: adsRemoved,
            interstitialCountToday: interstitialCountToday,
            lastAdDate: lastAdDate,
          ),
        );
  }

  @override
  Future<void> setDefaultQuality(ImageQuality quality) {
    return _upsert(defaultQuality: drift.Value(quality.name));
  }

  @override
  Future<void> setAdsRemoved(bool removed) {
    return _upsert(adsRemoved: drift.Value(removed));
  }

  @override
  Future<bool> isInterstitialEligible() async {
    try {
      final lastShown = _lastShownAt;
      if (lastShown != null) {
        final elapsed = _now().difference(lastShown).inSeconds;
        if (elapsed < _minIntervalSeconds) return false;
      }
      return true;
    } catch (_) {
      // §2.3: DB 초기화·조회 실패 시 카운트를 신뢰할 수 없다 → 실패-닫힘.
      return false;
    }
  }

  @override
  Future<void> recordInterstitialShown() {
    _lastShownAt = _now();
    return Future.value();
  }
}
