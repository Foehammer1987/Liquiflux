import AVFoundation
import AVKit
import AetherEngine
import Combine
import Flutter
import MediaPlayer
import UIKit

/// Liquiflux's Apple TV player: one AetherEngine for the app, its picture in an
/// AetherPlayerView behind the (transparent) Flutter view.
///
/// Channel `liquiflux/aether`: open, play, pause, seek, setRate, setVolume, audio, subtitle,
/// externalSubtitle, fit, nowPlaying, stop.
///
/// The engine owns the system Now Playing card (the Apple TV's overlay, Control Center on a
/// paired iPhone) and answers its transport commands itself; the app hands it the title and
/// artwork with `nowPlaying`, and sees play, pause and seeks the remote made through the
/// usual state and position events. Events on `liquiflux/aether/events`: maps holding only what
/// changed (state, position, duration, buffering, tracks, cue, error).
public final class LiquifluxAetherPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = LiquifluxAetherPlugin()
    let channel = FlutterMethodChannel(name: "liquiflux/aether", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    FlutterEventChannel(name: "liquiflux/aether/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(plugin)
    // A probe launch (LIQUIFLUX_PROBE in the environment, see app/lib/services/probe.dart) also
    // copies the engine's log into tmp/aetherengine.log: os_log isn't on a release build's
    // console, and the file can be copied off the Apple TV with devicectl.
    if ProcessInfo.processInfo.environment["LIQUIFLUX_PROBE"] != nil { EngineLogFile.start() }
  }

  private var engine: AetherEngine?
  private let subtitleImages = SubtitleImageView()
  private var view: AetherPlayerView?
  private var sink: FlutterEventSink?
  private var subscriptions = Set<AnyCancellable>()
  private var loadTask: Task<Void, Never>?
  private var lastPosition = -1.0
  /// A play or pause that came while a load was still running: the engine ignores transport
  /// calls then, so it is applied once the load returns.
  private var pendingPlay: Bool?
  private var loading = false
  /// Counts stops and opens, so a delayed display-mode reset knows whether it's still wanted.
  private var stops = 0
  /// The fit asked for before the engine existed, applied when it's made.
  private var pendingGravity: AVLayerVideoGravity = .resizeAspect
  /// The artwork request for the current Now Playing card, replaced by the next title's.
  private var artworkTask: URLSessionDataTask?

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
        stops += 1
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
              self.checkNowPlaying(engine)
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
      case "fit":
        // Liquiflux's Aspect setting: fit (letterbox), fill (crop to fill), stretch.
        let gravity: AVLayerVideoGravity = switch args["aspect"] as? String {
        case "fill": .resizeAspectFill
        case "stretch": .resize
        default: .resizeAspect
        }
        if let engine { engine.videoGravity = gravity }
        pendingGravity = gravity
        result(nil)
      case "nowPlaying":
        nowPlaying(args)
        result(nil)
      case "stop":
        subtitleImages.show([])
        loadTask?.cancel()
        // The TV leaves its HDR or Dolby Vision mode only once the app has finished leaving
        // the player: a mode switch freezes the screen for a moment, and one started now caught
        // the page's slide back in half-way and held it there until the switch ended.
        engine?.stop(resetDisplayCriteria: false, finalTeardown: true)
        view?.isHidden = true
        stops += 1
        let stop = stops
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
          // Not if another title opened since (it keeps or sets the mode itself).
          guard let self, self.stops == stop, !self.loading else { return }
          self.resetDisplayMode()
        }
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
    // The engine publishes Now Playing for every route and answers the remote's commands.
    engine.ownsVideoNowPlayingSession = true
    engine.ownsVideoNowPlayingCommands = true
    engine.ownsSoftwareNowPlaying = true
    engine.videoGravity = pendingGravity
    self.engine = engine
    let view = AetherPlayerView(frame: .zero)
    view.backgroundColor = .black
    self.view = view
    // Picture-based subtitles (PGS, VobSub, DVB) are drawn here, over the video and under the
    // app, so a title keeps its own picture (and HDR) instead of Plex burning them in.
    subtitleImages.frame = view.bounds
    subtitleImages.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(subtitleImages)
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
      .sink { [weak self] cues, t in
        self?.subtitleImages.show(cues.filter { $0.startTime <= t && t < $0.endTime }.compactMap { cue in
          if case .image(let image) = cue.body { return image }
          return nil
        })
      }
      .store(in: &subscriptions)
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

  /// The card's title, subtitle (show and episode) and artwork, fetched here so the token in
  /// its address never leaves the app.
  @MainActor
  private func nowPlaying(_ args: [String: Any]) {
    guard let engine = try? ensureEngine() else { return }
    var info: [String: Any] = [:]
    if let title = args["title"] as? String, !title.isEmpty { info[MPMediaItemPropertyTitle] = title }
    if let subtitle = args["subtitle"] as? String, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
    engine.setNowPlayingInfo(info)
    artworkTask?.cancel()
    guard let s = args["artwork"] as? String, let url = URL(string: s) else { return }
    artworkTask = URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, let engine = self.engine else { return }
        var withArt = info
        withArt[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        engine.setNowPlayingInfo(withArt)
      }
    }
    artworkTask?.resume()
  }

  /// Logs (to the engine's log) whether the system took this app's Now Playing session, and
  /// asks again if not: tvOS shows the card only for the active session.
  @MainActor
  private func checkNowPlaying(_ engine: AetherEngine) {
    guard let session = engine.videoNowPlayingSession else {
      EngineLog.emit("[Liquiflux] now playing: no session on this route (\(engine.videoRoute))")
      return
    }
    EngineLog.emit("[Liquiflux] now playing: session active \(session.isActive), info keys \(session.nowPlayingInfoCenter.nowPlayingInfo?.keys.sorted().joined(separator: ",") ?? "none")")
    if !session.isActive {
      session.becomeActiveIfPossible { active in
        EngineLog.emit("[Liquiflux] now playing: asked to become active: \(active)")
      }
    }
  }

  /// Back to the TV's own mode (the one the user set in tvOS), as AetherEngine's default stop does.
  @MainActor
  private func resetDisplayMode() {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    for window in windows where window.avDisplayManager.preferredDisplayCriteria != nil {
      window.avDisplayManager.preferredDisplayCriteria = nil
    }
  }

  private static func track(_ t: TrackInfo) -> [String: Any] {
    var m: [String: Any] = ["id": t.id, "name": t.name, "codec": t.codec, "channels": t.channels, "default": t.isDefault]
    if let l = t.language { m["language"] = l }
    return m
  }
}

