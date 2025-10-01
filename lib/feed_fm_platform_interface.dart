import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'feed_fm_method_channel.dart';

abstract class FeedFmPlatform extends PlatformInterface {
  /// Constructs a FeedFmPlatform.
  FeedFmPlatform() : super(token: _token);

  static final Object _token = Object();

  static FeedFmPlatform _instance = MethodChannelFeedFm();

  /// The default instance of [FeedFmPlatform] to use.
  ///
  /// Defaults to [MethodChannelFeedFm].
  static FeedFmPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FeedFmPlatform] when
  /// they register themselves.
  static set instance(FeedFmPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
