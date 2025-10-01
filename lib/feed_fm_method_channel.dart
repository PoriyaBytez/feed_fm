import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'feed_fm_platform_interface.dart';

/// An implementation of [FeedFmPlatform] that uses method channels.
class MethodChannelFeedFm extends FeedFmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('feed_fm');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
