import SwiftUI

/// Color handling for shortcut tiles. Shortcuts reports an RGB color; we store it as hex and
/// map it to a named family so smart lists can filter by color without exact matching.
nonisolated struct TileColor: Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else {
            self.init(red: 0.45, green: 0.45, blue: 0.5)
            return
        }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Blends toward white. Shortcuts' tiles sit about 12% lighter than the colors in its icon renders.
    func lightened(by amount: Double) -> TileColor {
        TileColor(red: red + (1 - red) * amount, green: green + (1 - green) * amount, blue: blue + (1 - blue) * amount)
    }

    /// Slightly darker tone for gradient bottoms.
    var shade: Color { Color(red: red * 0.86, green: green * 0.86, blue: blue * 0.86) }
    /// Slightly lighter tone for gradient tops.
    var tint: Color { Color(red: min(1, red + (1 - red) * 0.12), green: min(1, green + (1 - green) * 0.12), blue: min(1, blue + (1 - blue) * 0.12)) }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, shade], startPoint: .top, endPoint: .bottom)
    }

    static let families: [(name: String, color: Color)] = [
        ("Red", .red), ("Orange", .orange), ("Yellow", .yellow), ("Green", .green),
        ("Teal", .teal), ("Blue", .blue), ("Indigo", .indigo), ("Purple", .purple),
        ("Pink", .pink), ("Brown", .brown), ("Gray", .gray),
    ]

    /// Nearest named color family, by hue with a saturation guard for grays and browns.
    var family: String {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let delta = maxC - minC
        if delta < 0.12 { return "Gray" }
        var hue: Double
        if maxC == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxC == green { hue = (blue - red) / delta + 2 }
        else { hue = (red - green) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        let sat = maxC == 0 ? 0 : delta / maxC
        if hue >= 15 && hue < 45 && maxC < 0.6 && sat < 0.75 { return "Brown" }
        switch hue {
        case ..<15, 335...: return "Red"
        case 15..<40: return "Orange"
        case 40..<68: return "Yellow"
        case 68..<160: return "Green"
        case 160..<200: return "Teal"
        case 200..<245: return "Blue"
        case 245..<268: return "Indigo"
        case 268..<300: return "Purple"
        default: return "Pink"
        }
    }

    static func hex(for color: Color) -> String {
        #if os(macOS)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return TileColor(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent)).hex
        #else
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return TileColor(red: Double(r), green: Double(g), blue: Double(b)).hex
        #endif
    }
}

extension Color {
    init(hex: String, fallback: Color = .accentColor) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, UInt32(h, radix: 16) != nil else { self = fallback; return }
        self = TileColor(hex: hex).color
    }
}
