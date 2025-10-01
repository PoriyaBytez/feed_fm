import 'package:flutter/services.dart';

class FeedFm {
  static const MethodChannel _channel = MethodChannel('feed_fm');

  static Future<String?> getPlatformVersion() async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<void> initialize(String token, String secret) async {
    await _channel.invokeMethod('initialize', {'token': token, 'secret': secret});
  }

  static Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  static Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  static Future<void> skip() async {
    await _channel.invokeMethod('skip');
  }

  static Future<List<String>> stations() async {
    final List<dynamic> result = await _channel.invokeMethod('stations');
    return result.cast<String>();
  }
}
