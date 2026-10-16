import SwiftUI

/// Draws a shortcut's glyph the way Shortcuts does.
/// - `.badge`: translucent white rounded square with the white glyph, for use on a colored tile.
/// - `.standalone`: the tile gradient as the square, for lists and the inspector.
struct ShortcutIconView: View {
    enum Style {
        /// Bare white glyph, the way Shortcuts draws it on a tile.
        case badge
        /// Tile gradient square behind the glyph, for lists and the inspector.
        case standalone
    }

    let item: ShortcutItem
    var size: CGFloat = 40
    var style: Style = .standalone

    var body: some View {
        Group {
            switch style {
            case .badge:
                ShortcutGlyph(item: item, size: size)
            case .standalone:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(item.tileGradient)
                    ShortcutGlyph(item: item, size: size * 0.64)
                }
                .frame(width: size, height: size)
            }
        }
        .onAppear { LibrarySyncController.shared.prioritizeIcon(for: item) }
    }
}

/// The white glyph alone: the extracted mask when we have it, Shortcuts' generic stacked squares otherwise.
struct ShortcutGlyph: View {
    let item: ShortcutItem
    var size: CGFloat

    var body: some View {
        Group {
            if let data = item.iconData, let image = PlatformImage.image(from: data) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: item.isMissing ? "questionmark" : "square.2.layers.3d.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
    }
}

enum PlatformImage {
    static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}

/// Shortcuts' named tile colors, used when a sync source reports a color by name.
enum ShortcutsPalette {
    static let hexByName: [String: String] = [
        "red": "#F36F74", "orange": "#FF8E73", "yellow": "#F8AE5F", "gold": "#E8CA45", "green": "#53CD6B",
        "teal": "#57CFB4", "cyan": "#5ACCDE", "blue": "#24BAF7", "navy": "#5874CA", "purple": "#9164C7",
        "lavender": "#C085E6", "pink": "#F694D8", "gray": "#9099A3", "grey": "#9099A3", "sage": "#9DA79D", "tan": "#A49995",
    ]

    static func hex(forName name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix("#"), key.count == 7 { return key.uppercased() }
        return hexByName[key]
    }
}
