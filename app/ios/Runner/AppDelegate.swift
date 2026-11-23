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
  }
}
