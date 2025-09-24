import Flutter
import UIKit
import FeedMedia

public class FeedFmPlugin: NSObject, FlutterPlugin {
  private var player: FMAudioPlayer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "feedfm", binaryMessenger: registrar.messenger())
    let instance = FeedFmPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      guard let args = call.arguments as? [String: Any],
      let token = args["token"] as? String,
      let secret = args["secret"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Token or secret missing", details: nil))
        return
      }
      FMAudioPlayer.setClientToken(token, secret: secret)
      self.player = FMAudioPlayer.shared()
      result(true)

    case "play":
      player?.play()
      result(true)

    case "pause":
      player?.pause()
      result(true)

    case "skip":
      player?.skip()
      result(true)

    case "stations":
      if let stations = player?.stationList as? [FMStation] {
        let stationNames = stations.map { $0.name ?? "Unknown" }
        result(stationNames)
      } else {
        result([])
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
