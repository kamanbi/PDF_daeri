/// 외부 인텐트로 도착한 `content://` URI를 **앱 전체에서 한 곳에서만** 수신한다.
/// (설계 §4.3, 2주차 확정)
///
/// 네이티브(`MainActivity.kt`)와 `SafImporter` 래퍼는 1주차부터 이미 구현되어
/// 있었다 — 이 파일이 채우는 것은 그 둘을 앱 부팅·생명주기에 연결하는 배선이다
/// (§4.1의 미해소분 1·2·3).
///
/// 두 곳에서 구독하면 같은 파일이 두 번 임포트되어 `recent/`에 복사본이 두 개
/// 생긴다. 그래서 이 클래스는 앱 루트에서 정확히 하나만 만들어지고([lib/app/providers.dart]의
/// `incomingIntentServiceProvider`), 화면은 이 클래스가 내보내는 스트림만 본다.
library;

import 'dart:async';

import '../data/storage/saf_import.dart';

class IncomingIntentService {
  IncomingIntentService(this._importer);
  final SafImporter _importer;

  final StreamController<String> _controller = StreamController<String>();

  /// 수신된 URI. **broadcast가 아니다** — 구독자는 앱 루트 위젯 하나뿐이다.
  Stream<String> get uris => _controller.stream;

  StreamSubscription<String>? _nativeSub;
  bool _started = false;

  /// 앱 부팅 시 1회. 순서 고정: ① 스트림 구독 ② `takeInitialUri()` 1회 조회.
  /// 이 순서를 바꾸면 부팅 중 도착한 인텐트를 잃는다(§4.2).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // ① 먼저 구독한다 — 그 사이 도착하는 인텐트가 sink 부재로 네이티브 쪽
    // pendingInitialUri에 갇히는 것을 최소화한다.
    _nativeSub = _importer.onNewIntentUri().listen((uri) {
      if (!_controller.isClosed) _controller.add(uri);
    });

    // ② takeInitialUri()는 네이티브에서 1회 소비된다(같은 URI가 두 번 오지 않음).
    final initial = await _importer.takeInitialUri();
    if (initial != null && !_controller.isClosed) {
      _controller.add(initial);
    }
  }

  /// `AppLifecycleState.resumed` 마다 호출. 네이티브가 sink 부재 중 보관해 둔
  /// URI를 회수한다(§4.1 미해소분 3 — 이전에는 아무도 다시 묻지 않아 그 URI가
  /// 영영 사라졌다). 네이티브가 1회 소비 규약을 지키므로 중복 방출이 없다.
  Future<void> pollPending() async {
    final pending = await _importer.takeInitialUri();
    if (pending != null && !_controller.isClosed) {
      _controller.add(pending);
    }
  }

  Future<void> dispose() async {
    await _nativeSub?.cancel();
    await _controller.close();
  }
}
