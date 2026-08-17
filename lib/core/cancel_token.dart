/// 메인 isolate에 남는 객체. 절대 isolate 경계를 넘기지 않는다.
/// 워커에는 SendPort만 전달하고, 취소 신호는 포트 메시지로 보낸다(§8.2).
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
}
