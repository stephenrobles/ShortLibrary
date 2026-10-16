import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shortcuts hands us a finished icon: a rounded square filled with the tile gradient and a white
/// glyph on top. To draw tiles the way Shortcuts does, we pull the glyph out as a white alpha mask
/// and sample the gradient's top and bottom colors.
nonisolated enum IconProcessing {
    struct Result: Sendable, Hashable {
        var glyphPNG: Data
        var topHex: String
        var bottomHex: String
    }

    static let outputSize = 128

    static func process(_ data: Data) -> Result? {
        guard let source = cgImage(from: data) else { return nil }
        let size = outputSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double, Double)? {
            let i = (y * size + x) * 4
            let a = Double(pixels[i + 3])
            guard a > 32 else { return nil }
            // Un-premultiply.
            return (Double(pixels[i]) / a, Double(pixels[i + 1]) / a, Double(pixels[i + 2]) / a, a / 255)
        }

        // The first scanline in a bitmap context's buffer is the top edge of the image.
        let top = averageColor(x: size / 2, rows: 3...6, rgb)
        let bottom = averageColor(x: size / 2, rows: (size - 7)...(size - 4), rgb)
        guard let top, let bottom else { return nil }

        // Classify every opaque pixel: tile background, white glyph, or something else (an app icon).
        let backgroundMin = min(min(top.0, top.1, top.2), min(bottom.0, bottom.1, bottom.2))
        let whiteThreshold = min(max(0.6, backgroundMin + 0.18), 0.9)
        var otherCount = 0, opaqueCount = 0
        var minX = size, maxX = -1, minY = size, maxY = -1
        var classes = [UInt8](repeating: 0, count: size * size) // 0 transparent, 1 background, 2 white, 3 other
        for y in 0..<size {
            let t = Double(y) / Double(size - 1)
            let bg = (top.0 + (bottom.0 - top.0) * t, top.1 + (bottom.1 - top.1) * t, top.2 + (bottom.2 - top.2) * t)
            for x in 0..<size {
                guard let (r, g, b, _) = rgb(x, y) else { continue }
                opaqueCount += 1
                let dr = r - bg.0, dg = g - bg.1, db = b - bg.2
                let distance = (dr * dr + dg * dg + db * db).squareRoot()
                let whiteness = min(r, g, b)
                let cls: UInt8
                if distance < 0.14 { cls = 1 }
                else if whiteness > whiteThreshold { cls = 2 }
                else { cls = 3; otherCount += 1 }
                classes[y * size + x] = cls
                if cls != 1 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pictorial = opaqueCount > 0 && Double(otherCount) / Double(opaqueCount) > 0.02

        var out = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let cls = classes[y * size + x]
                guard cls == 2 || cls == 3, let (r, g, b, a) = rgb(x, y) else { continue }
                let i = (y * size + x) * 4
                if pictorial {
                    // Keep the artwork as is; only the tile background becomes transparent.
                    let av = UInt8((a * 255).rounded())
                    out[i] = UInt8((r * a * 255).rounded()); out[i + 1] = UInt8((g * a * 255).rounded()); out[i + 2] = UInt8((b * a * 255).rounded()); out[i + 3] = av
                } else {
                    let whiteness = (min(r, g, b) - whiteThreshold) / (1 - whiteThreshold)
                    let alpha = max(0, min(1, whiteness)) * a
                    guard alpha > 0.01 else { continue }
                    let v = UInt8((alpha * 255).rounded())
                    out[i] = v; out[i + 1] = v; out[i + 2] = v; out[i + 3] = v
                }
            }
        }
        guard let glyphContext = CGContext(data: &out, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                           space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let glyph = glyphContext.makeImage(), let trimmed = trimmed(glyph), let png = pngData(trimmed) else { return nil }
        return Result(glyphPNG: png, topHex: hex(top), bottomHex: hex(bottom))
    }

    /// Crops a glyph mask to its visible bounds so the glyph can be sized directly on a tile.
    static func trimmedGlyphPNG(_ data: Data) -> Data? {
        guard let image = cgImage(from: data), let cropped = trimmed(image) else { return nil }
        return pngData(cropped)
    }

    private static func trimmed(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Keep the glyph square-ish and centered so differently shaped glyphs sit on a common baseline.
        let side = max(maxX - minX + 1, maxY - minY + 1)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let rect = CGRect(x: max(0, cx - side / 2), y: max(0, h - 1 - cy - side / 2), width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return image.cropping(to: rect)
    }

    private static func averageColor(x: Int, rows: ClosedRange<Int>,
                                     _ rgb: (Int, Int) -> (Double, Double, Double, Double)?) -> (Double, Double, Double)? {
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in rows { for dx in -4...4 { if let p = rgb(x + dx, y) { r += p.0; g += p.1; b += p.2; n += 1 } } }
        guard n > 0 else { return nil }
        return (r / n, g / n, b / n)
    }

    private static func hex(_ c: (Double, Double, Double)) -> String {
        TileColor(red: c.0, green: c.1, blue: c.2).hex
    }

    static func cgImage(from data: Data) -> CGImage? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return UIImage(data: data)?.cgImage
        #endif
    }

    static func pngData(_ image: CGImage) -> Data? {
        #if os(macOS)
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        #else
        return UIImage(cgImage: image).pngData()
        #endif
    }
}
