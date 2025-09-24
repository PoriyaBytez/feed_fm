import 'package:flutter/services.dart';

class FeedFm {
  static const _channel = MethodChannel('feedfm');

  static Future<bool> initialize({
    required String token,
    required String secret,
  }) async {
    final success = await _channel.invokeMethod('initialize', {
      'token': token,
      'secret': secret,
    });
    return success;
  }

  static Future<void> play() => _channel.invokeMethod('play');
  static Future<void> pause() => _channel.invokeMethod('pause');
  static Future<void> skip() => _channel.invokeMethod('skip');


  static Future<List<String>> stations() async {
    final result = await _channel.invokeMethod('stations');
    return List<String>.from(result ?? []);
  }
}

