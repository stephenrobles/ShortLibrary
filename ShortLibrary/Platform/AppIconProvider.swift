#if os(macOS)
import AppKit
import Foundation

/// Produces the icon Shortcuts would show for an app-based shortcut: the installed Mac app's icon when
/// there is one, otherwise App Store artwork looked up by bundle id. Results are cached per bundle id.
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cache: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let size: CGFloat = 128

    /// iOS bundle ids that Shortcuts' database records, mapped to the Mac apps that own the same icon.
    static let macEquivalents: [String: String] = [
        "com.apple.mobilesafari": "com.apple.Safari", "com.apple.mobilenotes": "com.apple.Notes",
        "com.apple.mobilemail": "com.apple.mail", "com.apple.mobilecal": "com.apple.iCal",
        "com.apple.mobileslideshow": "com.apple.Photos", "com.apple.MobileSMS": "com.apple.MobileSMS",
        "com.apple.mobiletimer": "com.apple.clock", "com.apple.Preferences": "com.apple.systempreferences",
        "com.apple.DocumentsApp": "com.apple.finder", "com.apple.iBooks": "com.apple.iBooksX",
        "com.apple.MobileStore": "com.apple.AppStore", "com.apple.facetime": "com.apple.FaceTime",
        "com.apple.mobilephone": "com.apple.FaceTime", "com.apple.tv": "com.apple.TV",
        "com.apple.camera": "com.apple.PhotoBooth", "com.apple.Bridge": "com.apple.Bridge",
    ]

    /// Icons for Apple apps that exist on iPhone but have no Mac app or App Store page, drawn to resemble the real ones.
    static let drawnFallbacks: [String: (symbol: String, background: NSColor, tint: NSColor)] = [
        "com.apple.TVRemoteApp": ("appletvremote.gen4.fill", NSColor(white: 0.9, alpha: 1), NSColor(white: 0.22, alpha: 1)),
        "com.apple.TVRemoteUIService": ("appletvremote.gen4.fill", NSColor(white: 0.9, alpha: 1), NSColor(white: 0.22, alpha: 1)),
        "com.apple.Health": ("heart.fill", .white, NSColor(red: 1, green: 0.23, blue: 0.4, alpha: 1)),
        "com.apple.camera": ("camera.fill", NSColor(white: 0.35, alpha: 1), .white),
        "com.apple.Translate": ("character.bubble.fill", NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1), .white),
        "com.apple.Bridge": ("applewatch", .black, .white),
        "com.apple.mobilephone": ("phone.fill", NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1), .white),
        "com.apple.Fitness": ("figure.run", .black, NSColor(red: 0.98, green: 0.2, blue: 0.3, alpha: 1)),
        "com.apple.compass": ("safari.fill", .black, .white),
        "com.apple.measure": ("ruler.fill", .black, .white),
        "com.apple.Magnifier": ("plus.magnifyingglass", .black, .white),
        "com.apple.shortcuts": ("square.2.layers.3d.fill", NSColor(red: 0.3, green: 0.4, blue: 0.95, alpha: 1), .white),
    ]

    /// Fast, local resolution: an installed Mac app's icon or a drawn stand-in. Nil means "ask the App Store".
    func installedIcon(for bundleID: String) -> Data? {
        if let cached = cache[bundleID] { return cached }
        var result = installedAppIcon(for: bundleID)
        if result == nil, let fallback = Self.drawnFallbacks[bundleID] {
            result = Self.drawnIcon(symbol: fallback.symbol, background: fallback.background, tint: fallback.tint, size: size)
        }
        if let result { cache[bundleID] = result }
        return result
    }

    /// Slow path: App Store artwork, cached per bundle id.
    func remoteIcon(for bundleID: String) async -> Data? {
        if let cached = cache[bundleID] { return cached }
        if let task = inFlight[bundleID] { return await task.value }
        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.storeArtwork(for: bundleID)
        }
        inFlight[bundleID] = task
        let result = await task.value
        inFlight[bundleID] = nil
        if let result { cache[bundleID] = result }
        return result
    }

    func icon(for bundleID: String) async -> Data? {
        if let local = installedIcon(for: bundleID) { return local }
        return await remoteIcon(for: bundleID)
    }

    private func installedAppIcon(for bundleID: String) -> Data? {
        let candidates = [bundleID, Self.macEquivalents[bundleID]].compactMap { $0 }
        for id in candidates {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: size, height: size)
            if let png = Self.png(image, size: size, roundCorners: false) { return png }
        }
        return nil
    }

    private static func drawnIcon(symbol: String, background: NSColor, tint: NSColor, size: CGFloat) -> Data? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size * 0.46, weight: .medium)) else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        background.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237).fill()
        let symbolRect = NSRect(x: (size - tinted.size.width) / 2, y: (size - tinted.size.height) / 2, width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: symbolRect)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func storeArtwork(for bundleID: String) async -> Data? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID), URLQueryItem(name: "country", value: "us")]
        guard let url = components.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], let first = results.first,
              var artwork = first["artworkUrl100"] as? String else { return nil }
        artwork = artwork.replacingOccurrences(of: "100x100bb", with: "256x256bb")
        guard let artURL = URL(string: artwork), let (image, _) = try? await URLSession.shared.data(from: artURL),
              let ns = NSImage(data: image) else { return nil }
        return Self.png(ns, size: size, roundCorners: true)
    }

    /// Renders to a PNG; App Store artwork is square, so it gets the standard icon squircle.
    private static func png(_ image: NSImage, size: CGFloat, roundCorners: Bool) -> Data? {
        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        if roundCorners {
            NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237).addClip()
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
