/// Google Play에서 배포된 앱의 업데이트 가능 여부와 즉시 업데이트 흐름.
library;

import 'package:flutter/services.dart';

class PlayUpdateService {
  static const _channel = MethodChannel('com.kamanbi.pdf_daeri/update');

  Future<bool> isImmediateUpdateAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isImmediateUpdateAvailable',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> startImmediateUpdate() async {
    try {
      final result = await _channel.invokeMethod<bool>('startImmediateUpdate');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
