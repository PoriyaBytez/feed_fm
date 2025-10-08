import 'package:flutter/services.dart';

class FeedFm {
  static const MethodChannel _methodChannel = MethodChannel('feed_fm');
  static const EventChannel _stateEventChannel = EventChannel('feed_fm/state_events');
  static const EventChannel _trackEventChannel = EventChannel('feed_fm/track_events');
  static const EventChannel _progressEventChannel = EventChannel('feed_fm/progress_events');
  static const EventChannel _skipEventChannel = EventChannel('feed_fm/skip_events');
  // New event channels
  static const EventChannel _stationEventChannel = EventChannel('feed_fm/station_events');
  static const EventChannel _errorEventChannel = EventChannel('feed_fm/error_events');

  static Stream<PlayerStateEvent>? _stateStream;
  static Stream<Play>? _trackStream;
  static Stream<ProgressEvent>? _progressStream;
  static Stream<SkipEvent>? _skipStream;
  // New streams
  static Stream<Station>? _stationStream;
  static Stream<FeedFmError>? _errorStream;

  // ====================================
  // INITIALIZATION
  // ====================================

  static Future<bool> initialize({
    required String token,
    required String secret,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod('initialize', {
        'token': token,
        'secret': secret,
      });
      return result == true;
    } catch (e) {
      // Keep print: dev troubleshooting
      print('Error initializing FeedFm: $e');
      return false;
    }
  }

  // ====================================
  // PLAYBACK CONTROLS
  // ====================================

  static Future<void> play() async {
    await _methodChannel.invokeMethod('play');
  }

  static Future<void> pause() async {
    await _methodChannel.invokeMethod('pause');
  }

  static Future<void> stop() async {
    await _methodChannel.invokeMethod('stop');
  }

  static Future<void> skip() async {
    await _methodChannel.invokeMethod('skip');
  }

  static Future<void> requestSkip() async {
    await _methodChannel.invokeMethod('requestSkip');
  }

  // New: toggle play/pause
  static Future<void> togglePlayPause() async {
    await _methodChannel.invokeMethod('togglePlayPause');
  }

  // ====================================
  // TRACK RATING
  // ====================================

  static Future<void> like() async {
    await _methodChannel.invokeMethod('like');
  }

  static Future<void> dislike() async {
    await _methodChannel.invokeMethod('dislike');
  }

  static Future<void> unlike() async {
    await _methodChannel.invokeMethod('unlike');
  }

  // ====================================
  // STATION MANAGEMENT
  // ====================================

  static Future<void> selectStationByIndex(int index) async {
    await _methodChannel.invokeMethod('selectStationByIndex', {'index': index});
  }

  static Future<void> selectStationById(String stationId) async {
    await _methodChannel.invokeMethod('selectStationById', {'stationId': stationId});
  }

