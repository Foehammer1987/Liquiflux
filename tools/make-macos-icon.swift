// Makes the Mac app icon (app/macos/Runner/Assets.xcassets/AppIcon.appiconset) from the
// Liquiflux mark, drawn like the Windows and Android icons on Apple's macOS icon grid.
//   swift tools/make-macos-icon.swift docs/brand/liquiflux-mark.svg app/macos/Runner/Assets.xcassets/AppIcon.appiconset

import AppKit

let svg = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let out = CommandLine.arguments[2]
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
func render(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGraphicsContext.current!.imageInterpolation = .high
  let s = CGFloat(px) / 1024
  // macOS grid: 824pt body centred in 1024, corner radius ~185, soft drop shadow.
  let body = NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s)
  let path = NSBezierPath(roundedRect: body, xRadius: 185*s, yRadius: 185*s)
  NSGraphicsContext.saveGraphicsState()
  let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.35); sh.shadowOffset = NSSize(width: 0, height: -10*s); sh.shadowBlurRadius = 20*s; sh.set()
  c(13,13,14).setFill(); path.fill()
  NSGraphicsContext.restoreGraphicsState()
  // Same dark face as the Windows/Android icon: lighter at the top, a fine light rim.
  NSGradient(starting: c(24,25,31), ending: c(13,13,14))!.draw(in: path, angle: -90)
  c(42,43,49).setStroke(); let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2*s, dy: 2*s), xRadius: 183*s, yRadius: 183*s); rim.lineWidth = max(1, 4*s); rim.stroke()
  // The mark at 77% of the face's width, centred, as on Windows.
  let mw = 824*s*0.773, mh = mw * 360/480
  svg.draw(in: NSRect(x: body.midX - mw/2, y: body.midY - mh/2, width: mw, height: mh), from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}
for px in [16, 32, 64, 128, 256, 512, 1024] {
  try! render(px).write(to: URL(fileURLWithPath: "\(out)/app_icon_\(px).png"))
}
