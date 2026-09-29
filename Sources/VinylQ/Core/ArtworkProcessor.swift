import AppKit
import CoreImage

/// Cover art, prepared once per track.
struct ArtworkSet {
    /// At most 640 px — plenty for the largest label, and cheap to rotate.
    let image: NSImage
    /// A tiny, heavily blurred copy. Stretched across the ambient deck it
    /// looks like a 100-point blur, without blurring a full-screen image
    /// every frame.
    let backdrop: NSImage
    /// The cover's average colour, nudged to read on a dark deck.
    let tint: NSColor
    let id: String
}

/// Turns whatever a source hands us — sometimes a 3000 px PNG straight out
/// of Music.app — into what the deck actually needs. Runs off the main thread.
enum ArtworkProcessor {

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func process(_ source: NSImage, id: String) -> ArtworkSet? {
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let scaled = downsample(cg, maxSide: 640) else { return nil }
        let image = NSImage(cgImage: scaled, size: NSSize(width: scaled.width, height: scaled.height))
        let backdrop = blurredThumbnail(scaled).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        return ArtworkSet(
            image: image,
            backdrop: backdrop ?? image,
            tint: averageColor(scaled) ?? NSColor(red: 0.88, green: 0.64, blue: 0.35, alpha: 1),
            id: id
        )
    }

    /// Redraws `image` so its longer side is at most `maxSide` pixels.
    static func downsample(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = min(1, maxSide / max(width, height))
        let target = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: target))
        return context.makeImage()
    }

    private static func blurredThumbnail(_ image: CGImage) -> CGImage? {
        guard let small = downsample(image, maxSide: 160) else { return nil }
        let input = CIImage(cgImage: small)
        guard let blur = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputRadiusKey: 9
        ])?.outputImage else { return nil }
        return context.createCGImage(blur.cropped(to: input.extent), from: input.extent)
    }

    private static func averageColor(_ image: CGImage) -> NSColor? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent)
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        let color = NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        guard let hsb = color.usingColorSpace(.deviceRGB) else { return color }
        // Floor the saturation and brightness so muddy covers still read as a tint.
        return NSColor(
            hue: hsb.hueComponent,
            saturation: max(hsb.saturationComponent, 0.35),
            brightness: max(hsb.brightnessComponent, 0.62),
            alpha: 1
        )
    }
}