  static Future<List<Station>> getStations() async {
    final result = await _methodChannel.invokeMethod('getStations');
    if (result is List) {
      return result.map((e) => Station.fromMap(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<Station?> getCurrentStation() async {
    final result = await _methodChannel.invokeMethod('getCurrentStation');
    if (result != null && result is Map) {
      return Station.fromMap(Map<String, dynamic>.from(result));
    }
    return null;
  }

  static Future<String> getActiveStationId() async {
    final result = await _methodChannel.invokeMethod('getActiveStationId');
    return result?.toString() ?? '';
  }

  // Autoplay preferences on station change
  static Future<void> setAutoplayOnStationChange(bool enabled) async {
    await _methodChannel.invokeMethod('setAutoplayOnStationChange', {'enabled': enabled});
  }

  // ====================================
  // TRACK INFORMATION
  // ====================================

  static Future<Play?> getCurrentTrack() async {
    final result = await _methodChannel.invokeMethod('getCurrentTrack');
    if (result != null && result['play'] != null) {
      return Play.fromMap(Map<String, dynamic>.from(result['play']));
    }
    return null;
  }

  // ====================================
  // PLAYER STATE
  // ====================================

  static Future<PlayerState> getPlaybackState() async {
    final result = await _methodChannel.invokeMethod('getPlaybackState');
    return _parsePlayerState(result.toString());
  }

  static Future<bool> canSkip() async {
    final result = await _methodChannel.invokeMethod('canSkip');
    return result == true;
  }

  static Future<bool> isAvailable() async {
    final result = await _methodChannel.invokeMethod('isAvailable');
    return result == true;
  }

  // ====================================
  // VOLUME CONTROL
  // ====================================

  static Future<void> setVolume(double volume) async {
    await _methodChannel.invokeMethod('setVolume', {'volume': volume});
  }

  static Future<double> getVolume() async {
    final result = await _methodChannel.invokeMethod('getVolume');
    return (result as num).toDouble();
  }

  // ====================================
  // CROSSFADES & TIMING
  // ====================================

  static Future<void> setMixCrossfade(bool enabled) async {
    await _methodChannel.invokeMethod('mixCrossfade', {'enabled': enabled});
  }

  static Future<void> setSecondsOfCrossfade(int seconds) async {
    await _methodChannel.invokeMethod('setSecondsOfCrossfade', {'seconds': seconds});
  }

  // New: get seconds of crossfade
  static Future<double> getSecondsOfCrossfade() async {
    final result = await _methodChannel.invokeMethod('getSecondsOfCrossfade');
    return (result as num).toDouble();
  }

  // New: position/duration snapshots
  static Future<int> getPosition() async {
    final result = await _methodChannel.invokeMethod('getPosition');
    return (result as num?)?.toInt() ?? 0;
  }

  static Future<int> getDuration() async {
    final result = await _methodChannel.invokeMethod('getDuration');
    return (result as num?)?.toInt() ?? 0;
  }

  // New: detect if native SDK supports seeking
  static Future<bool> supportsSeek() async {
    try {
      final result = await _methodChannel.invokeMethod('supportsSeek');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // New: seek to position (seconds)
  static Future<bool> seekTo(int seconds) async {
    try {
      final result = await _methodChannel.invokeMethod('seekTo', {'position': seconds});
      return result == true;
    } catch (e) {
      return false;
    }
  }

  // Convenience: relative seek by delta seconds (positive or negative)
  static Future<bool> seekBy(int deltaSeconds) async {
    try {
      final pos = await getPosition();
      final dur = await getDuration();
      int target = pos + deltaSeconds;
      if (target < 0) target = 0;
      if (dur > 0 && target > dur) target = dur;
      return await seekTo(target);
    } catch (_) {
      return false;
    }
  }

  // ====================================
  // ADVANCED FEATURES
  // ====================================

  static Future<String> getClientId() async {
    final result = await _methodChannel.invokeMethod('getClientId');
    return result?.toString() ?? '';
  }

  // ====================================
  // EVENT STREAMS
  // ====================================

  static Stream<PlayerStateEvent> get onStateChanged {
    _stateStream ??= _stateEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return PlayerStateEvent.fromMap(map);
    });
    return _stateStream!;
  }

  static Stream<Play> get onTrackChanged {
    _trackStream ??= _trackEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return Play.fromMap(map);
    });
    return _trackStream!;
  }

  static Stream<ProgressEvent> get onProgressChanged {
    _progressStream ??= _progressEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return ProgressEvent.fromMap(map);
    });
    return _progressStream!;
  }

  static Stream<SkipEvent> get onSkipStatusChanged {
    _skipStream ??= _skipEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return SkipEvent.fromMap(map);
    });
    return _skipStream!;
  }

  // New: Station changed stream
  static Stream<Station> get onStationChanged {
    _stationStream ??= _stationEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return Station.fromMap(map);
    });
    return _stationStream!;
  }

  // New: Error stream
  static Stream<FeedFmError> get onError {
    _errorStream ??= _errorEventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event);
      return FeedFmError.fromMap(map);
    });
    return _errorStream!;
  }

  // ====================================
  // HELPER METHODS
  // ====================================

  static PlayerState _parsePlayerState(String state) {
    switch (state.toUpperCase()) {
      case 'PLAYING':
        return PlayerState.playing;
      case 'PAUSED':
        return PlayerState.paused;
      case 'STOPPED':
        return PlayerState.stopped;
      case 'READY':
        return PlayerState.ready;
      case 'STALLED':
        return PlayerState.stalled;
      case 'REQUESTING_SKIP':
        return PlayerState.requestingSkip;
      case 'WAITING':
        return PlayerState.waiting;
      case 'UNAVAILABLE':
        return PlayerState.unavailable;
      default:
        return PlayerState.idle;
    }
  }
}