/// The engine's log lines appended to tmp/aetherengine.log, one at a time on a queue of their
/// own (the handler fires on the engine's threads and must not block).
private enum EngineLogFile {
  static let queue = DispatchQueue(label: "liquiflux.aether.log")
  static var handle: FileHandle?

  static func start() {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aetherengine.log")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    handle = try? FileHandle(forWritingTo: url)
    let started = Date()
    EngineLog.handler = { line in
      let stamp = String(format: "%.3f ", Date().timeIntervalSince(started))
      queue.async { handle?.write(Data((stamp + line + "\n").utf8)) }
    }
  }
}

/// Draws the picture-based subtitle cues showing now: each bitmap at the place its canvas
/// gives it, mapped onto the picture (aspect-fit in the view), as AetherEngine's own
/// compositor maps them (width-aligned, centred vertically).
final class SubtitleImageView: UIView {
  private var shown: [SubtitleImage] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  func show(_ images: [SubtitleImage]) {
    // Most frames repeat the same cues: only a change redraws.
    if images.count == shown.count, zip(images, shown).allSatisfy({ $0.cgImage === $1.cgImage && $0.position == $1.position }) { return }
    shown = images
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    for image in shown {
      let canvas = image.canvasSize == .zero ? CGSize(width: 16, height: 9) : image.canvasSize
      let picture = AVMakeRect(aspectRatio: canvas, insideRect: bounds)
      let scale = picture.width / canvas.width
      let rect: CGRect
      if image.canvasSize == .zero {
        rect = CGRect(x: picture.minX + image.position.minX * picture.width, y: picture.minY + image.position.minY * picture.height,
                      width: image.position.width * picture.width, height: image.position.height * picture.height)
      } else {
        rect = CGRect(x: picture.minX + image.position.minX * canvas.width * scale,
                      y: picture.midY + (image.position.minY * canvas.height - canvas.height / 2) * scale,
                      width: image.position.width * canvas.width * scale, height: image.position.height * canvas.height * scale)
      }
      let sub = CALayer()
      sub.contents = image.cgImage
      sub.contentsGravity = .resize
      sub.frame = rect
      layer.addSublayer(sub)
    }
  }
}
