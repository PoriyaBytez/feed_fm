import Flutter
import UIKit
import FeedMedia

public class FeedFmPlugin: NSObject, FlutterPlugin {
  var player: FMAudioPlayer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "feed_fm", binaryMessenger: registrar.messenger())
    let instance = FeedFmPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "initialize":
      if let args = call.arguments as? [String: Any],
         let token = args["token"] as? String,
         let secret = args["secret"] as? String {
        FMAudioPlayer.setClientToken(token, secret: secret)
        player = FMAudioPlayer.shared()
        result(true)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing token or secret", details: nil))
      }
    case "play":
      FMAudioPlayer.shared().play()
      result(true)
    case "pause":
      FMAudioPlayer.shared().pause()
      result(true)
    case "skip":
      FMAudioPlayer.shared().skip()
      result(true)
    case "stations":
      if let stations = FMAudioPlayer.shared().stationList as? [FMStation] {
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
