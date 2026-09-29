// Renders VinylQ's app icon at every size macOS asks for.
//
//   swift Packaging/DrawIcon.swift <output-iconset-dir>
//
// A record on espresso paper, with the tonearm reaching in from the corner.
import AppKit
import Foundation

let sizes: [Int: [String]] = [
    16:   ["icon_16x16"],
    32:   ["icon_16x16@2x", "icon_32x32"],
    64:   ["icon_32x32@2x"],
    128:  ["icon_128x128"],
    256:  ["icon_128x128@2x", "icon_256x256"],
    512:  ["icon_256x256@2x", "icon_512x512"],
    1024: ["icon_512x512@2x"]
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green:   CGFloat((hex >> 8) & 0xFF) / 255,
        blue:    CGFloat(hex & 0xFF) / 255,
        alpha:   alpha
    )
}

func drawIcon(side: Int) -> NSImage {
    let size = CGFloat(side)
    let s = size / 1024
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    // Sleeve.
    let inset = 62 * s
    let sleeve = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: 190 * s, yRadius: 190 * s
    )
    sleeve.setClip()
    NSGradient(starting: color(0x3D3025), ending: color(0x141009))?
        .draw(in: NSRect(origin: .zero, size: image.size), angle: -55)

    let center = NSPoint(x: size * 0.5, y: size * 0.5)
    let disc = size * 0.335

    // Record.
    color(0x0A0908).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - disc, y: center.y - disc,
                                width: disc * 2, height: disc * 2)).fill()

    // Grooves.
    let rings = max(4, Int(18 * min(1, size / 256)))
    for i in 0..<rings {
        let r = disc * (0.42 + 0.56 * CGFloat(i) / CGFloat(rings))
        color(0xFFFFFF, i % 3 == 0 ? 0.16 : 0.07).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r,
                                               width: r * 2, height: r * 2))
        ring.lineWidth = max(0.5, 3 * s)
        ring.stroke()
    }

    // Light sweeping across the disc.
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: NSRect(x: center.x - disc, y: center.y - disc,
                                width: disc * 2, height: disc * 2)).setClip()
    NSGradient(starting: color(0xFFFFFF, 0.22), ending: color(0xFFFFFF, 0))?
        .draw(in: NSRect(x: center.x - disc, y: center.y - disc,
                         width: disc * 2, height: disc * 2), angle: -40)
    NSGraphicsContext.restoreGraphicsState()

    // Label and spindle.
    let label = disc * 0.36
    color(0xE0A458).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - label, y: center.y - label,
                                width: label * 2, height: label * 2)).fill()
    let hole = max(1, disc * 0.035)
    color(0x141009).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - hole, y: center.y - hole,
                                width: hole * 2, height: hole * 2)).fill()

    // Tonearm — dropped once the icon is big enough to read it.
    if side >= 64 {
        let pivot = NSPoint(x: size * 0.815, y: size * 0.815)
        let angle = 228.0 * .pi / 180
        let length = size * 0.47
        let arm = NSBezierPath()
        arm.move(to: pivot)
        arm.line(to: NSPoint(x: pivot.x + length * cos(angle),
                             y: pivot.y + length * sin(angle)))
        arm.lineWidth = max(1.5, 16 * s)
        arm.lineCapStyle = .round
        color(0xE8E2D8, 0.95).setStroke()
        arm.stroke()

        let gimbal = max(2, 32 * s)
        color(0xD6CFC3).setFill()
        NSBezierPath(ovalIn: NSRect(x: pivot.x - gimbal, y: pivot.y - gimbal,
                                    width: gimbal * 2, height: gimbal * 2)).fill()
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String, side: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = NSSize(width: side, height: side)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for (side, names) in sizes {
    let image = drawIcon(side: side)
    for name in names {
        writePNG(image, to: "\(outputDirectory)/\(name).png", side: side)
    }
}
print("drew \(sizes.count) sizes")
