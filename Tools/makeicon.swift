#!/usr/bin/env swift
import AppKit
import Foundation

// Renders AppIcon.icns from code — no design tool, no binary asset to keep in sync with
// the in-app brand mark. Run: make icon

// These fixed brand colors intentionally match `MurmurAppIcon`. The application icon is
// always the black identity, regardless of the user's light/dark appearance setting.
let tile = NSColor(hex: 0x101114)
let tileBorder = NSColor(hex: 0x2A2D35)
let mark = NSColor(hex: 0xFACC15)

/// Relative bar heights, center-weighted so the mark reads as a voice waveform rather
/// than a bar chart.
let bars: [CGFloat] = [0.30, 0.52, 0.78, 1.00, 0.82, 0.56, 0.34]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // macOS Big Sur+ icon grid: art occupies the middle ~82%, leaving the shadow gutter
    // the system expects.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    // Apple's squircle is ~22.37% of the tile's edge.
    let radius = rect.width * 0.2237

    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.035,
        color: NSColor.black.withAlphaComponent(0.34).cgColor
    )
    ctx.addPath(squircle)
    ctx.setFillColor(tile.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Flat black face with a fine edge. Murmur deliberately avoids gradients.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    ctx.setStrokeColor(tileBorder.cgColor)
    ctx.setLineWidth(max(1, size * 0.006))
    ctx.addPath(squircle)
    ctx.strokePath()
    ctx.restoreGState()

    // Waveform mark.
    let barWidth = rect.width * 0.072
    let gap = rect.width * 0.050
    let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
    let maxHeight = rect.height * 0.46
    var x = rect.midX - totalWidth / 2

    ctx.saveGState()
    ctx.setFillColor(mark.cgColor)
    for bar in bars {
        let height = max(barWidth, maxHeight * bar)
        let barRect = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
        ctx.addPath(CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth / 2,
            cornerHeight: barWidth / 2,
            transform: nil
        ))
        ctx.fillPath()
        x += barWidth + gap
    }
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Redraw at native pixel size rather than scaling a single render — keeps the small
    // sizes crisp instead of muddy.
    drawIcon(size: CGFloat(pixels)).draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .sourceOver, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) pairs iconutil expects.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    guard let data = png(NSImage(), pixels: pixels) else {
        print("failed at \(pixels)px"); exit(1)
    }
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

// `iconutil` in newer Command Line Tools releases no longer reliably repacks an iconset,
// even when it was produced by unpacking a valid ICNS. ICNS is a small chunk container, so
// assemble the modern PNG-backed entries directly and keep icon generation deterministic.
let icnsChunks: [(type: String, file: String)] = [
    ("ic04", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic05", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

func fourCC(_ value: String) -> [UInt8] {
    Array(value.utf8)
}

func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
}

var payload = Data()
for chunk in icnsChunks {
    let imageData = try Data(contentsOf: iconset.appendingPathComponent(chunk.file))
    payload.append(contentsOf: fourCC(chunk.type))
    payload.append(contentsOf: bigEndianBytes(UInt32(imageData.count + 8)))
    payload.append(imageData)
}

var icns = Data(fourCC("icns"))
icns.append(contentsOf: bigEndianBytes(UInt32(payload.count + 8)))
icns.append(payload)
try icns.write(to: root.appendingPathComponent("Resources/AppIcon.icns"), options: .atomic)

print("wrote \(variants.count) PNGs and Resources/AppIcon.icns")

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
