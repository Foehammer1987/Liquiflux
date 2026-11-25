// Apple app icons from the Liquiflux mark (docs/brand/liquiflux-mark.svg), drawn like the
// Windows and Android icons: the mark on a dark face. Two layers, so every Apple target can
// be made from the same source:
//
//   back   the dark face alone (gradient), full-bleed
//   front  the mark alone, on transparent
//
// Mac (the flattened icon on Apple's macOS grid, every size):
//   swift tools/make-apple-icons.swift mac docs/brand/liquiflux-mark.svg app/macos/Runner/Assets.xcassets/AppIcon.appiconset
// iPhone and iPad (one 1024 square, full-bleed and opaque as the App Store wants; iOS rounds
// it and makes every smaller size itself):
//   swift tools/make-apple-icons.swift ios docs/brand/liquiflux-mark.svg app/ios/Runner/Assets.xcassets/AppIcon.appiconset
// The iOS launch screen's mark (transparent, on the storyboard's dark background), 1x to 3x:
//   swift tools/make-apple-icons.swift launch docs/brand/liquiflux-mark.svg app/ios/Runner/Assets.xcassets/LaunchImage.imageset
// The two layers at any size (e.g. an Apple TV layered icon's back and front, or iPhone's
// full-bleed 1024 square, which iOS rounds itself):
//   swift tools/make-apple-icons.swift layers docs/brand/liquiflux-mark.svg <out folder> <width> <height>
// Apple TV (the whole AppIcon.brandassets: the layered icon, back, middle and front, at 400x240
// for the Home screen and 1280x768 for the App Store, each 1x and 2x, and both Top Shelf images; tvOS adds
// the parallax and the rounded corners itself):
//   swift tools/make-apple-icons.swift tvos docs/brand/liquiflux-mark.svg app/tvos/Runner/Assets.xcassets/AppIcon.brandassets

import AppKit

let args = CommandLine.arguments
let mode = args[1]
let svg = NSImage(contentsOf: URL(fileURLWithPath: args[2]))!
let out = args[3]
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }

func canvas(_ w: Int, _ h: Int, opaque: Bool = false, _ draw: (CGFloat) -> Void) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current!.imageInterpolation = .high
  draw(CGFloat(min(w, h)))
  NSGraphicsContext.restoreGraphicsState()
  if opaque { return rgb(rep).representation(using: .png, properties: [:])! }
  return rep.representation(using: .png, properties: [:])!
}

/// [rep]'s colours without its alpha channel (Core Graphics only draws into 32-bit pixels,
/// and the App Store refuses an iOS icon that has alpha at all).
func rgb(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
  let w = rep.pixelsWide, h = rep.pixelsHigh
  let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 3, bitsPerPixel: 24)!
  let src = rep.bitmapData!, dst = out.bitmapData!, sr = rep.bytesPerRow
  for y in 0..<h {
    for x in 0..<w {
      for k in 0..<3 { dst[y * w * 3 + x * 3 + k] = src[y * sr + x * 4 + k] }
    }
  }
  return out
}

/// The back layer: the face's gradient, lighter at the top.
func back(in rect: NSRect, path: NSBezierPath? = nil) {
  NSGradient(starting: c(24,25,31), ending: c(13,13,14))!.draw(in: path ?? NSBezierPath(rect: rect), angle: -90)
}

/// The front layer: the mark at 77% of [box]'s width (as on Windows), centred.
func front(in box: NSRect) {
  let mw = box.width * 0.773, mh = mw * 360/480
  svg.draw(in: NSRect(x: box.midX - mw/2, y: box.midY - mh/2, width: mw, height: mh), from: .zero, operation: .sourceOver, fraction: 1)
}

func mac(_ px: Int) -> Data {
  canvas(px, px) { size in
    let s = size / 1024
    // macOS grid: 824 body centred in 1024, corner radius ~185, soft drop shadow, fine rim.
    let body = NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185*s, yRadius: 185*s)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.35); sh.shadowOffset = NSSize(width: 0, height: -10*s); sh.shadowBlurRadius = 20*s; sh.set()
    c(13,13,14).setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    back(in: body, path: path)
    c(42,43,49).setStroke(); let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2*s, dy: 2*s), xRadius: 183*s, yRadius: 183*s); rim.lineWidth = max(1, 4*s); rim.stroke()
    front(in: body)
  }
}

/// The single iOS icon: the face edge to edge (no alpha), the mark on it.
func ios() -> Data {
  canvas(1024, 1024, opaque: true) { size in
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    back(in: rect)
    front(in: rect)
  }
}

func write(_ text: String, _ path: String) { try! text.write(toFile: path, atomically: true, encoding: .utf8) }

