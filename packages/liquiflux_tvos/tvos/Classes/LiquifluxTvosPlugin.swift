import Flutter
import UIKit

/// Apple TV services for Liquiflux on channel `liquiflux/tvos`. See README.md.
public final class LiquifluxTvosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "liquiflux/tvos", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LiquifluxTvosPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "defaultsGet":
      guard let key = args["key"] as? String else { return result(nil) }
      result(UserDefaults.standard.string(forKey: key))
    case "defaultsSet":
      guard let key = args["key"] as? String else { return result(nil) }
      if let value = args["value"] as? String {
        UserDefaults.standard.set(value, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
