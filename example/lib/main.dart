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
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  void _initFeedFm() async {
    await FeedFm.initialize('demo', 'demo');
  }

  void _play() async {
    await FeedFm.play();
  }

  void _pause() async {
    await FeedFm.pause();
  }

  void _skip() async {
    await FeedFm.skip();
  }

  void _showStations(BuildContext context) async {
    final stations = await FeedFm.stations();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stations'),
        content: Text(stations.join('\n')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FeedFM Demo')),
      body: const Center(child: Text('FeedFM Plugin Example')),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _initFeedFm,
            child: const Icon(Icons.music_note),
            heroTag: 'init',
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _play,
            child: const Icon(Icons.play_arrow),
            heroTag: 'play',
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _pause,
            child: const Icon(Icons.pause),
            heroTag: 'pause',
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _skip,
            child: const Icon(Icons.skip_next),
            heroTag: 'skip',
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: () => _showStations(context),
            child: const Icon(Icons.list),
            heroTag: 'stations',
          ),
        ],
      ),
    );
  }
}



// import 'package:flutter/material.dart';
// import 'dart:async';
//
// import 'package:flutter/services.dart';
// import 'package:feed_fm/feed_fm.dart';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatefulWidget {
//   const MyApp({super.key});
//
//   @override
//   State<MyApp> createState() => _MyAppState();
// }
//
// class _MyAppState extends State<MyApp> {
//   String _platformVersion = 'Unknown';
//   final _feedFmPlugin = FeedFm();
//
//   @override
//   void initState() {
//     super.initState();
//     initPlatformState();
//   }
//
//   // Platform messages are asynchronous, so we initialize in an async method.
//   Future<void> initPlatformState() async {
//     String platformVersion;
//     // Platform messages may fail, so we use a try/catch PlatformException.
//     // We also handle the message potentially returning null.
//     try {
//       platformVersion =
//           await FeedFm.getPlatformVersion() ?? 'Unknown platform version';
//     } on PlatformException {
//       platformVersion = 'Failed to get platform version.';
//     }
//
//     // If the widget was removed from the tree while the asynchronous platform
//     // message was in flight, we want to discard the reply rather than calling
//     // setState to update our non-existent appearance.
//     if (!mounted) return;
//
//     setState(() {
//       _platformVersion = platformVersion;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: Scaffold(
//         appBar: AppBar(
//           title: const Text('Plugin example app'),
//         ),
//         body: Center(
//           child: Text('Running on: $_platformVersion\n'),
//         ),
//       ),
//     );
//   }
// }
