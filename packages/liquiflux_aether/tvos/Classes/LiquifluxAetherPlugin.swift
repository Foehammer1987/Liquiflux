import AetherEngine
import Combine
import Flutter
import UIKit

/// Liquiflux's Apple TV player: one AetherEngine for the app, its picture in an
/// AetherPlayerView behind the (transparent) Flutter view.
///
/// Channel `liquiflux/aether`: open, play, pause, seek, setRate, setVolume, audio, subtitle,
/// externalSubtitle, stop. Events on `liquiflux/aether/events`: maps holding only what
/// changed (state, position, duration, buffering, tracks, cue, error).
public final class LiquifluxAetherPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = LiquifluxAetherPlugin()
    let channel = FlutterMethodChannel(name: "liquiflux/aether", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    FlutterEventChannel(name: "liquiflux/aether/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(plugin)
  }

  private var engine: AetherEngine?
  private var view: AetherPlayerView?
  private var sink: FlutterEventSink?
  private var subscriptions = Set<AnyCancellable>()
  private var loadTask: Task<Void, Never>?
  private var lastPosition = -1.0
  /// A play or pause that came while a load was still running: the engine ignores transport
  /// calls then, so it is applied once the load returns.
  private var pendingPlay: Bool?
  private var loading = false

  // MARK: FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func send(_ event: [String: Any]) {
    sink?(event)
  }

  // MARK: Methods

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    MainActor.assumeIsolated {
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "open":
        guard let s = args["url"] as? String, let url = URL(string: s) else {
          result(FlutterError(code: "bad-url", message: "No address to play", details: nil))
          return
        }
        do {
          let engine = try ensureEngine()
          var options = LoadOptions()
          options.httpHeaders = args["headers"] as? [String: String] ?? [:]
          options.autoplay = args["play"] as? Bool ?? true
          let start = args["start"] as? Double
          lastPosition = -1
          pendingPlay = nil
          loading = true
          loadTask?.cancel()
          loadTask = Task { @MainActor [weak self] in
            do {
              try await engine.load(url: url, startPosition: (start ?? 0) > 0 ? start : nil, options: options)
              guard let self, !Task.isCancelled else { return }
              self.loading = false
              switch self.pendingPlay {
              case true?: engine.play()
              case false?: engine.pause()
              case nil: break
              }
              self.pendingPlay = nil
            } catch is CancellationError {
            } catch {
              self?.loading = false
              self?.send(["error": "\(error.localizedDescription)"])
            }
          }
          result(nil)
        } catch {
          result(FlutterError(code: "engine", message: "AetherEngine could not start: \(error.localizedDescription)", details: nil))
        }
      case "play":
        if loading { pendingPlay = true }
        engine?.play()
        result(nil)
      case "pause":
        if loading { pendingPlay = false }
        engine?.pause()
        result(nil)
      case "seek":
        let to = args["position"] as? Double ?? 0
        Task { @MainActor [weak self] in
          await self?.engine?.seek(to: max(0, to))
          result(nil)
        }
      case "setRate":
        engine?.setRate(Float(args["rate"] as? Double ?? 1))
        result(nil)
      case "setVolume":
        engine?.volume = Float(args["volume"] as? Double ?? 1)
        result(nil)
      case "audio":
        if let id = args["id"] as? Int { engine?.selectAudioTrack(index: id) }
        result(nil)
      case "subtitle":
        if let id = args["id"] as? Int, id >= 0 {
          engine?.selectSubtitleTrack(index: id)
        } else {
          engine?.clearSubtitle()
        }
        result(nil)
      case "externalSubtitle":
        guard let engine, let s = args["url"] as? String, let url = URL(string: s) else {
          result(nil)
          return
        }
        let track = engine.addExternalSubtitleTrack(
          ExternalSubtitleTrack(url: url, name: args["title"] as? String, language: args["language"] as? String))
        engine.selectSubtitleTrack(index: track.id)
        result(track.id)
      case "stop":
        loadTask?.cancel()
        engine?.stop()
        view?.isHidden = true
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: Engine and view

  @MainActor
  private func ensureEngine() throws -> AetherEngine {
    if let engine {
      view?.isHidden = false
      attachView()
      return engine
    }
    let engine = try AetherEngine()
    self.engine = engine
    let view = AetherPlayerView(frame: .zero)
    view.backgroundColor = .black
    self.view = view
    engine.bind(view: view)
    attachView()
    observe(engine)
    return engine
  }

  /// Puts the player view in the window right under the Flutter view and lets the Flutter
  /// view show through where the app paints nothing.
  @MainActor
  private func attachView() {
    guard let view else { return }
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first,
      let flutter = window.rootViewController as? FlutterViewController
    else { return }
    flutter.isViewOpaque = false
    flutter.view.backgroundColor = .clear
    // The Flutter view's own parent (UIKit may wrap it in a transition view): the player goes
    // right below it there, never on top.
    guard let parent = flutter.view.superview else { return }
    if view.superview !== parent {
      view.removeFromSuperview()
      view.frame = parent.bounds
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      parent.insertSubview(view, belowSubview: flutter.view)
    }
    NSLog("[liquiflux_aether] player view under %@ (flutter view is %@), window %@", String(describing: type(of: parent)), String(describing: type(of: flutter.view!)), String(describing: type(of: window)))
  }

  @MainActor
  private func observe(_ engine: AetherEngine) {
    engine.$state
      .removeDuplicates()
      .sink { [weak self] state in
        switch state {
        case .idle: self?.send(["state": "idle"])
        case .loading: self?.send(["state": "loading"])
        case .playing: self?.send(["state": "playing"])
        case .paused: self?.send(["state": "paused"])
        case .seeking: self?.send(["state": "seeking"])
        case .ended: self?.send(["state": "ended"])
        case .error(let message): self?.send(["state": "error", "error": message])
        }
      }
      .store(in: &subscriptions)
    engine.clock.$currentTime
      .sink { [weak self] t in
        guard let self, abs(t - self.lastPosition) >= 0.2 else { return }
        self.lastPosition = t
        self.send(["position": t])
      }
      .store(in: &subscriptions)
    engine.$duration
      .removeDuplicates()
      .sink { [weak self] d in self?.send(["duration": d]) }
      .store(in: &subscriptions)
    engine.$isBuffering
      .removeDuplicates()
      .sink { [weak self] b in self?.send(["buffering": b]) }
      .store(in: &subscriptions)
    engine.$audioTracks
      .sink { [weak self] tracks in self?.send(["audioTracks": tracks.map(Self.track)]) }
      .store(in: &subscriptions)
    engine.$subtitleTracks
      .sink { [weak self] tracks in self?.send(["subtitleTracks": tracks.map(Self.track)]) }
      .store(in: &subscriptions)
    engine.$activeAudioTrackIndex
      .sink { [weak self] id in self?.send(["activeAudio": id ?? -1]) }
      .store(in: &subscriptions)
    engine.$activeSubtitleTrackIndex
      .sink { [weak self] id in self?.send(["activeSubtitle": id ?? -1]) }
      .store(in: &subscriptions)
    // Text cues are drawn by the app; picture-based ones would need an image overlay (not yet).
    engine.$subtitleCues
      .combineLatest(engine.clock.$sourceTime)
      .map { cues, t in
        cues.filter { $0.startTime <= t && t < $0.endTime }
          .compactMap { cue -> String? in
            switch cue.body {
            case .text(let s): return s
            case .richText(let runs): return runs.map(\.text).joined()
            case .image: return nil
            }
          }
          .joined(separator: "\n")
      }
      .removeDuplicates()
      .sink { [weak self] text in self?.send(["cue": text]) }
      .store(in: &subscriptions)
  }

  private static func track(_ t: TrackInfo) -> [String: Any] {
    var m: [String: Any] = ["id": t.id, "name": t.name, "codec": t.codec, "channels": t.channels, "default": t.isDefault]
    if let l = t.language { m["language"] = l }
    return m
  }
}