/// The Apple TV brand assets in [dir]: a three-layer image stack per icon size (Back opaque,
/// Middle a soft blue glow, Front the mark on transparent) and the two Top Shelf images
/// (opaque, the mark a little above centre, smaller, so the shelf reads as a banner rather
/// than a giant icon). File names follow flutter-tvos's template, which its build checks.
func tvos(_ dir: String) {
  let fm = FileManager.default
  try? fm.removeItem(atPath: dir)
  func folder(_ path: String) -> String { try! fm.createDirectory(atPath: "\(dir)/\(path)", withIntermediateDirectories: true); return "\(dir)/\(path)" }
  func json(_ obj: Any, _ path: String) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: path))
  }
  let info: [String: Any] = ["author": "xcode", "version": 1]
  // name, file prefix, points, scales
  let stacks: [(String, String, Int, Int, [Int])] = [("App Icon - Small", "small", 400, 240, [1, 2]), ("App Icon - Large", "large", 1280, 768, [1, 2])]
  for (name, prefix, w, h, scales) in stacks {
    let stack = folder("\(name).imagestack")
    json(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Middle.imagestacklayer"], ["filename": "Back.imagestacklayer"]]], "\(stack)/Contents.json")
    for layer in ["Front", "Middle", "Back"] {
      let set = folder("\(name).imagestack/\(layer).imagestacklayer/Content.imageset")
      json(["info": info], "\(stack)/\(layer).imagestacklayer/Contents.json")
      var images: [[String: Any]] = []
      for scale in scales {
        let pw = w * scale, ph = h * scale
        let file = "\(prefix)_\(layer.lowercased())\(scale == 1 ? "" : "@\(scale)x").png"
        let rect = NSRect(x: 0, y: 0, width: pw, height: ph)
        let side = CGFloat(min(pw, ph))
        let png: Data
        switch layer {
        case "Back":
          png = canvas(pw, ph, opaque: true) { _ in back(in: rect) }
        case "Middle":
          // A soft glow of the mark's blue behind it, so the parallax has a layer between.
          png = canvas(pw, ph) { _ in
            let centre = NSPoint(x: CGFloat(pw)/2, y: CGFloat(ph)/2)
            NSGradient(colors: [c(30, 120, 255).withAlphaComponent(0.22), c(30, 120, 255).withAlphaComponent(0)])!
              .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: side * 0.6, options: [])
          }
        default:
          png = canvas(pw, ph) { _ in front(in: NSRect(x: (CGFloat(pw) - side)/2, y: (CGFloat(ph) - side)/2, width: side, height: side)) }
        }
        try! png.write(to: URL(fileURLWithPath: "\(set)/\(file)"))
        images.append(["idiom": "tv", "filename": file, "scale": "\(scale)x"])
      }
      json(["info": info, "images": images], "\(set)/Contents.json")
    }
  }
  let shelves: [(String, String, Int, Int)] = [("Top Shelf Image", "top-shelf-image", 1920, 720), ("Top Shelf Image Wide", "top-shelf-image-wide", 2320, 720)]
  for (name, _, w, h) in shelves {
    let set = folder("\(name).imageset")
    var images: [[String: Any]] = []
    for scale in [1, 2] {
      let pw = w * scale, ph = h * scale
      let file = "\(name == "Top Shelf Image" ? "top_shelf" : "top_shelf_wide")\(scale == 1 ? "" : "@2x").png"
      let rect = NSRect(x: 0, y: 0, width: pw, height: ph)
      let side = CGFloat(ph) * 0.62
      let png = canvas(pw, ph, opaque: true) { _ in
        back(in: rect)
        front(in: NSRect(x: (CGFloat(pw) - side)/2, y: (CGFloat(ph) - side)/2 + CGFloat(ph) * 0.04, width: side, height: side))
      }
      try! png.write(to: URL(fileURLWithPath: "\(set)/\(file)"))
      images.append(["idiom": "tv", "filename": file, "scale": "\(scale)x"])
    }
    json(["info": info, "images": images], "\(set)/Contents.json")
  }
  json(["info": info, "assets": [
    ["filename": "App Icon - Large.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon - Small.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
  ]], "\(dir)/Contents.json")
}

switch mode {
case "mac":
  for px in [16, 32, 64, 128, 256, 512, 1024] {
    try! mac(px).write(to: URL(fileURLWithPath: "\(out)/app_icon_\(px).png"))
  }
case "layers":
  let w = Int(args[4])!, h = Int(args[5])!
  let rect = NSRect(x: 0, y: 0, width: w, height: h)
  try! canvas(w, h) { _ in back(in: rect) }.write(to: URL(fileURLWithPath: "\(out)/back_\(w)x\(h).png"))
  // The mark sized to the shorter side, so a wide Apple TV icon keeps it the same shape.
  let side = CGFloat(min(w, h))
  try! canvas(w, h) { _ in front(in: NSRect(x: (CGFloat(w) - side)/2, y: (CGFloat(h) - side)/2, width: side, height: side)) }.write(to: URL(fileURLWithPath: "\(out)/front_\(w)x\(h).png"))
case "ios":
  try! ios().write(to: URL(fileURLWithPath: "\(out)/AppIcon-1024.png"))
  write("""
  {
    "images" : [
      {
        "filename" : "AppIcon-1024.png",
        "idiom" : "universal",
        "platform" : "ios",
        "size" : "1024x1024"
      }
    ],
    "info" : {
      "author" : "xcode",
      "version" : 1
    }
  }

  """, "\(out)/Contents.json")
case "tvos":
  tvos(out)
case "launch":
  // 120 points wide, the mark's own shape (480 x 360).
  for (scale, name) in [(1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")] {
    let w = 120 * scale, h = 90 * scale
    try! canvas(w, h) { _ in
      svg.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
    }.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
  }
default:
  print("mode is mac, ios, tvos, launch or layers"); exit(1)
}
