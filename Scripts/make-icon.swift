// Renders the app icon into Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let outDir = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")

func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: an 824 pt rounded square centred on the 1024 pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        starting: NSColor(calibratedWhite: 0.20, alpha: 1),
        ending: NSColor(calibratedWhite: 0.04, alpha: 1)
    )!.draw(in: shape, angle: -90)

    NSColor.white.withAlphaComponent(0.10).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    rim.lineWidth = 3
    rim.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let size = symbol.size
    symbol.draw(in: NSRect(
        x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 10,
        width: size.width, height: size.height
    ))

    // Nothing-style red dot.
    NSColor(srgbRed: 0.84, green: 0.10, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 712, y: 712, width: 64, height: 64)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func resized(_ rep: NSBitmapImageRep, to pixels: Int) -> Data {
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let master = renderMaster()
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try resized(master, to: points * scale).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: outDir.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
