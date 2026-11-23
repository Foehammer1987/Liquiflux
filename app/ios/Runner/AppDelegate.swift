import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A video app: its sound plays with the silent switch on, as in the TV app or Apple's
    // own. Only the category is set here; the session becomes active when the player starts
    // its audio, so opening Liquiflux doesn't stop music that's already playing.
    // No background audio: Liquiflux has no picture in picture or audio-only playback on
    // iPhone and iPad, so the player stops when the app leaves the screen.
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    } catch {
      NSLog("Liquiflux: audio session category: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiquifluxBrightness") {
      ScreenBrightness.register(messenger: registrar.messenger())
    }
  }
}

/// The player's brightness gesture (services/screen_brightness.dart). iOS keeps a brightness
/// an app sets until the screen locks, so the one from before the first change is kept and put
/// back by "reset" when the player closes.
enum ScreenBrightness {
  private static var before: CGFloat?

  private static var screen: UIScreen? {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "liquiflux/brightness", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let screen = screen else { return result(nil) }
      switch call.method {
      case "get":
        result(Double(screen.brightness))
      case "set":
        let value = min(max((call.arguments as? Double) ?? 0.5, 0), 1)
        if before == nil { before = screen.brightness }
        screen.brightness = CGFloat(value)
        result(nil)
      case "reset":
        if let b = before { screen.brightness = b }
        before = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
