# feed_fm

A Flutter plugin for Feed.fm that exposes core playback, station management, and advanced controls like seeking, crossfade, and rating across Android and iOS.

## Getting Started

Initialize the SDK with your credentials, subscribe to the event streams, and control playback via the `FeedFm` API.

## Seeking

This plugin supports both forward and backward seeking when the underlying native SDK supports it.

- Check capability:
  - `await FeedFm.supportsSeek()` -> `bool`
- Seek to an absolute position (seconds):
  - `await FeedFm.seekTo(42)`
- Seek by a relative offset (positive or negative seconds):
  - `await FeedFm.seekBy(-15)` // backward 15s
  - `await FeedFm.seekBy(15)`  // forward 15s
- Snapshot helpers:
  - `await FeedFm.getPosition()` -> current position (s)
  - `await FeedFm.getDuration()` -> current track duration (s)

Notes:
- The plugin emits an immediate progress update after a seek for responsive UIs.
- Internally, Android now applies a short “smoothing window” after a seek to reflect the requested position instantly in both directions.

## Events

- Player state: `FeedFm.onStateChanged` -> `PlayerStateEvent`
- Current play info: `FeedFm.onTrackChanged` -> `Play`
- Progress updates: `FeedFm.onProgressChanged` -> `ProgressEvent`
- Skip availability: `FeedFm.onSkipStatusChanged` -> `SkipEvent`
- Station changes: `FeedFm.onStationChanged` -> `Station`
- Errors: `FeedFm.onError` -> `FeedFmError`

For general Flutter plugin development guidance, see the [Flutter documentation](https://docs.flutter.dev).
