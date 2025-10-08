import 'dart:async';

import 'package:feed_fm/feed_fm.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FeedFM Demo',
      home: const MusicPlayerPage(),
      theme: ThemeData.dark(useMaterial3: false),
    );
  }
}

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({Key? key}) : super(key: key);

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  // Core state
  Play? currentTrack;
  PlayerState playerState = PlayerState.idle;
  List<Station> stations = [];
  Station? currentStation;

  // Realtime/derived state
  bool canSkip = false;
  int currentPosition = 0;
  int duration = 0;
  double get progress => duration == 0 ? 0.0 : (currentPosition / duration).clamp(0, 1).toDouble();
  // Seek UI state
  bool _isSeeking = false;
  double _pendingProgress = 0.0;

  // Settings/state
  double volume = 1.0;
  double crossfadeSeconds = 0.0;
  bool autoplayOnStationChange = true;
  String clientId = '';
  String activeStationId = '';
  String? lastErrorMessage;

  // Subscriptions
  StreamSubscription? _stateSub;
  StreamSubscription? _trackSub;
  StreamSubscription? _progressSub;
  StreamSubscription? _skipSub;
  StreamSubscription? _stationSub;
  StreamSubscription? _errorSub;

  // Polling safety (light refresh for snapshots)
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _setupListeners();
    _startPolling();
  }

  Future<void> _initializePlayer() async {
    // TODO: Replace with your real credentials
    final ok = await FeedFm.initialize(token: 'demo', secret: 'demo');
    if (!ok) {
      _showSnack('Failed to initialize Feed.fm');
      return;
    }

    // Load initial data
    await _refreshStations();
    await _refreshCurrentStation();
    await _refreshCurrentTrack();
    await _refreshPlayerState();
    await _refreshSkipStatus();

    // Settings/init values
    final v = await FeedFm.getVolume();
    final cf = await FeedFm.getSecondsOfCrossfade();
    final cid = await FeedFm.getClientId();
    final asid = await FeedFm.getActiveStationId();

    setState(() {
      volume = v;
      crossfadeSeconds = cf;
      clientId = cid;
      activeStationId = asid;
    });

    // Ensure autoplay preference on station change
    await FeedFm.setAutoplayOnStationChange(autoplayOnStationChange);
  }

  void _setupListeners() {
    _stateSub = FeedFm.onStateChanged.listen((evt) {
      if (evt.state != null) {
        setState(() => playerState = evt.state!);
      }
    });

    _trackSub = FeedFm.onTrackChanged.listen((play) {
      setState(() => currentTrack = play);
    });

    _progressSub = FeedFm.onProgressChanged.listen((p) {
      setState(() {
        currentPosition = p.position;
        duration = p.duration;
      });
    });

    _skipSub = FeedFm.onSkipStatusChanged.listen((evt) {
      setState(() => canSkip = evt.canSkip);
    });

    _stationSub = FeedFm.onStationChanged.listen((st) async {
      setState(() => currentStation = st);
      activeStationId = await FeedFm.getActiveStationId();
      if (!mounted) return;
      _showSnack('Station changed to: ${st.name}');
    });

    _errorSub = FeedFm.onError.listen((err) {
      setState(() => lastErrorMessage = err.message);
      _showSnack('Error: ${err.message}');
    });
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      // Light snapshot refresh as a backup
      await _refreshCurrentTrack();
      await _refreshPlayerState();
      await _refreshSkipStatus();
    });
  }

  Future<void> _refreshStations() async {
    final list = await FeedFm.getStations();
    setState(() => stations = list);
  }

  Future<void> _refreshCurrentStation() async {
    final st = await FeedFm.getCurrentStation();
    setState(() => currentStation = st);
    activeStationId = await FeedFm.getActiveStationId();
  }

  Future<void> _refreshCurrentTrack() async {
    final play = await FeedFm.getCurrentTrack();
    setState(() => currentTrack = play);
  }

  Future<void> _refreshPlayerState() async {
    final st = await FeedFm.getPlaybackState();
    setState(() => playerState = st);
  }

  Future<void> _refreshSkipStatus() async {
    final s = await FeedFm.canSkip();
    setState(() => canSkip = s);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _trackSub?.cancel();
    _progressSub?.cancel();
    _skipSub?.cancel();
    _stationSub?.cancel();
    _errorSub?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  // UI helpers
  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _stateText() {
    switch (playerState) {
      case PlayerState.playing:
        return '● PLAYING';
      case PlayerState.paused:
        return '⏸ PAUSED';
      case PlayerState.stalled:
        return '⏳ BUFFERING...';
      case PlayerState.requestingSkip:
        return '⏭ SKIPPING...';
      case PlayerState.unavailable:
        return '⚠ UNAVAILABLE';
      case PlayerState.ready:
        return '✓ READY';
      default:
        return 'IDLE';
    }
  }

  Color _stateColor() {
    switch (playerState) {
      case PlayerState.playing:
        return Colors.green;
      case PlayerState.paused:
        return Colors.orange;
      case PlayerState.stalled:
      case PlayerState.requestingSkip:
        return Colors.yellow;
      case PlayerState.unavailable:
        return Colors.red;
      case PlayerState.ready:
        return Colors.blue;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final artUrl = currentTrack?.audioFile.extra.backgroundImageUrl ?? '';
    final title = currentTrack?.audioFile.track.title ?? 'No Track Playing';
    final artist = currentTrack?.audioFile.artist.name ?? '';
    final release = currentTrack?.audioFile.release.title ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('FeedFM Player'),
        backgroundColor: Colors.grey[900],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _openStationPicker,
          ),
        ],
      ),
      body: Column(
        children: [
          // Station Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              currentStation?.name.isNotEmpty == true ? currentStation!.name : 'No Station Selected',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),

          // Artwork
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[800],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: artUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          artUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderArt(),
                        ),
                      )
                    : _placeholderArt(),
              ),
            ),
          ),

          // Track Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  artist,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  release,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SliderTheme(
                  data: const SliderThemeData(trackHeight: 4),
                  child: Slider(
                    value: (_isSeeking ? _pendingProgress : progress).clamp(0.0, 1.0),
                    onChanged: duration > 0
                        ? (val) {
                            setState(() {
                              _isSeeking = true;
                              _pendingProgress = val.clamp(0.0, 1.0);
                            });
                          }
                        : null,
                    onChangeEnd: duration > 0
                        ? (val) async {
                            final targetSeconds = (val.clamp(0.0, 1.0) * duration).round();
                            final ok = await FeedFm.seekTo(targetSeconds);
                            if (!mounted) return;
                            if (ok) {
                              setState(() {
                                currentPosition = targetSeconds;
                              });
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Seek not supported by this SDK version')),
                              );
                            }
                            setState(() {
                              _isSeeking = false;
                            });
                          }
                        : null,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_isSeeking ? ( (_pendingProgress * duration).round() ) : currentPosition), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const Text('⏱', style: TextStyle(color: Colors.white24, fontSize: 10)),
                      Text(_fmt(duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Controls row
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.thumb_down_alt_outlined),
                  color: Colors.white70,
                  onPressed: () async {
                    await FeedFm.dislike();
                    _showSnack('Disliked');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  color: Colors.white,
                  iconSize: 44,
                  onPressed: playerState == PlayerState.playing ? () async => FeedFm.pause() : null,
                ),
                IconButton(
                  icon: Icon(playerState == PlayerState.playing ? Icons.pause : Icons.play_arrow),
                  color: Colors.white,
                  iconSize: 56,
                  onPressed: () async => FeedFm.togglePlayPause(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: canSkip ? Colors.white : Colors.white24,
                  iconSize: 44,
                  onPressed: canSkip ? () async => FeedFm.skip() : null,
                ),
                IconButton(
                  icon: const Icon(Icons.thumb_up_alt_outlined),
                  color: Colors.white70,
                  onPressed: () async {
                    await FeedFm.like();
                    _showSnack('Liked');
                  },
                ),
              ],
            ),
          ),

          // Seek controls (-15s / +15s)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: duration > 0 ? () async {
                    final ok = await FeedFm.seekBy(-15);
                    if (ok) {
                      final p = await FeedFm.getPosition();
                      if (!mounted) return;
                      setState(() => currentPosition = p);
                    } else {
                      _showSnack('Seek not supported');
                    }
                  } : null,
                  icon: const Icon(Icons.replay_10),
                  label: const Text('-15s'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: duration > 0 ? () async {
                    final ok = await FeedFm.seekBy(15);
                    if (ok) {
                      final p = await FeedFm.getPosition();
                      if (!mounted) return;
                      setState(() => currentPosition = p);
                    } else {
                      _showSnack('Seek not supported');
                    }
                  } : null,
                  icon: const Icon(Icons.forward_10),
                  label: const Text('+15s'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ],
            ),
          ),

          // Volume & Crossfade
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Volume', style: TextStyle(color: Colors.white70)),
                    Text(volume.toStringAsFixed(2), style: const TextStyle(color: Colors.white54)),
                  ],
                ),
                Slider(
                  value: volume.clamp(0.0, 1.0),
                  min: 0,
                  max: 1,
                  onChanged: (v) async {
                    setState(() => volume = v);
                    await FeedFm.setVolume(v);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Crossfade (s)', style: TextStyle(color: Colors.white70)),
                    Text(crossfadeSeconds.toStringAsFixed(0), style: const TextStyle(color: Colors.white54)),
                  ],
                ),
                Slider(
                  value: crossfadeSeconds.clamp(0, 10),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (v) async {
                    setState(() => crossfadeSeconds = v);
                    await FeedFm.setSecondsOfCrossfade(v.round());
                  },
                ),
              ],
            ),
          ),

          // State indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _stateText(),
              style: TextStyle(color: _stateColor(), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _placeholderArt() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.purple[700]!, Colors.pink[700]!],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note, size: 120, color: Colors.white30),
      ),
    );
  }

  Future<void> _openStationPicker() async {
    await showModalBottomSheet(

      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                const Text('Select Station', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      final st = stations[index];
                      final isSelected = st.name == currentStation?.name;
                      return ListTile(
                        title: Text(
                          st.name,
                          style: TextStyle(
                            color: isSelected ? Colors.purple[300] : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: st.description.isNotEmpty ? Text(st.description, style: const TextStyle(color: Colors.white54)) : null,
                        trailing: isSelected ? Icon(Icons.check_circle, color: Colors.purple[300]) : null,
                        onTap: () async {
                          await FeedFm.selectStationByIndex(index);
                          await _refreshCurrentStation();
                          if (mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Autoplay on station change', style: TextStyle(color: Colors.white70)),
                    Switch(
                      value: autoplayOnStationChange,
                      onChanged: (v) async {
                        setState(() => autoplayOnStationChange = v);
                        await FeedFm.setAutoplayOnStationChange(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Client ID: $clientId', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Text('Active Station ID: $activeStationId', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (lastErrorMessage?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('Last error: $lastErrorMessage', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async => FeedFm.requestSkip(),
                      icon: const Icon(Icons.forward_5),
                      label: const Text('Request Skip'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async => FeedFm.unlike(),
                      icon: const Icon(Icons.thumb_down),
                      label: const Text('Unlike (clear like)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

///============================= working code latest================================//
// import 'dart:async';
//
// import 'package:feed_fm/feed_fm.dart';
// import 'package:feed_fm/feed_fm_data_model.dart' hide Track, Station;
// import 'package:feed_fm/feed_fm_public_interface.dart' hide FeedFm;
// import 'package:flutter/material.dart';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'FeedFM Demo',
//       home: MusicPlayerPage(),
//     );
//   }
// }
//
// class MusicPlayerPage extends StatefulWidget {
//   const MusicPlayerPage({Key? key}) : super(key: key);
//
//   @override
//   State<MusicPlayerPage> createState() => _MusicPlayerPageState();
// }
//
// class _MusicPlayerPageState extends State<MusicPlayerPage> {
//   Play? currentTrack;
//   PlayerState playerState = PlayerState.idle;
//   List<Station> stations = [];
//   Station? currentStation;
//   bool canSkip = false;
//   double progress = 0.0;
//   int currentPosition = 0;
//   int duration = 0;
//
//   StreamSubscription? _stateSubscription;
//   StreamSubscription? _trackSubscription;
//   StreamSubscription? _progressSubscription;
//   Timer? _pollingTimer;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializePlayer();
//     _setupListeners();
//     _startPolling();
//   }
//
//   Future<void> _initializePlayer() async {
//     // Replace with your actual Feed.fm credentials
//     final success = await FeedFm.initialize(
//       token: 'demo',
//       secret: 'demo',
//     );
//
//     if (success) {
//       await _loadStations();
//       await _updateCurrentTrack();
//       await _updatePlayerState();
//     } else {
//       _showError('Failed to initialize player');
//     }
//   }
//
//   void _setupListeners() {
//     // Listen to state changes
//     _stateSubscription = FeedFm.onStateChanged.listen((event) {
//       if (event.state != null) {
//         setState(() {
//           playerState = event.state!;
//         });
//       }
//     });
//
//     // Listen to track changes
//     _trackSubscription = FeedFm.onTrackChanged.listen((event) {
//       if (event.audioFile.id != null) {
//         print('Track changed: ${event.toString()}');
//         setState(() {
//           currentTrack = event;
//         });
//         _updateCanSkip();
//       }
//     });
//
//     // Listen to progress updates
//     _progressSubscription = FeedFm.onProgressChanged.listen((event) {
//       setState(() {
//         currentPosition = event.position;
//         duration = event.duration;
//         progress = event.progress;
//       });
//     });
//   }
//
//   Future<void> _loadStations() async {
//     final stationList = await FeedFm.getStations();
//     setState(() {
//       stations = stationList;
//     });
//
//     if (stations.isNotEmpty) {
//       await FeedFm.selectStationByIndex(0);
//       await _updateCurrentStation();
//     }
//   }
//
//   Future<void> _updateCurrentTrack() async {
//     final track = await FeedFm.getCurrentTrack();
//     setState(() {
//       currentTrack = track;
//     });
//     await _updateCanSkip();
//   }
//
//   Future<void> _updatePlayerState() async {
//     final state = await FeedFm.getPlaybackState();
//     setState(() {
//       playerState = state;
//     });
//   }
//
//   Future<void> _updateCurrentStation() async {
//     final station = await FeedFm.getCurrentStation();
//     setState(() {
//       currentStation = station;
//     });
//   }
//
//   Future<void> _updateCanSkip() async {
//     final skip = await FeedFm.canSkip();
//     setState(() {
//       canSkip = skip;
//     });
//   }
//
//   void _showError(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message)),
//     );
//   }
//
//   String _formatDuration(int seconds) {
//     final minutes = seconds ~/ 60;
//     final secs = seconds % 60;
//     return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
//   }
//
//   void _startPolling() {
//     // Poll every second to update track info and state
//     _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
//       await _updateCurrentTrack();
//       await _updatePlayerState();
//       await _updateCanSkip();
//     });
//   }
//
//   @override
//   void dispose() {
//     _stateSubscription?.cancel();
//     _trackSubscription?.cancel();
//     _progressSubscription?.cancel();
//     _pollingTimer?.cancel();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: const Text('Music Player'),
//         backgroundColor: Colors.grey[900],
//         elevation: 0,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.list),
//             onPressed: () => _showStationPicker(),
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           // Station Info
//           Container(
//             padding: const EdgeInsets.all(16),
//             child: Text(
//               currentStation?.name ?? 'No Station Selected',
//               style: const TextStyle(
//                 color: Colors.white70,
//                 fontSize: 16,
//               ),
//             ),
//           ),
//
//           // Album Art
//           Expanded(
//             child: Center(
//               child: Container(
//                 width: 300,
//                 height: 300,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(12),
//                   color: Colors.grey[800],
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.5),
//                       blurRadius: 20,
//                       spreadRadius: 5,
//                     ),
//                   ],
//                 ),
//                 child: currentTrack?.audioFile?.extra?.backgroundImageUrl != null ?ClipRRect(
//                   borderRadius: BorderRadius.circular(12),
//                   child: Image.network(
//                    currentTrack!.audioFile.extra.backgroundImageUrl,
//                     fit: BoxFit.cover,
//                     errorBuilder: (context, error, stackTrace) =>
//                         _buildPlaceholderArt(),
//                   ),
//                 )
//                     : _buildPlaceholderArt(),
//               ),
//             ),
//           ),
//
//           // Track Info
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//             child: Column(
//               children: [
//                 Text(
//                   currentTrack?.audioFile?.track?.title ?? 'No Track Playing',
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 24,
//                     fontWeight: FontWeight.bold,
//                   ),
//                   textAlign: TextAlign.center,
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   currentTrack?.audioFile?.artist.name ?? '',
//                   style: const TextStyle(
//                     color: Colors.white70,
//                     fontSize: 18,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   currentTrack?.audioFile?.release?.title ?? '',
//                   style: const TextStyle(
//                     color: Colors.white54,
//                     fontSize: 14,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//               ],
//             ),
//           ),
//
//           // Progress Bar
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24),
//             child: Column(
//               children: [
//                 SliderTheme(
//                   data: SliderThemeData(
//                     thumbShape: const RoundSliderThumbShape(
//                       enabledThumbRadius: 6,
//                     ),
//                     overlayShape: const RoundSliderOverlayShape(
//                       overlayRadius: 14,
//                     ),
//                     trackHeight: 4,
//                   ),
//                   child: Slider(
//                     value: progress.clamp(0.0, 1.0),
//                     onChanged: null, // Feed.fm doesn't support seeking
//                     activeColor: Colors.white,
//                     inactiveColor: Colors.white24,
//                   ),
//                 ),
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 8),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       Text(
//                         _formatDuration(currentPosition),
//                         style: const TextStyle(
//                           color: Colors.white54,
//                           fontSize: 12,
//                         ),
//                       ),
//                       Text(
//                         _formatDuration(duration),
//                         style: const TextStyle(
//                           color: Colors.white54,
//                           fontSize: 12,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//
//           // Control Buttons
//           Padding(
//             padding: const EdgeInsets.all(24),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 // Dislike Button
//                 IconButton(
//                   icon: const Icon(Icons.thumb_down_outlined),
//                   iconSize: 32,
//                   color: Colors.white70,
//                   onPressed: () async {
//                     await FeedFm.dislike();
//                     _showError('Track disliked');
//                   },
//                 ),
//
//                 // Previous (disabled for Feed.fm)
//                 IconButton(
//                   icon: const Icon(Icons.skip_previous),
//                   iconSize: 48,
//                   color: Colors.white24,
//                   onPressed: null,
//                 ),
//
//                 // Play/Pause Button
//                 Container(
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     gradient: LinearGradient(
//                       colors: [Colors.purple[400]!, Colors.pink[400]!],
//                     ),
//                     boxShadow: [
//                       BoxShadow(
//                         color: Colors.purple.withOpacity(0.4),
//                         blurRadius: 20,
//                         spreadRadius: 2,
//                       ),
//                     ],
//                   ),
//                   child: IconButton(
//                     icon: Icon(
//                       playerState == PlayerState.playing
//                           ? Icons.pause
//                           : Icons.play_arrow,
//                     ),
//                     iconSize: 48,
//                     color: Colors.white,
//                     onPressed: () async {
//                       if (playerState == PlayerState.playing) {
//                         await FeedFm.pause();
//                       } else {
//                         await FeedFm.play();
//                       }
//                     },
//                   ),
//                 ),
//
//                 // Skip Button
//                 IconButton(
//                   icon: const Icon(Icons.skip_next),
//                   iconSize: 48,
//                   color: canSkip ? Colors.white : Colors.white24,
//                   onPressed: canSkip
//                       ? () async {
//                     try {
//                       await FeedFm.skip();
//                     } catch (e) {
//                       _showError('Cannot skip this track');
//                     }
//                   }
//                       : null,
//                 ),
//
//                 // Like Button
//                 IconButton(
//                   icon: const Icon(Icons.thumb_up_outlined),
//                   iconSize: 32,
//                   color: Colors.white70,
//                   onPressed: () async {
//                     await FeedFm.like();
//                     _showError('Track liked');
//                   },
//                 ),
//               ],
//             ),
//           ),
//
//           // Player State Indicator
//           Container(
//             padding: const EdgeInsets.all(8),
//             child: Text(
//               _getStateText(),
//               style: TextStyle(
//                 color: _getStateColor(),
//                 fontSize: 12,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//
//           const SizedBox(height: 16),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildPlaceholderArt() {
//     return Container(
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(12),
//         gradient: LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: [Colors.purple[700]!, Colors.pink[700]!],
//         ),
//       ),
//       child: const Center(
//         child: Icon(
//           Icons.music_note,
//           size: 120,
//           color: Colors.white30,
//         ),
//       ),
//     );
//   }
//
//   void _showStationPicker() {
//     showModalBottomSheet(
//       context: context,
//       backgroundColor: Colors.grey[900],
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) {
//         return Container(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 width: 40,
//                 height: 4,
//                 decoration: BoxDecoration(
//                   color: Colors.white24,
//                   borderRadius: BorderRadius.circular(2),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               const Text(
//                 'Select Station',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 16),
//               Flexible(
//                 child: ListView.builder(
//                   shrinkWrap: true,
//                   itemCount: stations.length,
//                   itemBuilder: (context, index) {
//                     final station = stations[index];
//                     final isSelected = station.name == currentStation?.name;
//
//                     return ListTile(
//                       title: Text(
//                         station.name,
//                         style: TextStyle(
//                           color: isSelected ? Colors.purple[300] : Colors.white,
//                           fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
//                         ),
//                       ),
//                       subtitle: station.description.isNotEmpty
//                           ? Text(
//                         station.description,
//                         style: const TextStyle(color: Colors.white54),
//                       )
//                           : null,
//                       trailing: isSelected
//                           ? Icon(Icons.check_circle, color: Colors.purple[300])
//                           : null,
//                       onTap: () async {
//                         await FeedFm.selectStationByIndex(index);
//                         await _updateCurrentStation();
//                         Navigator.pop(context);
//                       },
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
//
//   String _getStateText() {
//     switch (playerState) {
//       case PlayerState.playing:
//         return '● PLAYING';
//       case PlayerState.paused:
//         return '⏸ PAUSED';
//       case PlayerState.stalled:
//         return '⏳ BUFFERING...';
//       case PlayerState.requestingSkip:
//         return '⏭ SKIPPING...';
//       case PlayerState.unavailable:
//         return '⚠ UNAVAILABLE';
//       case PlayerState.ready:
//         return '✓ READY';
//       default:
//         return 'IDLE';
//     }
//   }
//
//   Color _getStateColor() {
//     switch (playerState) {
//       case PlayerState.playing:
//         return Colors.green;
//       case PlayerState.paused:
//         return Colors.orange;
//       case PlayerState.stalled:
//       case PlayerState.requestingSkip:
//         return Colors.yellow;
//       case PlayerState.unavailable:
//         return Colors.red;
//       case PlayerState.ready:
//         return Colors.blue;
//       default:
//         return Colors.white54;
//     }
//   }
// }
///=====================================working code================================///
//
// import 'dart:async';
//
// import 'package:feed_fm/feed_fm.dart';
// import 'package:feed_fm/feed_fm_data_model.dart' hide Track, Station;
// import 'package:feed_fm/feed_fm_public_interface.dart' hide FeedFm;
// import 'package:flutter/material.dart';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'FeedFM Demo',
//       home: MusicPlayerPage(),
//     );
//   }
// }
//
// class MusicPlayerPage extends StatefulWidget {
//   const MusicPlayerPage({Key? key}) : super(key: key);
//
//   @override
//   State<MusicPlayerPage> createState() => _MusicPlayerPageState();
// }
//
// class _MusicPlayerPageState extends State<MusicPlayerPage> {
//   Track? currentTrack;
//   PlayerState playerState = PlayerState.idle;
//   List<Station> stations = [];
//   Station? currentStation;
//   bool canSkip = false;
//   double progress = 0.0;
//   int currentPosition = 0;
//   int duration = 0;
//
//   StreamSubscription? _stateSubscription;
//   StreamSubscription? _trackSubscription;
//   StreamSubscription? _progressSubscription;
//   Timer? _pollingTimer;
//
//   @override
//   void initState() {
//     super.initState();
//     _initializePlayer();
//     _setupListeners();
//     _startPolling();
//   }
//
//   Future<void> _initializePlayer() async {
//     // Replace with your actual Feed.fm credentials
//     final success = await FeedFm.initialize(
//       token: 'demo',
//       secret: 'demo',
//     );
//
//     if (success) {
//       await _loadStations();
//       await _updateCurrentTrack();
//       await _updatePlayerState();
//     } else {
//       _showError('Failed to initialize player');
//     }
//   }
//
//   void _setupListeners() {
//     // Listen to state changes
//     _stateSubscription = FeedFm.onStateChanged.listen((event) {
//       if (event.state != null) {
//         setState(() {
//           playerState = event.state!;
//         });
//       }
//     });
//
//     // Listen to track changes
//     _trackSubscription = FeedFm.onTrackChanged.listen((event) {
//       if (event.track != null) {
//         print('Track changed: ${event.track!.toString()}');
//         setState(() {
//           currentTrack = event.track;
//         });
//         _updateCanSkip();
//       }
//     });
//
//     // Listen to progress updates
//     _progressSubscription = FeedFm.onProgressChanged.listen((event) {
//       setState(() {
//         currentPosition = event.position;
//         duration = event.duration;
//         progress = event.progress;
//       });
//     });
//   }
//
//   Future<void> _loadStations() async {
//     final stationList = await FeedFm.getStations();
//     setState(() {
//       stations = stationList;
//     });
//
//     if (stations.isNotEmpty) {
//       await FeedFm.selectStationByIndex(0);
//       await _updateCurrentStation();
//     }
//   }
//
//   Future<void> _updateCurrentTrack() async {
//     final track = await FeedFm.getCurrentTrack();
//     setState(() {
//       currentTrack = track;
//     });
//     await _updateCanSkip();
//   }
//
//   Future<void> _updatePlayerState() async {
//     final state = await FeedFm.getPlaybackState();
//     setState(() {
//       playerState = state;
//     });
//   }
//
//   Future<void> _updateCurrentStation() async {
//     final station = await FeedFm.getCurrentStation();
//     setState(() {
//       currentStation = station;
//     });
//   }
//
//   Future<void> _updateCanSkip() async {
//     final skip = await FeedFm.canSkip();
//     setState(() {
//       canSkip = skip;
//     });
//   }
//
//   void _showError(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message)),
//     );
//   }
//
//   String _formatDuration(int seconds) {
//     final minutes = seconds ~/ 60;
//     final secs = seconds % 60;
//     return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
//   }
//
//   void _startPolling() {
//     // Poll every second to update track info and state
//     _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
//       await _updateCurrentTrack();
//       await _updatePlayerState();
//       await _updateCanSkip();
//     });
//   }
//
//   @override
//   void dispose() {
//     _stateSubscription?.cancel();
//     _trackSubscription?.cancel();
//     _progressSubscription?.cancel();
//     _pollingTimer?.cancel();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: const Text('Music Player'),
//         backgroundColor: Colors.grey[900],
//         elevation: 0,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.list),
//             onPressed: () => _showStationPicker(),
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           // Station Info
//           Container(
//             padding: const EdgeInsets.all(16),
//             child: Text(
//               currentStation?.name ?? 'No Station Selected',
//               style: const TextStyle(
//                 color: Colors.white70,
//                 fontSize: 16,
//               ),
//             ),
//           ),
//
//           // Album Art
//           Expanded(
//             child: Center(
//               child: Container(
//                 width: 300,
//                 height: 300,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(12),
//                   color: Colors.grey[800],
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.5),
//                       blurRadius: 20,
//                       spreadRadius: 5,
//                     ),
//                   ],
//                 ),
//                 child: currentTrack?.albumArtUrl != null &&
//                     currentTrack!.albumArtUrl.isNotEmpty
//                     ? ClipRRect(
//                   borderRadius: BorderRadius.circular(12),
//                   child: Image.network(
//                     currentTrack!.albumArtUrl,
//                     fit: BoxFit.cover,
//                     errorBuilder: (context, error, stackTrace) =>
//                         _buildPlaceholderArt(),
//                   ),
//                 )
//                     : _buildPlaceholderArt(),
//               ),
//             ),
//           ),
//
//           // Track Info
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//             child: Column(
//               children: [
//                 Text(
//                   currentTrack?.title ?? 'No Track Playing',
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 24,
//                     fontWeight: FontWeight.bold,
//                   ),
//                   textAlign: TextAlign.center,
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   currentTrack?.artist ?? '',
//                   style: const TextStyle(
//                     color: Colors.white70,
//                     fontSize: 18,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   currentTrack?.album ?? '',
//                   style: const TextStyle(
//                     color: Colors.white54,
//                     fontSize: 14,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//               ],
//             ),
//           ),
//
//           // Progress Bar
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24),
//             child: Column(
//               children: [
//                 SliderTheme(
//                   data: SliderThemeData(
//                     thumbShape: const RoundSliderThumbShape(
//                       enabledThumbRadius: 6,
//                     ),
//                     overlayShape: const RoundSliderOverlayShape(
//                       overlayRadius: 14,
//                     ),
//                     trackHeight: 4,
//                   ),
//                   child: Slider(
//                     value: progress.clamp(0.0, 1.0),
//                     onChanged: null, // Feed.fm doesn't support seeking
//                     activeColor: Colors.white,
//                     inactiveColor: Colors.white24,
//                   ),
//                 ),
//                 Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 8),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       Text(
//                         _formatDuration(currentPosition),
//                         style: const TextStyle(
//                           color: Colors.white54,
//                           fontSize: 12,
//                         ),
//                       ),
//                       Text(
//                         _formatDuration(duration),
//                         style: const TextStyle(
//                           color: Colors.white54,
//                           fontSize: 12,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//
//           // Control Buttons
//           Padding(
//             padding: const EdgeInsets.all(24),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 // Dislike Button
//                 IconButton(
//                   icon: const Icon(Icons.thumb_down_outlined),
//                   iconSize: 32,
//                   color: Colors.white70,
//                   onPressed: () async {
//                     await FeedFm.dislike();
//                     _showError('Track disliked');
//                   },
//                 ),
//
//                 // Previous (disabled for Feed.fm)
//                 IconButton(
//                   icon: const Icon(Icons.skip_previous),
//                   iconSize: 48,
//                   color: Colors.white24,
//                   onPressed: null,
//                 ),
//
//                 // Play/Pause Button
//                 Container(
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     gradient: LinearGradient(
//                       colors: [Colors.purple[400]!, Colors.pink[400]!],
//                     ),
//                     boxShadow: [
//                       BoxShadow(
//                         color: Colors.purple.withOpacity(0.4),
//                         blurRadius: 20,
//                         spreadRadius: 2,
//                       ),
//                     ],
//                   ),
//                   child: IconButton(
//                     icon: Icon(
//                       playerState == PlayerState.playing
//                           ? Icons.pause
//                           : Icons.play_arrow,
//                     ),
//                     iconSize: 48,
//                     color: Colors.white,
//                     onPressed: () async {
//                       if (playerState == PlayerState.playing) {
//                         await FeedFm.pause();
//                       } else {
//                         await FeedFm.play();
//                       }
//                     },
//                   ),
//                 ),
//
//                 // Skip Button
//                 IconButton(
//                   icon: const Icon(Icons.skip_next),
//                   iconSize: 48,
//                   color: canSkip ? Colors.white : Colors.white24,
//                   onPressed: canSkip
//                       ? () async {
//                     try {
//                       await FeedFm.skip();
//                     } catch (e) {
//                       _showError('Cannot skip this track');
//                     }
//                   }
//                       : null,
//                 ),
//
//                 // Like Button
//                 IconButton(
//                   icon: const Icon(Icons.thumb_up_outlined),
//                   iconSize: 32,
//                   color: Colors.white70,
//                   onPressed: () async {
//                     await FeedFm.like();
//                     _showError('Track liked');
//                   },
//                 ),
//               ],
//             ),
//           ),
//
//           // Player State Indicator
//           Container(
//             padding: const EdgeInsets.all(8),
//             child: Text(
//               _getStateText(),
//               style: TextStyle(
//                 color: _getStateColor(),
//                 fontSize: 12,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//
//           const SizedBox(height: 16),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildPlaceholderArt() {
//     return Container(
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(12),
//         gradient: LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: [Colors.purple[700]!, Colors.pink[700]!],
//         ),
//       ),
//       child: const Center(
//         child: Icon(
//           Icons.music_note,
//           size: 120,
//           color: Colors.white30,
//         ),
//       ),
//     );
//   }
//
//   void _showStationPicker() {
//     showModalBottomSheet(
//       context: context,
//       backgroundColor: Colors.grey[900],
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) {
//         return Container(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 width: 40,
//                 height: 4,
//                 decoration: BoxDecoration(
//                   color: Colors.white24,
//                   borderRadius: BorderRadius.circular(2),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               const Text(
//                 'Select Station',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 16),
//               Flexible(
//                 child: ListView.builder(
//                   shrinkWrap: true,
//                   itemCount: stations.length,
//                   itemBuilder: (context, index) {
//                     final station = stations[index];
//                     final isSelected = station.name == currentStation?.name;
//
//                     return ListTile(
//                       title: Text(
//                         station.name,
//                         style: TextStyle(
//                           color: isSelected ? Colors.purple[300] : Colors.white,
//                           fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
//                         ),
//                       ),
//                       subtitle: station.description.isNotEmpty
//                           ? Text(
//                         station.description,
//                         style: const TextStyle(color: Colors.white54),
//                       )
//                           : null,
//                       trailing: isSelected
//                           ? Icon(Icons.check_circle, color: Colors.purple[300])
//                           : null,
//                       onTap: () async {
//                         await FeedFm.selectStationByIndex(index);
//                         await _updateCurrentStation();
//                         Navigator.pop(context);
//                       },
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
//
//   String _getStateText() {
//     switch (playerState) {
//       case PlayerState.playing:
//         return '● PLAYING';
//       case PlayerState.paused:
//         return '⏸ PAUSED';
//       case PlayerState.stalled:
//         return '⏳ BUFFERING...';
//       case PlayerState.requestingSkip:
//         return '⏭ SKIPPING...';
//       case PlayerState.unavailable:
//         return '⚠ UNAVAILABLE';
//       case PlayerState.ready:
//         return '✓ READY';
//       default:
//         return 'IDLE';
//     }
//   }
//
//   Color _getStateColor() {
//     switch (playerState) {
//       case PlayerState.playing:
//         return Colors.green;
//       case PlayerState.paused:
//         return Colors.orange;
//       case PlayerState.stalled:
//       case PlayerState.requestingSkip:
//         return Colors.yellow;
//       case PlayerState.unavailable:
//         return Colors.red;
//       case PlayerState.ready:
//         return Colors.blue;
//       default:
//         return Colors.white54;
//     }
//   }
// }

