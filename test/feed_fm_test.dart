import 'package:flutter_test/flutter_test.dart';
import 'package:feed_fm/feed_fm.dart';
import 'package:feed_fm/feed_fm_platform_interface.dart';
import 'package:feed_fm/feed_fm_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFeedFmPlatform
    with MockPlatformInterfaceMixin
    implements FeedFmPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FeedFmPlatform initialPlatform = FeedFmPlatform.instance;

  test('$MethodChannelFeedFm is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFeedFm>());
  });

  test('getPlatformVersion', () async {
    FeedFm feedFmPlugin = FeedFm();
    MockFeedFmPlatform fakePlatform = MockFeedFmPlatform();
    FeedFmPlatform.instance = fakePlatform;

    expect(await FeedFm.getPlatformVersion(), '42');
  });
}
