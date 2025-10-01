package com.byteztech.feed_fm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pass the app context from the Activity
        FeedFmPlugin().registerWith(flutterEngine, applicationContext)
    }
}