// ===================
// MODELS
// ===================

class Station {
  final int? index;
  final String id;
  final String name;
  final String description;

  Station({
    this.index,
    required this.id,
    required this.name,
    this.description = '',
  });

  factory Station.fromMap(Map<String, dynamic> map) {
    return Station(
      index: map['index'] as int?,
      id: map['id']?.toString() ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'index': index,
      'id': id,
      'name': name,
      'description': description,
    };
  }
}

class Play {
  final String id;
  final AudioFile audioFile;
  final StationDetail station;

  Play({required this.id, required this.audioFile, required this.station});

  factory Play.fromMap(Map<String, dynamic> map) {
    return Play(
      id: map['id']?.toString() ?? '',
      audioFile: AudioFile.fromMap(
        (map['audio_file'] as Map).cast<String, dynamic>(),
      ),
      station: StationDetail.fromMap(
        (map['station'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'audio_file': audioFile.toMap(),
      'station': station.toMap(),
    };
  }
}

class AudioFile {
  final String id;
  final int durationInSeconds;
  final String codec;
  final Track track;
  final Release release;
  final Artist artist;
  final String url;
  final int bitrate;
  final bool liked;
  final double replaygainTrackGain;
  final Extra extra;

  AudioFile({
    required this.id,
    required this.durationInSeconds,
    required this.codec,
    required this.track,
    required this.release,
    required this.artist,
    required this.url,
    required this.bitrate,
    required this.liked,
    required this.replaygainTrackGain,
    required this.extra,
  });

  factory AudioFile.fromMap(Map<String, dynamic> map) {
    return AudioFile(
      id: map['id']?.toString() ?? '',
      durationInSeconds: (map['duration_in_seconds'] ?? 0) is int
          ? map['duration_in_seconds']
          : (map['duration_in_seconds'] as num).toInt(),
      codec: map['codec']?.toString() ?? '',
      track: Track.fromMap((map['track'] as Map).cast<String, dynamic>()),
      release: Release.fromMap((map['release'] as Map).cast<String, dynamic>()),
      artist: Artist.fromMap((map['artist'] as Map).cast<String, dynamic>()),
      url: map['url']?.toString() ?? '',
      bitrate: (map['bitrate'] ?? 0) is int
          ? map['bitrate']
          : int.tryParse(map['bitrate']?.toString() ?? '0') ?? 0,
      liked: map['liked'] == true,
      replaygainTrackGain: (map['replaygain_track_gain'] ?? 0.0) is double
          ? map['replaygain_track_gain']
          : (map['replaygain_track_gain'] as num?)?.toDouble() ?? 0.0,
      extra: Extra.fromMap((map['extra'] as Map?)?.cast<String, dynamic>() ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'duration_in_seconds': durationInSeconds,
      'codec': codec,
      'track': track.toMap(),
      'release': release.toMap(),
      'artist': artist.toMap(),
      'url': url,
      'bitrate': bitrate,
      'liked': liked,
      'replaygain_track_gain': replaygainTrackGain,
      'extra': extra.toMap(),
    };
  }
}

class Track {
  final String id;
  final String title;

  Track({required this.id, required this.title});

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
    };
  }
}

class Artist {
  final String id;
  final String name;

  Artist({required this.id, required this.name});

  factory Artist.fromMap(Map<String, dynamic> map) {
    return Artist(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class Release {
  final String id;
  final String title;

  Release({required this.id, required this.title});

  factory Release.fromMap(Map<String, dynamic> map) {
    return Release(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
    };
  }
}

class Extra {
  final String artwork;
  final String image;
  final String backgroundImageUrl;
  final String caption;

  Extra({
    this.artwork = '',
    this.image = '',
    this.backgroundImageUrl = '',
    this.caption = '',
  });

  factory Extra.fromMap(Map<String, dynamic> map) {
    return Extra(
      artwork: map['artwork']?.toString() ?? '',
      image: map['image']?.toString() ?? '',
      backgroundImageUrl: map['background_image_url']?.toString() ?? '',
      caption: map['caption']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'artwork': artwork,
      'image': image,
      'background_image_url': backgroundImageUrl,
      'caption': caption,
    };
  }
}

class StationDetail {
  final String id;
  final String name;
  final double preGain;

  StationDetail({required this.id, required this.name, required this.preGain});

  factory StationDetail.fromMap(Map<String, dynamic> map) {
    return StationDetail(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      preGain: (map['pre_gain'] ?? 0.0) is double
          ? map['pre_gain']
          : double.tryParse(map['pre_gain']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pre_gain': preGain,
    };
  }
}

// ===================
// PLAYER STATE
// ===================

enum PlayerState {
  idle,
  ready,
  playing,
  paused,
  stopped,
  stalled,
  requestingSkip,
  waiting,
  unavailable,
}

// ===================
// EVENT MODELS
// ===================

class PlayerStateEvent {
  final String event;
  final PlayerState? state;
  final bool? available;

  PlayerStateEvent({
    required this.event,
    this.state,
    this.available,
  });

  factory PlayerStateEvent.fromMap(Map<String, dynamic> map) {
    return PlayerStateEvent(
      event: map['event'] as String,
      state: map['state'] != null
          ? FeedFm._parsePlayerState(map['state'] as String)
          : null,
      available: map['available'] as bool?,
    );
  }
}

class ProgressEvent {
  final int position;
  final int duration;

  ProgressEvent({
    required this.position,
    required this.duration,
  });

  factory ProgressEvent.fromMap(Map<String, dynamic> map) {
    return ProgressEvent(
      position: (map['position'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
    );
  }

  double get progress {
    if (duration == 0) return 0.0;
    return position / duration;
  }

  String get positionString {
    return _formatDuration(position);
  }

  String get durationString {
    return _formatDuration(duration);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class SkipEvent {
  final String event;
  final bool canSkip;

  SkipEvent({
    required this.event,
    required this.canSkip,
  });

  factory SkipEvent.fromMap(Map<String, dynamic> map) {
    return SkipEvent(
      event: map['event'] as String,
      canSkip: map['canSkip'] as bool? ?? false,
    );
  }
}
// New: Error event model
class FeedFmError {
  final String message;
  FeedFmError(this.message);
  factory FeedFmError.fromMap(Map<String, dynamic> map) => FeedFmError(map['message']?.toString() ?? '');
}
/// =================================================================///
// // import 'dart:async';
// //
// // import 'package:flutter/services.dart';
// //
// // enum PlayerState {
// //   idle,
// //   loading,
// //   playing,
// //   paused,
// //   stopped,
// //   error,
// // }
// //
// // class Track {
// //   final String title;
// //   final String artist;
// //   final String album;
// //   final String albumArtUrl;
// //   final int duration;
// //   final bool canSkip;
// //
// //   Track({
// //     required this.title,
// //     required this.artist,
// //     required this.album,
// //     required this.albumArtUrl,
// //     required this.duration,
// //     required this.canSkip,
// //   });
// //
// //   factory Track.fromMap(Map<String, dynamic> map) {
// //     return Track(
// //       title: map['title'] as String? ?? '',
// //       artist: map['artist'] as String? ?? '',
// //       album: map['album'] as String? ?? '',
// //       albumArtUrl: map['albumArtUrl'] as String? ?? '',
// //       duration: (map['duration'] as num?)?.toInt() ?? 0, // Fix: Handle double from native
// //       canSkip: map['canSkip'] as bool? ?? false,
// //     );
// //   }
// //
// //   @override
// //   String toString() {
// //     return 'Track(title: $title, artist: $artist, album: $album, albumArtUrl: $albumArtUrl, duration: $duration, canSkip: $canSkip)';
// //   }
// // }
// //
// // class Station {
// //   final int index;
// //   final String name;
// //   final String description;
// //
// //   Station({
// //     required this.index,
// //     required this.name,
// //     required this.description,
// //   });
// //
// //   factory Station.fromMap(Map<String, dynamic> map) {
// //     return Station(
// //       index: map['index'] as int? ?? 0,
// //       name: map['name'] as String? ?? '',
// //       description: map['description'] as String? ?? '',
// //     );
// //   }
// //
// //   @override
// //   String toString() {
// //     return 'Station(index: $index, name: $name, description: $description)';
// //   }
// // }
// //
// // class FeedFm {
// //   static const MethodChannel _methodChannel = MethodChannel('feed_fm');
// //   static const EventChannel _eventChannel = EventChannel('feed_fm_events');
// //
// //   static Stream<PlayerStateEvent>? _onStateChanged;
// //   static Stream<TrackChangedEvent>? _onTrackChanged;
// //   // Removed _onProgressChanged as progress will be handled on Dart side
// //
// //   static Future<void> initialize(String token, String secret) async {
// //     await _methodChannel.invokeMethod('initialize', {
// //       'token': token,
// //       'secret': secret,
// //     });
// //   }
// //
// //   static Future<void> play() async {
// //     await _methodChannel.invokeMethod('play');
// //   }
// //
// //   static Future<void> pause() async {
// //     await _methodChannel.invokeMethod('pause');
// //   }
// //
// //   static Future<void> skip() async {
// //     await _methodChannel.invokeMethod('skip');
// //   }
// //
// //   static Future<void> stop() async {
// //     await _methodChannel.invokeMethod('stop');
// //   }
// //
// //   static Future<List<Station>> getStations() async {
// //     final List<dynamic>? stationsMap = await _methodChannel.invokeMethod('getStations');
// //     if (stationsMap == null) {
// //       return [];
// //     }
// //     return stationsMap.map((e) => Station.fromMap(e as Map<String, dynamic>)).toList();
// //   }
// //
// //   static Future<void> selectStation(int index) async {
// //     await _methodChannel.invokeMethod('selectStation', {'index': index});
// //   }
// //
// //   static Stream<PlayerStateEvent> get onStateChanged {
// //     _onStateChanged ??= _eventChannel.receiveBroadcastStream().where((event) => event['eventType'] == 'stateChanged').map((event) {
// //       return PlayerStateEvent.fromMap(event as Map<String, dynamic>);
// //     });
// //     return _onStateChanged!;
// //   }
// //
// //   static Stream<TrackChangedEvent> get onTrackChanged {
// //     _onTrackChanged ??= _eventChannel.receiveBroadcastStream().where((event) => event['eventType'] == 'trackChanged').map((event) {
// //       return TrackChangedEvent.fromMap(event as Map<String, dynamic>);
// //     });
// //     return _onTrackChanged!;
// //   }
// // }
// //
// // class PlayerStateEvent {
// //   final PlayerState? state;
// //
// //   PlayerStateEvent({this.state});
// //
// //   factory PlayerStateEvent.fromMap(Map<String, dynamic> map) {
// //     PlayerState? state;
// //     switch (map['state']) {
// //       case 'idle':
// //         state = PlayerState.idle;
// //         break;
// //       case 'loading':
// //         state = PlayerState.loading;
// //         break;
// //       case 'playing':
// //         state = PlayerState.playing;
// //         break;
// //       case 'paused':
// //         state = PlayerState.paused;
// //         break;
// //       case 'stopped':
// //         state = PlayerState.stopped;
// //         break;
// //       case 'error':
// //         state = PlayerState.error;
// //         break;
// //     }
// //     return PlayerStateEvent(state: state);
// //   }
// // }
// //
// // class TrackChangedEvent {
// //   final Track? track;
// //
// //   TrackChangedEvent({this.track});
// //
// //   factory TrackChangedEvent.fromMap(Map<String, dynamic> map) {
// //     return TrackChangedEvent(track: map['track'] != null ? Track.fromMap(map['track'] as Map<String, dynamic>) : null);
// //   }
// // }
// //
// //
// //
//
// import 'dart:async';
// import 'package:flutter/services.dart';
//
// class FeedFm {
//   static const MethodChannel _methodChannel = MethodChannel('feed_fm');
//   static const EventChannel _stateEventChannel = EventChannel('feed_fm/state_events');
//   static const EventChannel _trackEventChannel = EventChannel('feed_fm/track_events');
//   static const EventChannel _progressEventChannel = EventChannel('feed_fm/progress_events');
//
//   // Streams for real-time updates
//   static Stream<PlayerStateEvent>? _stateStream;
//   static Stream<TrackEvent>? _trackStream;
//   static Stream<ProgressEvent>? _progressStream;
//
//   /// Initialize the Feed.fm player with your credentials
//   static Future<bool> initialize({
//     required String token,
//     required String secret,
//   }) async {
//     try {
//       final result = await _methodChannel.invokeMethod('initialize', {
//         'token': token,
//         'secret': secret,
//       });
//       return result == true;
//     } catch (e) {
//       print('Error initializing FeedFm: $e');
//       return false;
//     }
//   }
//
//   /// Start playing music
//   static Future<void> play() async {
//     await _methodChannel.invokeMethod('play');
//   }
//
//   /// Pause playback
//   static Future<void> pause() async {
//     await _methodChannel.invokeMethod('pause');
//   }
//
//   /// Stop playback
//   static Future<void> stop() async {
//     await _methodChannel.invokeMethod('stop');
//   }
//
//   /// Skip to next track
//   static Future<void> skip() async {
//     await _methodChannel.invokeMethod('skip');
//   }
//
//   /// Like the current track
//   static Future<void> like() async {
//     await _methodChannel.invokeMethod('like');
//   }
//
//   /// Dislike the current track (will skip)
//   static Future<void> dislike() async {
//     await _methodChannel.invokeMethod('dislike');
//   }
//
//   /// Select a station by index
//   static Future<void> selectStationByIndex(int index) async {
//     await _methodChannel.invokeMethod('selectStationByIndex', {'index': index});
//   }
//
//   /// Select a station by ID/name
//   static Future<void> selectStationById(String stationId) async {
//     await _methodChannel.invokeMethod('selectStationById', {'stationId': stationId});
//   }
//
//   /// Get list of available stations
//   static Future<List<Station>> getStations() async {
//     final result = await _methodChannel.invokeMethod('getStations');
//     if (result is List) {
//       return result.map((e) => Station.fromMap(Map<String, dynamic>.from(e))).toList();
//     }
//     return [];
//   }
//
//   /// Get current station
//   static Future<Station?> getCurrentStation() async {
//     final result = await _methodChannel.invokeMethod('getCurrentStation');
//     if (result != null && result is Map) {
//       return Station.fromMap(Map<String, dynamic>.from(result));
//     }
//     return null;
//   }
//
//   /// Get current track information
//   static Future<Track> getCurrentTrack() async {
//     final result = await _methodChannel.invokeMethod('getCurrentTrack');
//     print('getCurrentTrack result: $result');
//     return Track.fromMap(Map<String, dynamic>.from(result));
//   }
//
//   /// Get current playback state
//   static Future<PlayerState> getPlaybackState() async {
//     final result = await _methodChannel.invokeMethod('getPlaybackState');
//     return _parsePlayerState(result.toString());
//   }
//
//   /// Check if current track can be skipped
//   static Future<bool> canSkip() async {
//     final result = await _methodChannel.invokeMethod('canSkip');
//     return result == true;
//   }
//
//   /// Set volume (0.0 to 1.0)
//   static Future<void> setVolume(double volume) async {
//     await _methodChannel.invokeMethod('setVolume', {'volume': volume});
//   }
//
//   /// Get current volume
//   static Future<double> getVolume() async {
//     final result = await _methodChannel.invokeMethod('getVolume');
//     return (result as num).toDouble();
//   }
//
//   /// Get maximum skip count per hour
//   static Future<int> getMaxSkipCount() async {
//     final result = await _methodChannel.invokeMethod('getMaxSkipCount');
//     return result as int;
//   }
//
//   /// Get current skip count
//   static Future<int> getSkipCount() async {
//     final result = await _methodChannel.invokeMethod('getSkipCount');
//     return result as int;
//   }
//
//   /// Check if player is available (has content to play)
//   static Future<bool> isAvailable() async {
//     final result = await _methodChannel.invokeMethod('isAvailable');
//     return result == true;
//   }
//
//   // =================================================================
//   // EVENT STREAMS - Listen to real-time updates
//   // =================================================================
//
//   /// Stream of player state changes (play, pause, buffering, etc.)
//   static Stream<PlayerStateEvent> get onStateChanged {
//     _stateStream ??= _stateEventChannel.receiveBroadcastStream().map((event) {
//       final map = Map<String, dynamic>.from(event);
//       return PlayerStateEvent.fromMap(map);
//     });
//     return _stateStream!;
//   }
//
//   /// Stream of track changes
//   static Stream<TrackEvent> get onTrackChanged {
//     _trackStream ??= _trackEventChannel.receiveBroadcastStream().map((event) {
//       final map = Map<String, dynamic>.from(event);
//       return TrackEvent.fromMap(map);
//     });
//     return _trackStream!;
//   }
//
//   /// Stream of playback progress updates
//   static Stream<ProgressEvent> get onProgressChanged {
//     _progressStream ??= _progressEventChannel.receiveBroadcastStream().map((event) {
//       final map = Map<String, dynamic>.from(event);
//       return ProgressEvent.fromMap(map);
//     });
//     return _progressStream!;
//   }
//
//   static PlayerState _parsePlayerState(String state) {
//     switch (state.toUpperCase()) {
//       case 'PLAYING':
//         return PlayerState.playing;
//       case 'PAUSED':
//         return PlayerState.paused;
//       case 'STOPPED':
//         return PlayerState.stopped;
//       case 'READY':
//         return PlayerState.ready;
//       case 'STALLED':
//         return PlayerState.stalled;
//       case 'REQUESTING_SKIP':
//         return PlayerState.requestingSkip;
//       case 'WAITING':
//         return PlayerState.waiting;
//       case 'UNAVAILABLE':
//         return PlayerState.unavailable;
//       default:
//         return PlayerState.idle;
//     }
//   }
// }
//
// // =================================================================
// // DATA MODELS
// // =================================================================
//
// class Station {
//   final int? index;
//   final String name;
//   final String description;
//
//   Station({
//     this.index,
//     required this.name,
//     this.description = '',
//   });
//
//   factory Station.fromMap(Map<String, dynamic> map) {
//     return Station(
//       index: map['index'] as int?,
//       name: map['name'] as String? ?? '',
//       description: map['description'] as String? ?? '',
//     );
//   }
// }
//
// // class Track {
// //
// //   final String title;
// //   final String artist;
// //   final String album;
// //   final String albumArtUrl;
// //   final int duration;
// //   final bool canSkip;
// //
// //   Track({
// //
// //     required this.title,
// //     required this.artist,
// //     required this.album,
// //     this.albumArtUrl = '',
// //     this.duration = 0,
// //     this.canSkip = false,
// //   });
// //
// //   factory Track.fromMap(Map<String, dynamic> map) {
// //     return Track(
// //
// //       title: map['title'] as String? ?? '',
// //       artist: map['artist'] as String? ?? '',
// //       album: map['album'] as String? ?? '',
// //       albumArtUrl: map['albumArtUrl'] as String? ?? '',
// //       duration: (map['duration'] as num?)?.toInt() ?? 0, // Fix: Handle double from native
// //
// //       canSkip: map['canSkip'] as bool? ?? false,
// //     );
// //   }
// // }
//
// class Track {
//   final String id;
//   final AudioFile audioFile;
//   final StationName station;
//
//   Track({
//     required this.id,
//     required this.audioFile,
//     required this.station,
//   });
//
//   factory Track.fromMap(Map<String, dynamic> map) {
//     return Play(
//       id: map['id'] as String? ?? '',
//       audioFile: AudioFile.fromMap(map['audio_file'] as Map<String, dynamic>? ?? {}),
//       station: Station.fromMap(map['station'] as Map<String, dynamic>? ?? {}),
//     );
//   }
// }
//
// class AudioFile {
//   final String id;
//   final int durationInSeconds;
//   final String codec;
//   final Track track;
//   final Release release;
//   final Artist artist;
//   final String url;
//   final int bitrate;
//   final bool liked;
//   final double replaygainTrackGain;
//   final Extra extra; // For artwork, images, etc.
//
//   AudioFile({
//     required this.id,
//     required this.durationInSeconds,
//     required this.codec,
//     required this.track,
//     required this.release,
//     required this.artist,
//     required this.url,
//     required this.bitrate,
//     required this.liked,
//     required this.replaygainTrackGain,
//     required this.extra,
//   });
//
//   factory AudioFile.fromMap(Map<String, dynamic> map) {
//     return AudioFile(
//       id: map['id'] as String? ?? '',
//       durationInSeconds: (map['duration_in_seconds'] as num?)?.toInt() ?? 0,
//       codec: map['codec'] as String? ?? '',
//       track: Track.fromMap(map['track'] as Map<String, dynamic>? ?? {}),
//       release: Release.fromMap(map['release'] as Map<String, dynamic>? ?? {}),
//       artist: Artist.fromMap(map['artist'] as Map<String, dynamic>? ?? {}),
//       url: map['url'] as String? ?? '',
//       bitrate: map['bitrate'] as int? ?? 0,
//       liked: map['liked'] as bool? ?? false,
//       replaygainTrackGain: (map['replaygain_track_gain'] as num?)?.toDouble() ?? 0.0,
//       extra: Extra.fromMap(map['extra'] as Map<String, dynamic>? ?? {}),
//     );
//   }
// }
//
// class Track {
//   final String id;
//   final String title;
//
//   Track({required this.id, required this.title});
//
//   factory Track.fromMap(Map<String, dynamic> map) {
//     return Track(
//       id: map['id'] as String? ?? '',
//       title: map['title'] as String? ?? '',
//     );
//   }
// }
//
// class Release {
//   final String id;
//   final String title;
//
//   Release({required this.id, required this.title});
//
//   factory Release.fromMap(Map<String, dynamic> map) {
//     return Release(
//       id: map['id'] as String? ?? '',
//       title: map['title'] as String? ?? '',
//     );
//   }
//
//   Map<String, dynamic> toMap() {
//     return {
//       'id': id,
//       'title': title,
//     };
//   }
// }
//
// class Artist {
//   final String id;
//   final String name;
//
//   Artist({required this.id, required this.name});
//
//   factory Artist.fromMap(Map<String, dynamic> map) {
//     return Artist(
//       id: map['id'] as String? ?? '',
//       name: map['name'] as String? ?? '',
//     );
//   }
//
//   Map<String, dynamic> toMap() {
//     return {
//       'id': id,
//       'name': name,
//     };
//   }
// }
//
// class Extra {
//   final String artwork;
//   final String image;
//   final String backgroundImageUrl;
//   final String caption;
//
//   Extra({
//     this.artwork = '',
//     this.image = '',
//     this.backgroundImageUrl = '',
//     this.caption = '',
//   });
//
//   factory Extra.fromMap(Map<String, dynamic> map) {
//     return Extra(
//       artwork: map['artwork'] as String? ?? '',
//       image: map['image'] as String? ?? '',
//       backgroundImageUrl: map['background_image_url'] as String? ?? '',
//       caption: map['caption'] as String? ?? '',
//     );
//   }
// }
//
// class StationName {
//   final String id;
//   final String name;
//   final int preGain;
//
//   StationName({
//     required this.id,
//     required this.name,
//     required this.preGain,
//   });
//
//   factory StationName.fromMap(Map<String, dynamic> map) {
//     return StationName(
//       id: map['id'] as String? ?? '',
//       name: map['name'] as String? ?? '',
//       preGain: map['pre_gain'] as int? ?? 0,
//     );
//   }
// }
//
//
// enum PlayerState {
//   idle,
//   ready,
//   playing,
//   paused,
//   stopped,
//   stalled,
//   requestingSkip,
//   waiting,
//   unavailable,
// }
//
// class PlayerStateEvent {
//   final String event;
//   final PlayerState? state;
//   final bool? available;
//
//   PlayerStateEvent({
//     required this.event,
//     this.state,
//     this.available,
//   });
//
//   factory PlayerStateEvent.fromMap(Map<String, dynamic> map) {
//     return PlayerStateEvent(
//       event: map['event'] as String,
//       state: map['state'] != null
//           ? FeedFm._parsePlayerState(map['state'] as String)
//           : null,
//       available: map['available'] as bool?,
//     );
//   }
// }
//
// class TrackEvent {
//   final String event;
//   final Track? track;
//
//   TrackEvent({
//     required this.event,
//     this.track,
//   });
//
//   factory TrackEvent.fromMap(Map<String, dynamic> map) {
//     return TrackEvent(
//       event: map['event'] as String,
//       track: map['track'] != null
//           ? Track.fromMap(Map<String, dynamic>.from(map['track']))
//           : null,
//     );
//   }
// }
//
// class ProgressEvent {
//   final int position;
//   final int duration;
//
//   ProgressEvent({
//     required this.position,
//     required this.duration,
//   });
//
//   factory ProgressEvent.fromMap(Map<String, dynamic> map) {
//     return ProgressEvent(
//       position: (map['position'] as num?)?.toInt() ?? 0,
//       duration: (map['duration'] as num?)?.toInt() ?? 0,
//     );
//   }
//
//   double get progress {
//     if (duration == 0) return 0.0;
//     return position / duration;
//   }
// }

