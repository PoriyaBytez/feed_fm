package com.byteztech.feed_fm

import android.content.Context
import fm.feed.android.playersdk.FeedAudioPlayer
import fm.feed.android.playersdk.FeedPlayerService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FeedFmPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var player: FeedAudioPlayer? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    setupChannel(binding.binaryMessenger, binding.applicationContext)
  }

  // ✅ Modified helper: pass context explicitly
  fun registerWith(flutterEngine: FlutterEngine, appContext: Context) {
    setupChannel(flutterEngine.dartExecutor.binaryMessenger, appContext)
  }

  private fun setupChannel(messenger: io.flutter.plugin.common.BinaryMessenger, appContext: Context) {
    channel = MethodChannel(messenger, "feedfm")
    channel.setMethodCallHandler(this)
    context = appContext
  }







  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "initialize" -> {
        val token = call.argument<String>("token") ?: ""
        val secret = call.argument<String>("secret") ?: ""

        FeedPlayerService.initialize(context, token, secret)
        player = FeedPlayerService.getInstance()

        result.success(true)
      }

      "play" -> {
        player?.play()
        result.success(true)
      }

      "pause" -> {
        player?.pause()
        result.success(true)
      }

      "skip" -> {
        player?.skip()
        result.success(true)
      }

      "stations" -> {
        val stations = player?.stationList?.map { it.name } ?: emptyList()
        result.success(stations)
      }

      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}

//import io.flutter.embedding.engine.plugins.FlutterPlugin
//import io.flutter.plugin.common.MethodCall
//import io.flutter.plugin.common.MethodChannel
//import io.flutter.plugin.common.MethodChannel.MethodCallHandler
//import io.flutter.plugin.common.MethodChannel.Result
//
///** FeedFmPlugin */
//class FeedFmPlugin: FlutterPlugin, MethodCallHandler {
//  /// The MethodChannel that will the communication between Flutter and native Android
//  ///
//  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
//  /// when the Flutter Engine is detached from the Activity
//  private lateinit var channel : MethodChannel
//
//  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
//    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "feed_fm")
//    channel.setMethodCallHandler(this)
//  }
//
//  override fun onMethodCall(call: MethodCall, result: Result) {
//    if (call.method == "getPlatformVersion") {
//      result.success("Android ${android.os.Build.VERSION.RELEASE}")
//    } else {
//      result.notImplemented()
//    }
//  }
//
//  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
//    channel.setMethodCallHandler(null)
//  }
//}
