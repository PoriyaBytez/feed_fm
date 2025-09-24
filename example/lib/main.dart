import 'package:feed_fm/feed_fm_initialize.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FeedFm.initialize(token: "demo", secret: "demo");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: FeedFmDemo(),
    );
  }
}

class FeedFmDemo extends StatefulWidget {
  const FeedFmDemo({super.key});

  @override
  State<FeedFmDemo> createState() => _FeedFmDemoState();
}

class _FeedFmDemoState extends State<FeedFmDemo> {
  List<String> stations = [];

  Future<void> _loadStations() async {
    final list = await FeedFm.stations();
    setState(() {
      stations = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Feed.fm Demo")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                    onPressed: () => FeedFm.play(), child: const Text("Play")),
                ElevatedButton(
                    onPressed: () => FeedFm.pause(), child: const Text("Pause")),
                ElevatedButton(
                    onPressed: () => FeedFm.skip(), child: const Text("Skip")),
                ElevatedButton(
                  onPressed: _loadStations,
                  child: const Text("Get Stations"),
                ),
              ],
            ),
          ),

          const Divider(),

          // Station List
          Expanded(
            child: stations.isEmpty
                ? const Center(child: Text("No stations loaded"))
                : ListView.builder(
              itemCount: stations.length,
              itemBuilder: (context, index) {
                final station = stations[index];
                return ListTile(
                  leading: const Icon(Icons.radio),
                  title: Text(station),
                  onTap: () {
                    debugPrint("Selected Station: $station");
                    // Future: Play specific station if supported
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
