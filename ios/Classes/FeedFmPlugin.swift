import Flutter
import UIKit
import FeedMedia
import AVFoundation

// ======================================================
// CONFIG – FALLBACK STATIONS (if SDK stations not available)
// ======================================================
private let iosStationNames: [String] = [
    "Top Hits",
    "Pop",
    "Rock",
    "Hip Hop",
    "Electronic"
]

// ======================================================
// Event Stream Handler
// ======================================================
class EventStreamHandler: NSObject, FlutterStreamHandler {
    let onListenCallback: (FlutterEventSink?) -> Void
    let onCancelCallback: () -> Void

    init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
        self.onListenCallback = onListen
        self.onCancelCallback = onCancel
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelCallback()
        return nil
    }
}

// ======================================================
// MAIN PLUGIN
// ======================================================
public class FeedFmPlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel!

    private var stateEventSink: FlutterEventSink?
    private var trackEventSink: FlutterEventSink?
    private var progressEventSink: FlutterEventSink?
    private var skipEventSink: FlutterEventSink?
    private var stationEventSink: FlutterEventSink?
    private var errorEventSink: FlutterEventSink?

    private var playbackStartTime: TimeInterval = 0
    private var pausedPositionMs: TimeInterval = 0
    private var isPaused: Bool = true
    private var lastCanSkip: Bool = false
    private var currentVolume: Double = 1.0
    private var autoplayOnStationChange: Bool = true
    private var lastTrackId: String = ""
    private var hasSelectedStation: Bool = false // Track if station was manually selected

    private var pollTimer: Timer?
    private var stateObserver: NSObjectProtocol?

    // ======================================================
    // REGISTER
    // ======================================================
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FeedFmPlugin()

        instance.methodChannel = FlutterMethodChannel(name: "feed_fm", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)

        let stateChannel = FlutterEventChannel(name: "feed_fm/state_events", binaryMessenger: registrar.messenger())
        let trackChannel = FlutterEventChannel(name: "feed_fm/track_events", binaryMessenger: registrar.messenger())
        let progressChannel = FlutterEventChannel(name: "feed_fm/progress_events", binaryMessenger: registrar.messenger())
        let skipChannel = FlutterEventChannel(name: "feed_fm/skip_events", binaryMessenger: registrar.messenger())
        let stationChannel = FlutterEventChannel(name: "feed_fm/station_events", binaryMessenger: registrar.messenger())
        let errorChannel = FlutterEventChannel(name: "feed_fm/error_events", binaryMessenger: registrar.messenger())

        stateChannel.setStreamHandler(EventStreamHandler(onListen: { instance.stateEventSink = $0; instance.ensurePolling() }, onCancel: { instance.stateEventSink = nil; instance.stopPollingIfUnused() }))
        trackChannel.setStreamHandler(EventStreamHandler(onListen: { instance.trackEventSink = $0; instance.ensurePolling() }, onCancel: { instance.trackEventSink = nil; instance.stopPollingIfUnused() }))
        progressChannel.setStreamHandler(EventStreamHandler(onListen: { instance.progressEventSink = $0; instance.ensurePolling() }, onCancel: { instance.progressEventSink = nil; instance.stopPollingIfUnused() }))
        skipChannel.setStreamHandler(EventStreamHandler(onListen: { instance.skipEventSink = $0; instance.ensurePolling() }, onCancel: { instance.skipEventSink = nil; instance.stopPollingIfUnused() }))
        stationChannel.setStreamHandler(EventStreamHandler(onListen: { instance.stationEventSink = $0; instance.ensurePolling() }, onCancel: { instance.stationEventSink = nil; instance.stopPollingIfUnused() }))
        errorChannel.setStreamHandler(EventStreamHandler(onListen: { instance.errorEventSink = $0; instance.ensurePolling() }, onCancel: { instance.errorEventSink = nil; instance.stopPollingIfUnused() }))
    }

    // ======================================================
    // METHOD HANDLER
    // ======================================================
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let player = FMAudioPlayer.shared()

        switch call.method {

        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let token = args["token"] as? String,
                  let secret = args["secret"] as? String else {
                NSLog("[FeedFmPlugin] ❌ ERROR: Missing token or secret in initialize()")
                result(false); return
            }

            NSLog("[FeedFmPlugin] 🔑 Initializing with token: \(token.prefix(10))... secret: \(secret.prefix(10))...")
            FMAudioPlayer.setClientToken(token, secret: secret)
            NSLog("[FeedFmPlugin] ✅ setClientToken() called")

            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
                try AVAudioSession.sharedInstance().setActive(true)
                NSLog("[FeedFmPlugin] ✅ Audio session activated")
            } catch {
                NSLog("[FeedFmPlugin] ❌ Audio session error: \(error)")
            }

            // Set up state change observer
            setupStateObserver()

            NSLog("[FeedFmPlugin] 🎵 Calling whenAvailable()...")
            // Check availability and log, then auto-select first station
            player.whenAvailable({
                NSLog("[FeedFmPlugin] ✅✅✅ Music is available! Station count: \(player.stationList.count)")

                // Log all available stations
                for i in 0..<player.stationList.count {
                    if let station = player.stationList[i] as? FMStation {
                        NSLog("[FeedFmPlugin]   Station \(i): \(station.name)")
                    }
                }

                // Auto-select first station if none selected
                if player.stationList.count > 0 && !self.hasSelectedStation {
                    let firstStation = player.stationList[0] as! FMStation
                    NSLog("[FeedFmPlugin] 🎵 Auto-selecting first station: \(firstStation.name)")
                    let success = player.setActiveStation(firstStation, withCrossfade: false)
                    NSLog("[FeedFmPlugin] Station selection success: \(success)")
                    self.hasSelectedStation = true

                    // Prepare the player after selecting station
                    player.prepareToPlay()
                    NSLog("[FeedFmPlugin] Called prepareToPlay() after auto-selection")
                }
            }, notAvailable: {
                NSLog("[FeedFmPlugin] ❌❌❌ Music is NOT available - check your token/secret or Feed.fm account configuration")
                NSLog("[FeedFmPlugin] Token starts with: \(token.prefix(15))...")
                NSLog("[FeedFmPlugin] Secret starts with: \(secret.prefix(15))...")
            })

            NSLog("[FeedFmPlugin] whenAvailable() registered, waiting for callback...")

            _ = setVolumeInternal(currentVolume)
            ensurePolling()

            NSLog("[FeedFmPlugin] ✅ Initialize complete, returning true")
            result(true)

        // ---------- PLAYBACK ----------
        case "play":
            NSLog("[FeedFmPlugin] 🎮 play() called")
            NSLog("[FeedFmPlugin] Current state: \(stateToString(player.playbackState))")
            NSLog("[FeedFmPlugin] Active station: \(player.activeStation.name)")
            NSLog("[FeedFmPlugin] Station list count: \(player.stationList.count)")

            // Check if station list is available
            if player.stationList.count == 0 {
                NSLog("[FeedFmPlugin] ⚠️ No stations available yet")
                errorEventSink?(["message": "Music not available yet. Please wait..."])

                // Wait for stations to load, then try again
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    NSLog("[FeedFmPlugin] Retrying after waiting for stations...")
                    if player.stationList.count > 0 {
                        NSLog("[FeedFmPlugin] ✅ Stations now available, trying to play")
                        // Auto-select first station and play
                        if !self.hasSelectedStation {
                            let firstStation = player.stationList[0] as! FMStation
                            _ = player.setActiveStation(firstStation, withCrossfade: false)
                            self.hasSelectedStation = true
                            NSLog("[FeedFmPlugin] Selected station: \(firstStation.name)")
                        }
                        player.prepareToPlay()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            player.play()
                            NSLog("[FeedFmPlugin] Started playback after retry")
                        }
                    } else {
                        NSLog("[FeedFmPlugin] ❌ Stations still not available after waiting")
                    }
                }
                result(true)
                return
            }

            // If no station selected, auto-select the first one
            if !hasSelectedStation || player.activeStation.name.isEmpty {
                NSLog("[FeedFmPlugin] 🎵 No station selected, auto-selecting first station")
                let firstStation = player.stationList[0] as! FMStation
                let success = player.setActiveStation(firstStation, withCrossfade: false)
                hasSelectedStation = true
                NSLog("[FeedFmPlugin] Auto-selected station: \(firstStation.name), success: \(success)")
            }

            let currentState = player.playbackState
            NSLog("[FeedFmPlugin] State after station check: \(stateToString(currentState))")

            // Always reset timing before starting playback so it begins at 0
            playbackStartTime = Date().timeIntervalSince1970
            pausedPositionMs = 0
            isPaused = false

            // If already playing, do nothing
            if currentState == .playing {
                NSLog("[FeedFmPlugin] ✅ Already playing")
                result(true)
                return
            }

            // If ready to play, just play
            if currentState == .readyToPlay {
                NSLog("[FeedFmPlugin] ▶️ Ready to play, calling play()")
                player.play()
                result(true)
                return
            }

            // If waiting for item or uninitialized, prepare first
            if currentState == .waitingForItem || currentState == .uninitialized {
                NSLog("[FeedFmPlugin] ⏳ Preparing to play (state: \(stateToString(currentState)))...")
                player.prepareToPlay()
                // Wait longer for music to be queued
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let newState = player.playbackState
                    NSLog("[FeedFmPlugin] After 2s prepare, state: \(self.stateToString(newState))")
                    if newState == .readyToPlay {
                        NSLog("[FeedFmPlugin] ▶️ Now ready, calling play()")
                        player.play()
                    } else if newState != .playing {
                        NSLog("[FeedFmPlugin] ⚠️ Still not ready, calling play() anyway")
                        player.play()
                        // One more retry after 2 more seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if player.playbackState != .playing {
                                NSLog("[FeedFmPlugin] 🔄 Final retry: calling play() again")
                                player.play()
                            }
                        }
                    }
                }
            } else {
                // For other states, just try to play
                NSLog("[FeedFmPlugin] ▶️ Calling play() directly for state: \(stateToString(currentState))")
                player.play()
            }

            result(true)

        case "pause":
            player.pause()
            result(true)

        case "stop":
            player.stop()
            resetProgress()
            result(true)

        case "togglePlayPause":
            let state = player.playbackState
            if state == .playing {
                player.pause()
            } else {
                player.play()
            }
            result(true)

        case "skip", "requestSkip":
            player.skip()
            resetProgress()
            result(true)

        // ---------- STATIONS ----------
        case "getStations":
            getStationsFromSDK(result: result)

        case "selectStationByIndex":
            let idx = (call.arguments as? [String: Any])?["index"] as? Int ?? -1
            selectStationByIndex(idx, result: result)

        case "selectStationById":
            let sid = (call.arguments as? [String: Any])?["stationId"] as? String ?? ""
            selectStationById(sid, result: result)

        case "getCurrentStation":
            let station = player.activeStation
            var description = ""
            if let options = station.options, let desc = options["description"] as? String {
                description = desc
            }
            result(["id": station.name, "name": station.name, "description": description])

        case "getActiveStationId":
            result(player.activeStation.name)

        case "setAutoplayOnStationChange":
            autoplayOnStationChange = ((call.arguments as? [String: Any])?["enabled"] as? Bool) ?? true
            result(true)

        // ---------- STATE ----------
        case "getPlaybackState":
            result(stateToString(player.playbackState))

        case "isAvailable":
            let stationList = player.stationList
            result(stationList.count > 0)

        case "canSkip":
            result(player.canSkip)

        // ---------- VOLUME ----------
        case "setVolume":
            let v = (call.arguments as? [String: Any])?["volume"] as? Double ?? 1.0
            currentVolume = v
            _ = setVolumeInternal(v)
            result(true)

        case "getVolume":
            result(currentVolume)

        // ---------- TRACK ----------
        case "getCurrentTrack":
            let playData = playMap()
            result(["play": playData])

        // ---------- PROGRESS ----------
        case "getPosition":
            result(currentPositionSeconds())

        case "getDuration":
            // Get duration from current item or player
            if let currentItem = player.currentItem {
                let dur = Int(currentItem.duration)
                result(dur > 0 ? dur : 0)
            } else {
                let dur = Int(player.currentItemDuration)
                result(dur > 0 ? dur : 0)
            }

        // ---------- TRACK RATING ----------
        case "like":
            player.like()
            result(true)

        case "dislike":
            player.dislike()
            result(true)

        case "unlike":
            player.unlike()
            result(true)

        // ---------- MIX / CROSSFADES ----------
        case "mixCrossfade":
            result(true)

        case "setSecondsOfCrossfade":
            let seconds = (call.arguments as? [String: Any])?["seconds"] as? Int ?? 0
            player.secondsOfCrossfade = Float(seconds)
            result(true)

        case "getSecondsOfCrossfade":
            result(Double(player.secondsOfCrossfade))

        // ---------- CLIENT INFO ----------
        case "getClientId":
            result("")

        // ---------- SEEKING (NOT SUPPORTED BY iOS SDK) ----------
        case "supportsSeek":
            result(false)

        case "seekTo":
            result(false)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ======================================================
    // STATE OBSERVER
    // ======================================================
    private func setupStateObserver() {
        // Remove existing observer if any
        if let observer = stateObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Listen to actual player state changes
        stateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.FMAudioPlayerPlaybackStateDidChange,
            object: FMAudioPlayer.shared(),
            queue: .main
        ) { [weak self] _ in
            self?.onPlayerStateChanged()
        }
    }

    private func onPlayerStateChanged() {
        let player = FMAudioPlayer.shared()
        let state = stateToString(player.playbackState)

        NSLog("[FeedFmPlugin] State changed to: \(state)")

        stateEventSink?(["event": "stateChanged", "state": state])

        // Update internal state tracking
        switch player.playbackState {
        case .playing:
            // If resuming from pause, anchor start time so elapsed excludes paused gap
            if pausedPositionMs > 0 {
                playbackStartTime = Date().timeIntervalSince1970 - (pausedPositionMs / 1000)
                pausedPositionMs = 0
            } else if playbackStartTime == 0 {
                playbackStartTime = Date().timeIntervalSince1970
            }
            isPaused = false
            NSLog("[FeedFmPlugin] Now playing - currentItem: \(player.currentItem != nil ? "exists" : "nil")")
        case .paused:
            isPaused = true
            // Use SDK-reported playback time when available for precise pause position
            let sdkPos = player.currentPlaybackTime
            if sdkPos > 0 {
                pausedPositionMs = sdkPos * 1000
            } else if playbackStartTime > 0 {
                pausedPositionMs = (Date().timeIntervalSince1970 - playbackStartTime) * 1000
            }
        case .complete:
            playbackStartTime = 0
            pausedPositionMs = 0
            isPaused = true
        default:
            break
        }

        // Check skip availability
        let canSkip = player.canSkip
        if canSkip != lastCanSkip {
            lastCanSkip = canSkip
            skipEventSink?(["event": "skipStatusChanged", "canSkip": canSkip])
        }

        // Emit track change if current item changed
        if let currentItem = player.currentItem {
            let trackId = currentItem.id ?? ""
            if !trackId.isEmpty && trackId != lastTrackId {
                lastTrackId = trackId
                // Reset position tracking for new track so it always starts at 0
                playbackStartTime = Date().timeIntervalSince1970
                pausedPositionMs = 0
                isPaused = (player.playbackState == .paused)
                NSLog("[FeedFmPlugin] Current item: \(currentItem.name ?? "no name"), duration: \(currentItem.duration)")
                trackEventSink?(buildTrackMap(from: currentItem))
            }
        }
    }

    // ======================================================
    // STATION MANAGEMENT
    // ======================================================
    private func getStationsFromSDK(result: @escaping FlutterResult) {
        let player = FMAudioPlayer.shared()
        let stationList = player.stationList

        if stationList.count > 0 {
            let stations = buildStationsArray(from: stationList)
            result(stations)
            return
        }

        // Stations not ready yet - poll for them (like Android does)
        waitForStationsThenReturn(result: result, maxAttempts: 20, delayMs: 150)
    }

    private func buildStationsArray(from stationList: FMStationArray) -> [[String: Any]] {
        var stations: [[String: Any]] = []
        let count = stationList.count
        for index in 0..<count {
            if let station = stationList[index] as? FMStation {
                let stationName = station.name
                var description = ""
                var image = ""
                if let options = station.options {
                    if let desc = options["description"] as? String {
                        description = desc
                    }
                    if let img = options["image"] as? String {
                        image = img
                    }
                }

                stations.append([
                    "index": index,
                    "id": stationName,
                    "name": stationName,
                    "description": description,
                    "image": image
                ])
            }
        }
        return stations
    }

    private func waitForStationsThenReturn(result: @escaping FlutterResult, maxAttempts: Int, delayMs: Int) {
        let player = FMAudioPlayer.shared()
        var attemptsLeft = maxAttempts

        func poll() {
            let stationList = player.stationList
            if stationList.count > 0 {
                let stations = buildStationsArray(from: stationList)
                result(stations)
            } else if attemptsLeft > 0 {
                attemptsLeft -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
                    poll()
                }
            } else {
                // Fallback to configured station names
                result(iosStationNames.enumerated().map {
                    ["index": $0.offset, "id": $0.element, "name": $0.element, "description": "", "image": ""]
                })
            }
        }
        poll()
    }

    private func selectStationByIndex(_ index: Int, result: @escaping FlutterResult) {
        let player = FMAudioPlayer.shared()
        guard index >= 0 else {
            result(false)
            return
        }

        let stationList = player.stationList
        if index < stationList.count {
            let station = stationList[index] as! FMStation
            selectStation(station, result: result)
        } else {
            // Stations not ready yet - poll for them
            var attemptsLeft = 20
            func poll() {
                let stationList = player.stationList
                if index < stationList.count {
                    let station = stationList[index] as! FMStation
                    self.selectStation(station, result: result)
                } else if attemptsLeft > 0 {
                    attemptsLeft -= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
                        poll()
                    }
                } else {
                    result(false)
                }
            }
            poll()
        }
    }

    private func selectStationById(_ stationId: String, result: @escaping FlutterResult) {
        let player = FMAudioPlayer.shared()
        let stationList = player.stationList

        let count = stationList.count
        for index in 0..<count {
            let station = stationList[index] as! FMStation
            if station.name == stationId {
                return selectStation(station, result: result)
            }
        }

        // Station not found
        result(false)
    }

    private func selectStation(_ station: FMStation, result: @escaping FlutterResult) {
        let name = station.name
        NSLog("[FeedFm] Selecting station: \(name), current state: \(stateToString(FMAudioPlayer.shared().playbackState))")

        let player = FMAudioPlayer.shared()
        let success = player.setActiveStation(station, withCrossfade: false)

        if success {
            hasSelectedStation = true // Mark that station was explicitly selected
            // Reset timing to ensure next playback starts at 0
            player.stop()
            playbackStartTime = 0
            pausedPositionMs = 0
            isPaused = true
            lastTrackId = ""

            var description = ""
            if let options = station.options, let desc = options["description"] as? String {
                description = desc
            }

            stationEventSink?(["id": name, "name": name, "description": description])

            if autoplayOnStationChange {
                NSLog("[FeedFm] Autoplay enabled, preparing station...")
                // Prepare to play first to ensure music is ready
                player.prepareToPlay()
                // Wait for prepareToPlay to complete and station to be ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let currentState = player.playbackState
                    NSLog("[FeedFm] After prepare, state: \(self.stateToString(currentState))")
                    if currentState == .readyToPlay || currentState == .waitingForItem {
                        NSLog("[FeedFm] Station ready, starting playback")
                        player.play()
                    } else {
                        NSLog("[FeedFm] Station not ready yet (state: \(self.stateToString(currentState))), will retry...")
                        // Retry after another delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if player.playbackState != .playing {
                                NSLog("[FeedFm] Retry: calling play()")
                                player.play()
                            }
                        }
                    }
                }
            }

            resetProgress()
            result(true)
        } else {
            NSLog("[FeedFm] Failed to set active station")
            result(false)
        }
    }

    // ======================================================
    // POLLING
    // ======================================================
    private func ensurePolling() {
        if pollTimer != nil { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollTick()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopPollingIfUnused() {
        if stateEventSink == nil && trackEventSink == nil && progressEventSink == nil &&
            skipEventSink == nil && stationEventSink == nil && errorEventSink == nil {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func pollTick() {
        let player = FMAudioPlayer.shared()
        let state = stateToString(player.playbackState)
        stateEventSink?(["event": "stateChanged", "state": state])

        if player.playbackState == .playing {
            if playbackStartTime == 0 {
                playbackStartTime = Date().timeIntervalSince1970
            }
            isPaused = false
        } else {
            isPaused = true
        }

        // Get actual duration from current item
        let duration: Int
        if let currentItem = player.currentItem {
            let dur = Int(currentItem.duration)
            duration = dur > 0 ? dur : 0
        } else {
            let dur = Int(player.currentItemDuration)
            duration = dur > 0 ? dur : 0
        }

        // Only emit progress if we have a valid duration or are playing
        if duration > 0 || player.playbackState == .playing || player.playbackState == .readyToPlay {
            progressEventSink?(["position": currentPositionSeconds(), "duration": duration])
        }

        let canSkip = player.canSkip
        if canSkip != lastCanSkip {
            lastCanSkip = canSkip
            skipEventSink?(["event": "skipStatusChanged", "canSkip": canSkip])
        }

        // Emit track info if available and track changed
        if let currentItem = player.currentItem {
            let trackId = currentItem.id ?? ""
            if !trackId.isEmpty && trackId != lastTrackId {
                lastTrackId = trackId
                // Reset position tracking for new track so it always starts at 0
                playbackStartTime = Date().timeIntervalSince1970
                pausedPositionMs = 0
                isPaused = (player.playbackState == .paused)
                trackEventSink?(buildTrackMap(from: currentItem))
            }
        }
    }

    // ======================================================
    // DATA BUILDERS
    // ======================================================
    private func buildTrackMap(from audioItem: FMAudioItem) -> [String: Any] {
        let station = FMAudioPlayer.shared().activeStation
        let stationName = station.name

        // FMAudioItem has name, artist, album as strings (not objects)
        let trackDict: [String: Any] = [
            "id": "",
            "title": audioItem.name ?? ""
        ]

        let releaseDict: [String: Any] = [
            "id": "",
            "title": audioItem.album ?? ""
        ]

        let artistDict: [String: Any] = [
            "id": "",
            "name": audioItem.artist ?? ""
        ]

        var extraDict: [String: Any] = [
            "artwork": "",
            "image": "",
            "background_image_url": "",
            "caption": ""
        ]

        // Try to get artwork from metadata
        if let metadata = audioItem.metadata {
            if let artwork = metadata["artwork"] as? String {
                extraDict["artwork"] = artwork
            }
            if let image = metadata["image"] as? String {
                extraDict["image"] = image
            }
            if let bgImage = metadata["background_image_url"] as? String {
                extraDict["background_image_url"] = bgImage
            }
            if let caption = metadata["caption"] as? String {
                extraDict["caption"] = caption
            }
        }

        let audioFileDict: [String: Any] = [
            "id": audioItem.id ?? "",
            "duration_in_seconds": Int(audioItem.duration),
            "codec": audioItem.codec ?? "",
            "track": trackDict,
            "release": releaseDict,
            "artist": artistDict,
            "url": audioItem.contentUrl?.absoluteString ?? "",
            "bitrate": Int(audioItem.bitrate),
            "liked": audioItem.liked,
            "replaygain_track_gain": audioItem.replayGain,
            "extra": extraDict
        ]

        let stationDict: [String: Any] = [
            "id": stationName,
            "name": stationName,
            "pre_gain": station.preGain
        ]

        return [
            "id": audioItem.playId ?? audioItem.id ?? "",
            "audio_file": audioFileDict,
            "station": stationDict
        ]
    }

    private func playMap() -> [String: Any] {
        let player = FMAudioPlayer.shared()

        // If we have a current item, use it
        if let currentItem = player.currentItem {
            return buildTrackMap(from: currentItem)
        }

        // Otherwise return empty structure
        let station = player.activeStation
        let stationName = station.name

        return [
            "id": "",
            "audio_file": [
                "id": "",
                "duration_in_seconds": 0,
                "codec": "",
                "track": ["id": "", "title": ""],
                "release": ["id": "", "title": ""],
                "artist": ["id": "", "name": ""],
                "url": "",
                "bitrate": 0,
                "liked": false,
                "replaygain_track_gain": 0.0,
                "extra": [
                    "artwork": "",
                    "image": "",
                    "background_image_url": "",
                    "caption": ""
                ]
            ],
            "station": [
                "id": stationName,
                "name": stationName,
                "pre_gain": station.preGain
            ]
        ]
    }

    // ======================================================
    // HELPERS
    // ======================================================
    private func resetProgress() {
        playbackStartTime = Date().timeIntervalSince1970
        pausedPositionMs = 0
        isPaused = false
    }

    private func stateToString(_ state: FMAudioPlayerPlaybackState) -> String {
        switch state {
        case .uninitialized:
            return "IDLE"
        case .unavailable:
            return "UNAVAILABLE"
        case .waitingForItem:
            return "WAITING"
        case .readyToPlay:
            return "READY"
        case .playing:
            return "PLAYING"
        case .paused:
            return "PAUSED"
        case .stalled:
            return "STALLED"
        case .requestingSkip:
            return "REQUESTING_SKIP"
        case .complete:
            return "STOPPED"
        @unknown default:
            return "IDLE"
        }
    }

    private func currentPositionSeconds() -> Int {
        // Prefer SDK-reported playback time when available
        let sdkPos = FMAudioPlayer.shared().currentPlaybackTime
        if sdkPos > 0 {
            return Int(sdkPos)
        }
        if isPaused { return Int(pausedPositionMs / 1000) }
        let elapsed = Date().timeIntervalSince1970 - playbackStartTime
        return max(0, Int(elapsed))
    }

    private func setVolumeInternal(_ volume: Double) -> Any? {
        let sel = NSSelectorFromString("setVolume:")
        if FMAudioPlayer.shared().responds(to: sel) {
            return FMAudioPlayer.shared().perform(sel, with: NSNumber(value: volume))
        }
        return nil
    }

    deinit {
        if let observer = stateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}