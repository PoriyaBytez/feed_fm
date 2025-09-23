
import 'feed_fm_platform_interface.dart';

class FeedFm {
  Future<String?> getPlatformVersion() {
    return FeedFmPlatform.instance.getPlatformVersion();
  }
}
