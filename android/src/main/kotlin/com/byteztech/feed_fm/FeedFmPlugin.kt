package com.byteztech.feed_fm

import android.content.Context
import android.os.Handler
import android.os.Looper
import fm.feed.android.playersdk.FeedAudioPlayer
import fm.feed.android.playersdk.FeedPlayerService
import fm.feed.android.playersdk.StateListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import android.util.Log

class FeedFmPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

  private lateinit var methodChannel: MethodChannel
  private lateinit var stateEventChannel: EventChannel
  private lateinit var trackEventChannel: EventChannel
  private lateinit var progressEventChannel: EventChannel
  private lateinit var skipEventChannel: EventChannel
  // New channels
  private lateinit var stationEventChannel: EventChannel
  private lateinit var errorEventChannel: EventChannel

  private var stateEventSink: EventChannel.EventSink? = null
  private var trackEventSink: EventChannel.EventSink? = null
  private var progressEventSink: EventChannel.EventSink? = null
  private var skipEventSink: EventChannel.EventSink? = null
  // New sinks
  private var stationEventSink: EventChannel.EventSink? = null
  private var errorEventSink: EventChannel.EventSink? = null

  private lateinit var context: Context
  private var player: FeedAudioPlayer? = null

  private val handler = Handler(Looper.getMainLooper())
  private var progressRunnable: Runnable? = null

  private var playbackStartTime: Long = 0
  private var pausedPosition: Long = 0
  private var isPaused: Boolean = true
  private var currentTrackId: String? = null
  private var lastCanSkip: Boolean = false
  // Track the last known volume when SDK doesn't expose a getter
  private var currentVolume: Float = 1.0f
  // Control autoplay behavior on station change
  private var autoplayOnStationChange: Boolean = true
  // Remember last state to avoid re-initializing timers on repeated callbacks
  private var lastStateStr: String? = null
  // Seek smoothing
  private var lastSeekTargetSec: Int? = null
  private var lastSeekTimeMs: Long = 0L

  private companion object {
    const val METHOD_CHANNEL_NAME = "feed_fm"
    const val STATE_EVENT_CHANNEL = "feed_fm/state_events"
    const val TRACK_EVENT_CHANNEL = "feed_fm/track_events"
    const val PROGRESS_EVENT_CHANNEL = "feed_fm/progress_events"
    const val SKIP_EVENT_CHANNEL = "feed_fm/skip_events"
    // New event channels
    const val STATION_EVENT_CHANNEL = "feed_fm/station_events"
    const val ERROR_EVENT_CHANNEL = "feed_fm/error_events"
    const val TAG = "FeedFmPlugin"
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    setupChannels(binding.binaryMessenger, binding.applicationContext)
  }

  fun registerWith(flutterEngine: FlutterEngine, appContext: Context) {
    setupChannels(flutterEngine.dartExecutor.binaryMessenger, appContext)
  }

  private fun setupChannels(messenger: BinaryMessenger, appContext: Context) {
    context = appContext

    methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    methodChannel.setMethodCallHandler(this)

    stateEventChannel = EventChannel(messenger, STATE_EVENT_CHANNEL)
    stateEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        stateEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        stateEventSink = null
      }
    })

    trackEventChannel = EventChannel(messenger, TRACK_EVENT_CHANNEL)
    trackEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        trackEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        trackEventSink = null
      }
    })

    progressEventChannel = EventChannel(messenger, PROGRESS_EVENT_CHANNEL)
    progressEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        progressEventSink = events
        startProgressUpdates()
      }
      override fun onCancel(arguments: Any?) {
        progressEventSink = null
        stopProgressUpdates()
      }
    })

    skipEventChannel = EventChannel(messenger, SKIP_EVENT_CHANNEL)
    skipEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        skipEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        skipEventSink = null
      }
    })

    // New: station events
    stationEventChannel = EventChannel(messenger, STATION_EVENT_CHANNEL)
    stationEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        stationEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        stationEventSink = null
      }
    })

    // New: error events
    errorEventChannel = EventChannel(messenger, ERROR_EVENT_CHANNEL)
    errorEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        errorEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        errorEventSink = null
      }
    })
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    stateEventChannel.setStreamHandler(null)
    trackEventChannel.setStreamHandler(null)
    progressEventChannel.setStreamHandler(null)
    skipEventChannel.setStreamHandler(null)
    // New
    stationEventChannel.setStreamHandler(null)
    errorEventChannel.setStreamHandler(null)

    stopProgressUpdates()
    player?.removeStateListener(stateListener)
    // Removed: player?.removePlayListener(playListener)
  }

  // State Listener
  private val stateListener = StateListener { state ->
    handler.post {
      val stateStr = state.toString()
      stateEventSink?.success(mapOf(
        "event" to "stateChanged",
        "state" to stateStr
      ))

      if (lastStateStr == stateStr) return@post
      val prevState = lastStateStr
      lastStateStr = stateStr

      when (stateStr.uppercase()) {
        "PLAYING" -> {
          isPaused = false
          when (prevState?.uppercase()) {
            // Resume from pause: honor pausedPosition
            "PAUSED" -> {
              if (pausedPosition > 0) {
                playbackStartTime = System.currentTimeMillis() - pausedPosition
              } else if (playbackStartTime == 0L) {
                playbackStartTime = System.currentTimeMillis()
              }
            }
            // From transient states (READY/WAITING/STALLED/REQUESTING_SKIP), do not clobber seek-adjusted timers
            "READY", "WAITING", "STALLED", "REQUESTING_SKIP" -> {
              if (playbackStartTime == 0L && pausedPosition == 0L) {
                // Starting fresh (no prior timing info)
                playbackStartTime = System.currentTimeMillis()
              }
            }
            // From STOPPED or unknown -> starting fresh
            else -> {
              playbackStartTime = System.currentTimeMillis()
              pausedPosition = 0
            }
          }
        }
        "PAUSED" -> {
          isPaused = true
          pausedPosition = if (playbackStartTime > 0) System.currentTimeMillis() - playbackStartTime else pausedPosition
        }
        "STOPPED" -> {
          playbackStartTime = 0
          pausedPosition = 0
          isPaused = true
        }
        // Do NOT reset timers on READY/WAITING/STALLED/REQUESTING_SKIP anymore
        "READY", "WAITING", "STALLED", "REQUESTING_SKIP" -> {
          // keep timing
        }
        else -> {}
      }
    }
  }

  // Removed Play Listener; track changes will be detected in progress loop.
  // private val playListener = object : PlayListener { ... }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "initialize" -> initializePlayer(call, result)
      "play" -> playMusic(result)
      "pause" -> pauseMusic(result)
      "stop" -> stopMusic(result)
      "skip" -> skipTrack(result)
      "like" -> likeTrack(result)
      "dislike" -> dislikeTrack(result)
      "unlike" -> unlikeTrack(result)
      "selectStationByIndex" -> selectStationByIndex(call, result)
      "selectStationById" -> selectStationById(call, result)
      "getStations" -> getStations(result)
      "getCurrentStation" -> getCurrentStation(result)
      "getCurrentTrack" -> getCurrentTrack(result)
      "getPlaybackState" -> getPlaybackState(result)
      "canSkip" -> canSkip(result)
      "setVolume" -> setVolume(call, result)
      "getVolume" -> getVolume(result)
      "isAvailable" -> isAvailable(result)
      "getClientId" -> getClientId(result)
      "getActiveStationId" -> getActiveStationId(result)
      "requestSkip" -> skipTrack(result) // alias of skip
      "mixCrossfade" -> setMixCrossfade(call, result)
      "setSecondsOfCrossfade" -> setSecondsOfCrossfade(call, result)
      // New methods
      "getSecondsOfCrossfade" -> getSecondsOfCrossfade(result)
      "getPosition" -> getPosition(result)
      "getDuration" -> getDuration(result)
      "togglePlayPause" -> togglePlayPause(result)
      "setAutoplayOnStationChange" -> setAutoplayOnStationChange(call, result)
      // New: seek support
      "seekTo" -> seekTo(call, result)
      "supportsSeek" -> supportsSeek(result)
      else -> result.notImplemented()
    }
  }

  private fun initializePlayer(call: MethodCall, result: MethodChannel.Result) {
    try {
      val token = call.argument<String>("token") ?: ""
      val secret = call.argument<String>("secret") ?: ""

      FeedPlayerService.initialize(context, token, secret)
      player = FeedPlayerService.getInstance()

      player?.addStateListener(stateListener)
      // Removed: player?.addPlayListener(playListener)
      // Initialize player volume to last known
      player?.setVolume(currentVolume)

      // Kick off a short availability probe to help early "getStations" calls
      probeStationsAvailability()

      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "init failed")))
      result.error("INIT_ERROR", e.message, null)
    }
  }

  private fun playMusic(result: MethodChannel.Result) {
    try {
      player?.play()
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "play failed")))
      result.error("PLAY_ERROR", e.message, null)
    }
  }

  private fun pauseMusic(result: MethodChannel.Result) {
    try {
      player?.pause()
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "pause failed")))
      result.error("PAUSE_ERROR", e.message, null)
    }
  }

  private fun stopMusic(result: MethodChannel.Result) {
    try {
      player?.stop()
      playbackStartTime = 0
      pausedPosition = 0
      isPaused = true
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "stop failed")))
      result.error("STOP_ERROR", e.message, null)
    }
  }

  private fun togglePlayPause(result: MethodChannel.Result) {
    try {
      val stateStr = player?.state?.toString()?.uppercase()
      if (stateStr == "PLAYING") {
        player?.pause()
      } else {
        player?.play()
      }
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "toggle failed")))
      result.error("TOGGLE_ERROR", e.message, null)
    }
  }

  private fun skipTrack(result: MethodChannel.Result) {
    try {
      player?.skip()
      playbackStartTime = 0
      pausedPosition = 0
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "skip failed")))
      result.error("SKIP_ERROR", e.message, null)
    }
  }

  private fun likeTrack(result: MethodChannel.Result) {
    try {
      player?.like()
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "like failed")))
      result.error("LIKE_ERROR", e.message, null)
    }
  }

  private fun dislikeTrack(result: MethodChannel.Result) {
    try {
      player?.dislike()
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "dislike failed")))
      result.error("DISLIKE_ERROR", e.message, null)
    }
  }

  private fun unlikeTrack(result: MethodChannel.Result) {
    try {
      player?.unlike()
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "unlike failed")))
      result.error("UNLIKE_ERROR", e.message, null)
    }
  }

  private fun selectStationByIndex(call: MethodCall, result: MethodChannel.Result) {
    try {
      val index = call.argument<Int>("index") ?: -1
      player?.let { p ->
        val stationList = p.stationList
        if (stationList != null && index >= 0 && index < stationList.size) {
          val station = stationList[index]
          p.setActiveStation(station, autoplayOnStationChange)
          // Ensure playback if autoplay is requested
          if (autoplayOnStationChange) {
            try { p.play() } catch (_: Exception) {}
          }
          playbackStartTime = 0
          pausedPosition = 0
          stationEventSink?.success(mapOf(
            "id" to (station.name ?: ""),
            "name" to (station.name ?: ""),
            "description" to (station.options?.get("description") ?: "")
          ))
          result.success(true)
        } else {
          result.error("INVALID_INDEX", "Station index out of bounds.", null)
        }
      } ?: result.error("NOT_INITIALIZED", "Player is not initialized.", null)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "select station failed")))
      result.error("SELECT_STATION_ERROR", e.message, null)
    }
  }

  private fun selectStationById(call: MethodCall, result: MethodChannel.Result) {
    try {
      val stationId = call.argument<String>("stationId") ?: ""
      player?.let { p ->
        val station = p.stationList?.find { it.name == stationId }
        if (station != null) {
          p.setActiveStation(station, autoplayOnStationChange)
          if (autoplayOnStationChange) {
            try { p.play() } catch (_: Exception) {}
          }
          playbackStartTime = 0
          pausedPosition = 0
          stationEventSink?.success(mapOf(
            "id" to (station.name ?: ""),
            "name" to (station.name ?: ""),
            "description" to (station.options?.get("description") ?: "")
          ))
          result.success(true)
        } else {
          result.error("STATION_NOT_FOUND", "Station with id $stationId not found", null)
        }
      } ?: result.error("NOT_INITIALIZED", "Player is not initialized.", null)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "select station failed")))
      result.error("SELECT_STATION_ERROR", e.message, null)
    }
  }

  private fun seekTo(call: MethodCall, result: MethodChannel.Result) {
    val seconds = call.argument<Int>("position") ?: 0
    val p = player
    if (p == null) {
      result.error("NOT_INITIALIZED", "Player is not initialized.", null)
      return
    }
    try {
      val playObj = p.currentPlay
      if (playObj == null) {
        result.error("NO_PLAY", "No active play to seek.", null)
        return
      }
      val durationTotal = playObj.audioFile?.durationInSeconds?.toInt() ?: 0
      val durationForClamp = if (durationTotal > 0) durationTotal else Int.MAX_VALUE
      val targetSec = seconds.coerceIn(0, durationForClamp)

      // Determine if this is a backward seek relative to our current notion of position
      val nowPosSec = when {
        isPaused -> (pausedPosition / 1000).toInt()
        playbackStartTime > 0 -> ((System.currentTimeMillis() - playbackStartTime) / 1000).toInt()
        else -> 0
      }
      val isBackward = targetSec < nowPosSec
      Log.d(TAG, "seekTo: target=$targetSec current=$nowPosSec backward=$isBackward duration=$durationTotal")

      var invoked = false
      var lastAttemptedMethod: String? = null

      fun tryInvokeOnTarget(target: Any, method: java.lang.reflect.Method, secondsValue: Int) {
        if (invoked) return
        try {
          val paramType = method.parameterTypes[0]
          val isMsHint = method.name.lowercase().contains("ms") || method.name.lowercase().contains("millis")
          val sec = secondsValue
          val ms = secondsValue * 1000
          val primary = if (isMsHint) ms else sec
          val alt = if (isMsHint) sec else ms

          fun toArg(v: Int): Any? = when (paramType) {
            Int::class.javaPrimitiveType, java.lang.Integer::class.java -> v
            Long::class.javaPrimitiveType, java.lang.Long::class.java -> v.toLong()
            Float::class.javaPrimitiveType, java.lang.Float::class.java -> v.toFloat()
            Double::class.javaPrimitiveType, java.lang.Double::class.java -> v.toDouble()
            else -> null
          }

          val arg1 = toArg(primary)
          val arg2 = toArg(alt)
          if (arg1 != null) {
            lastAttemptedMethod = "${method.name}($primary)"
            Log.d(TAG, "Invoking ${target.javaClass.simpleName}.${method.name}($arg1)")
            method.invoke(target, arg1)
            invoked = true
            Log.d(TAG, "SUCCESS: ${method.name}($arg1)")
            return
          }
          if (arg2 != null) {
            lastAttemptedMethod = "${method.name}($alt)"
            Log.d(TAG, "Invoking ${target.javaClass.simpleName}.${method.name}($arg2)")
            method.invoke(target, arg2)
            invoked = true
            Log.d(TAG, "SUCCESS: ${method.name}($arg2)")
          }
        } catch (e: Exception) {
          Log.w(TAG, "Failed to invoke ${method.name}: ${e.message}")
        }
      }

      fun candidate(m: java.lang.reflect.Method): Boolean {
        val n = m.name.lowercase()
        if (m.parameterTypes.size != 1) return false
        val t = m.parameterTypes[0]
        val numeric = t.isPrimitive && (t == Int::class.javaPrimitiveType || t == Long::class.javaPrimitiveType || t == Float::class.javaPrimitiveType || t == Double::class.javaPrimitiveType) ||
          (t == java.lang.Integer::class.java || t == java.lang.Long::class.java || t == java.lang.Float::class.java || t == java.lang.Double::class.java)
        if (!numeric) return false
        return n.contains("seek") || n.contains("setposition") || n.contains("position") || n.contains("playback") || n.contains("time")
      }

      val preferredNames = arrayOf(
        "seekTo", "seek", "seekToMs", "seekToMillis", "setPosition", "setPositionSeconds", "setPositionMs", "setPlaybackPosition", "setCurrentPosition", "setCurrentTime", "seekToTime", "setTime"
      )

      val wasPlaying = p.state?.toString()?.uppercase() == "PLAYING"
      Log.d(TAG, "Player state before seek: ${p.state} wasPlaying=$wasPlaying")

      fun attemptSeek(): Boolean {
        invoked = false
        // Try on player instance
        run {
          val methods = p.javaClass.methods
          Log.d(TAG, "Scanning ${methods.size} methods on ${p.javaClass.simpleName}")
          for (name in preferredNames) {
            val m = methods.find { it.name == name && it.parameterTypes.size == 1 }
            if (m != null) {
              Log.d(TAG, "Found preferred method: ${m.name}")
              tryInvokeOnTarget(p, m, targetSec)
              if (invoked) break
            }
          }
          if (!invoked) {
            val candidates = methods.filter { candidate(it) }
            Log.d(TAG, "Trying ${candidates.size} candidate methods")
            candidates.forEach { m ->
              if (!invoked) {
                Log.d(TAG, "Trying candidate: ${m.name}(${m.parameterTypes[0].simpleName})")
                tryInvokeOnTarget(p, m, targetSec)
              }
            }
          }
        }
        // If not found on player, try on currentPlay
        if (!invoked) {
          val play = p.currentPlay
          if (play != null) {
            Log.d(TAG, "Seeking on currentPlay: ${play.javaClass.simpleName}")
            val methods = play.javaClass.methods
            for (name in preferredNames) {
              val m = methods.find { it.name == name && it.parameterTypes.size == 1 }
              if (m != null) {
                Log.d(TAG, "Found preferred method on Play: ${m.name}")
                tryInvokeOnTarget(play, m, targetSec)
                if (invoked) break
              }
            }
            if (!invoked) {
              val candidates = methods.filter { candidate(it) }
              Log.d(TAG, "Trying ${candidates.size} candidate methods on Play")
              candidates.forEach { m ->
                if (!invoked) {
                  Log.d(TAG, "Trying candidate on Play: ${m.name}(${m.parameterTypes[0].simpleName})")
                  tryInvokeOnTarget(play, m, targetSec)
                }
              }
            }
          }
        }
        return invoked
      }

      // First try without changing playback state
      var ok = attemptSeek()
      Log.d(TAG, "First attempt result: $ok (method: $lastAttemptedMethod)")

      // Fallback for backward seeks: briefly pause, try again, then resume if needed
      if (!ok && isBackward && wasPlaying) {
        Log.d(TAG, "Backward seek fallback: pausing...")
        try { p.pause() } catch (e: Exception) { Log.w(TAG, "Pause failed: ${e.message}") }
        Thread.sleep(100) // Increased delay to let pause settle
        ok = attemptSeek()
        Log.d(TAG, "Paused attempt result: $ok")
        if (wasPlaying) {
          try { p.play() } catch (e: Exception) { Log.w(TAG, "Resume failed: ${e.message}") }
        }
      }

      // Additional fallback: try seeking backward by forcing position reset
      if (!ok && isBackward) {
        Log.d(TAG, "Additional backward seek fallback: trying alternate methods...")
        try {
          // Try stopping and playing to force position reset
          val currentStation = p.activeStation
          if (currentStation != null) {
            p.stop()
            Thread.sleep(100)
            // Manually set our internal position tracker
            playbackStartTime = System.currentTimeMillis() - (targetSec * 1000L)
            pausedPosition = targetSec * 1000L
            if (wasPlaying) {
              p.play()
            }
            ok = true
            Log.d(TAG, "Forced position reset for backward seek")
          }
        } catch (e: Exception) {
          Log.w(TAG, "Forced position reset failed: ${e.message}")
        }
      }

      if (!ok) {
        Log.e(TAG, "Seek FAILED - no suitable method found")
        result.error("UNSUPPORTED", "Seeking not supported by this SDK version.", null)
        return
      }

      val clamped = if (durationTotal > 0) targetSec.coerceAtMost(durationTotal) else targetSec

      // CRITICAL FIX: For backward seeks, we must force a longer smoothing window
      // because the SDK's internal position updates asynchronously
      val smoothingDuration = if (isBackward) 3000L else 1500L

      if (isPaused) {
        pausedPosition = clamped * 1000L
      } else {
        playbackStartTime = System.currentTimeMillis() - clamped * 1000L
      }
      lastSeekTargetSec = clamped
      lastSeekTimeMs = System.currentTimeMillis()

      Log.d(TAG, "Seek complete: target=$clamped playbackStartTime=$playbackStartTime pausedPos=$pausedPosition smoothing=${smoothingDuration}ms")

      // Emit immediate progress update
      progressEventSink?.success(mapOf(
        "position" to clamped,
        "duration" to (durationTotal.coerceAtLeast(0))
      ))
      result.success(true)
    } catch (e: Exception) {
      Log.e(TAG, "Seek exception: ${e.message}", e)
      errorEventSink?.success(mapOf("message" to (e.message ?: "seek failed")))
      result.error("SEEK_ERROR", e.message, null)
    }
  }

  private fun supportsSeek(result: MethodChannel.Result) {
    val p = player
    if (p == null) {
      result.success(false)
      return
    }
    try {
      fun candidate(m: java.lang.reflect.Method): Boolean {
        val n = m.name.lowercase()
        if (m.parameterTypes.size != 1) return false
        val t = m.parameterTypes[0]
        val numeric = t.isPrimitive && (t == Int::class.javaPrimitiveType || t == Long::class.javaPrimitiveType || t == Float::class.javaPrimitiveType || t == Double::class.javaPrimitiveType) ||
          (t == java.lang.Integer::class.java || t == java.lang.Long::class.java || t == java.lang.Float::class.java || t == java.lang.Double::class.java)
        if (!numeric) return false
        return n.contains("seek") || n.contains("position") || n.contains("playback") || n.contains("time")
      }
      val targets = mutableListOf<Any>()
      targets.add(p)
      p.currentPlay?.let { targets.add(it) }
      val supported = targets.any { t -> t.javaClass.methods.any { candidate(it) } }
      result.success(supported)
    } catch (_: Exception) {
      result.success(false)
    }
  }

  private fun getStations(result: MethodChannel.Result) {
    try {
      val p = player
      if (p == null) {
        result.error("NOT_INITIALIZED", "Player is not initialized.", null)
        return
      }

      val stations = p.stationList
      if (stations != null && stations.isNotEmpty()) {
        val payload = stations.mapIndexed { index, station ->
          mapOf(
            "index" to index,
            // Expose name as id for cross-platform consistency
            "id" to (station.name ?: ""),
            "name" to (station.name ?: ""),
            "description" to (station.options?.get("description") ?: ""),
            "image" to (station.options?.get("image") ?: "")
          )
        }
        result.success(payload)
        return
      }

      // Fallback: wait briefly for stations to load, then return or timeout
      waitForStationsThenReturn(result, maxAttempts = 20, delayMs = 150)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get stations failed")))
      result.error("GET_STATIONS_ERROR", e.message, null)
    }
  }

  private fun waitForStationsThenReturn(result: MethodChannel.Result, maxAttempts: Int, delayMs: Long) {
    var attemptsLeft = maxAttempts
    fun poll() {
      val p = player
      val list = p?.stationList
      if (list != null && list.isNotEmpty()) {
        val payload = list.mapIndexed { index, station ->
          mapOf(
            "index" to index,
            "id" to (station.name ?: ""),
            "name" to (station.name ?: ""),
            "description" to (station.options?.get("description") ?: "")
          )
        }
        result.success(payload)
      } else if (attemptsLeft > 0) {
        attemptsLeft -= 1
        handler.postDelayed({ poll() }, delayMs)
      } else {
        // Timed out; return empty list rather than an error
        result.success(emptyList<Map<String, Any?>>())
      }
    }
    poll()
  }

  private fun probeStationsAvailability() {
    // Emit a lightweight state hint when stations first become available
    var fired = false
    fun check() {
      if (fired) return
      val s = player?.stationList
      if (s != null && s.isNotEmpty()) {
        fired = true
        stateEventSink?.success(mapOf(
          "event" to "availableChanged",
          "available" to true
        ))
      } else {
        handler.postDelayed({ check() }, 200)
      }
    }
    handler.postDelayed({ check() }, 200)
  }

  private fun getCurrentStation(result: MethodChannel.Result) {
    try {
      val station = player?.activeStation
      val stationMap = if (station != null) {
        mapOf(
          // Expose name as id for cross-platform consistency
          "id" to (station.name ?: ""),
          "name" to (station.name ?: ""),
          "description" to (station.options?.get("description") ?: "")
        )
      } else {
        null
      }
      result.success(stationMap)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get current station failed")))
      result.error("GET_CURRENT_STATION_ERROR", e.message, null)
    }
  }

  private fun getCurrentTrack(result: MethodChannel.Result) {
    try {
      val play = player?.currentPlay
      val trackMap = if (play != null) {
        mapOf("play" to buildPlayMap(play))
      } else {
        emptyMap<String, Any>()
      }
      result.success(trackMap)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get track failed")))
      result.error("GET_TRACK_ERROR", e.message, null)
    }
  }

  private fun buildPlayMap(play: fm.feed.android.playersdk.models.Play): Map<String, Any?> {
    return mapOf(
      "id" to play.audioFile.id.toString(),
      "audio_file" to mapOf(
        "id" to play.audioFile.id.toString(),
        "duration_in_seconds" to play.audioFile.durationInSeconds.toInt(),
        "codec" to (play.audioFile.codec ?: ""),
        "track" to mapOf(
          "id" to play.audioFile.track.id.toString(),
          "title" to (play.audioFile.track.title ?: "")
        ),
        "release" to mapOf(
          "id" to play.audioFile.release.id.toString(),
          "title" to (play.audioFile.release.title ?: "")
        ),
        "artist" to mapOf(
          "id" to play.audioFile.artist.id.toString(),
          "name" to (play.audioFile.artist.name ?: "")
        ),
        "url" to (play.audioFile.url ?: ""),
        "bitrate" to (play.audioFile.bitrate ?: 0),
        "liked" to play.audioFile.isLiked,
        "replaygain_track_gain" to (play.audioFile.replayGain ?: 0.0),
        "extra" to mapOf(
          "artwork" to (play.audioFile.metadata?.get("artwork") ?: ""),
          "image" to (play.audioFile.metadata?.get("image") ?: ""),
          "background_image_url" to (play.audioFile.metadata?.get("background_image_url") ?: ""),
          "caption" to (play.audioFile.metadata?.get("caption") ?: "")
        )
      ),
      "station" to mapOf(
        // Expose name as id for cross-platform consistency
        "id" to (play.station?.name ?: ""),
        "name" to (play.station?.name ?: ""),
        "pre_gain" to (play.station?.preGain ?: 0.0)
      )
    )
  }

  private fun getPlaybackState(result: MethodChannel.Result) {
    try {
      val state = player?.state?.toString() ?: "IDLE"
      result.success(state)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get state failed")))
      result.error("GET_STATE_ERROR", e.message, null)
    }
  }

  private fun canSkip(result: MethodChannel.Result) {
    try {
      val canSkipNow = player?.canSkip() ?: false
      if (canSkipNow != lastCanSkip) {
        lastCanSkip = canSkipNow
        skipEventSink?.success(mapOf(
          "event" to "skipStatusChanged",
          "canSkip" to canSkipNow
        ))
      }
      result.success(canSkipNow)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "canSkip failed")))
      result.error("CAN_SKIP_ERROR", e.message, null)
    }
  }

  private fun setVolume(call: MethodCall, result: MethodChannel.Result) {
    try {
      val volume = call.argument<Double>("volume")?.toFloat() ?: 1.0f
      currentVolume = volume
      player?.setVolume(volume)
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "set volume failed")))
      result.error("SET_VOLUME_ERROR", e.message, null)
    }
  }

  private fun getVolume(result: MethodChannel.Result) {
    try {
      // SDK may not expose a getter; return the last set value as a Double
      result.success(currentVolume.toDouble())
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get volume failed")))
      result.error("GET_VOLUME_ERROR", e.message, null)
    }
  }

  private fun getSecondsOfCrossfade(result: MethodChannel.Result) {
    try {
      val seconds = player?.secondsOfCrossfade ?: 0f
      result.success(seconds.toDouble())
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get crossfade failed")))
      result.error("GET_SECONDS_OF_CROSSFADE_ERROR", e.message, null)
    }
  }

  private fun isAvailable(result: MethodChannel.Result) {
    try {
      result.success((player?.stationList?.size ?: 0) > 0)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "isAvailable failed")))
      result.error("IS_AVAILABLE_ERROR", e.message, null)
    }
  }

  private fun getClientId(result: MethodChannel.Result) {
    try {
      result.success(player?.clientId ?: "")
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get client id failed")))
      result.error("GET_CLIENT_ID_ERROR", e.message, null)
    }
  }

  private fun getActiveStationId(result: MethodChannel.Result) {
    try {
      // Expose name as id for cross-platform consistency
      result.success(player?.activeStation?.name ?: "")
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get active station id failed")))
      result.error("GET_ACTIVE_STATION_ID_ERROR", e.message, null)
    }
  }

  private fun setMixCrossfade(call: MethodCall, result: MethodChannel.Result) {
    try {
      // Some SDK versions expose crossfade behavior; here we accept the flag
      // and return success even if it's a no-op to keep API stable.
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "mixCrossfade failed")))
      result.error("SET_MIX_CROSSFADE_ERROR", e.message, null)
    }
  }

  private fun setSecondsOfCrossfade(call: MethodCall, result: MethodChannel.Result) {
    try {
      val seconds = call.argument<Int>("seconds")?.toFloat() ?: 0f
      player?.secondsOfCrossfade = seconds
      result.success(true)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "set crossfade failed")))
      result.error("SET_SECONDS_OF_CROSSFADE_ERROR", e.message, null)
    }
  }

  private fun setAutoplayOnStationChange(call: MethodCall, result: MethodChannel.Result) {
    autoplayOnStationChange = call.argument<Boolean>("enabled") ?: true
    result.success(true)
  }

  private fun getPosition(result: MethodChannel.Result) {
    try {
      val p = player
      if (p != null) {
        val duration = p.currentPlay?.audioFile?.durationInSeconds?.toInt() ?: 0
        val position = if (isPaused) {
          (pausedPosition / 1000).toInt()
        } else if (playbackStartTime > 0) {
          ((System.currentTimeMillis() - playbackStartTime) / 1000).toInt()
        } else 0
        result.success(position.coerceAtMost(duration))
      } else {
        result.success(0)
      }
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get position failed")))
      result.error("GET_POSITION_ERROR", e.message, null)
    }
  }

  private fun getDuration(result: MethodChannel.Result) {
    try {
      val duration = player?.currentPlay?.audioFile?.durationInSeconds?.toInt() ?: 0
      result.success(duration)
    } catch (e: Exception) {
      errorEventSink?.success(mapOf("message" to (e.message ?: "get duration failed")))
      result.error("GET_DURATION_ERROR", e.message, null)
    }
  }

  private fun startProgressUpdates() {
    stopProgressUpdates()
    progressRunnable = object : Runnable {
      override fun run() {
        player?.let { p ->
          val currentPlay = p.currentPlay
          val nowTrackId = try { currentPlay?.audioFile?.id?.toString() } catch (e: Exception) { null }
          if (nowTrackId != null && nowTrackId != currentTrackId) {
            currentTrackId = nowTrackId
            if (isPaused) {
              playbackStartTime = 0
              pausedPosition = 0
            } else {
              playbackStartTime = System.currentTimeMillis()
              pausedPosition = 0
            }
            try {
              trackEventSink?.success(buildPlayMap(currentPlay!!))
            } catch (_: Exception) { /* ignore */ }
          }
          if (currentPlay != null) {
            val duration = currentPlay.audioFile.durationInSeconds.toInt()
            var position = when {
              isPaused -> (pausedPosition / 1000).toInt()
              playbackStartTime > 0 -> ((System.currentTimeMillis() - playbackStartTime) / 1000).toInt()
              else -> 0
            }
            // Apply seek smoothing for a short window after seek (both forward and backward)
            // Backward seeks get a longer window (3s) because SDK position updates async
            lastSeekTargetSec?.let { target ->
              val elapsed = System.currentTimeMillis() - lastSeekTimeMs
              val smoothingWindow = if (target < position) 3000L else 1500L
              if (elapsed in 0..smoothingWindow) {
                // Force position to the requested seek target to avoid bounce from async state/timer updates
                Log.d(TAG, "Progress smoothing: forcing position=$target (calculated=$position, elapsed=${elapsed}ms)")
                position = target
              } else {
                if (lastSeekTargetSec != null) {
                  Log.d(TAG, "Smoothing expired, clearing target")
                }
                lastSeekTargetSec = null
              }
            }
            progressEventSink?.success(mapOf(
              "position" to position.coerceAtMost(duration),
              "duration" to duration
            ))
          }
          val canSkipNow = p.canSkip()
          if (canSkipNow != lastCanSkip) {
            lastCanSkip = canSkipNow
            skipEventSink?.success(mapOf(
              "event" to "skipStatusChanged",
              "canSkip" to canSkipNow
            ))
          }
        }
        handler.postDelayed(this, 1000)
      }
    }
    handler.post(progressRunnable!!)
  }

  private fun stopProgressUpdates() {
    progressRunnable?.let { handler.removeCallbacks(it) }
  }
}
