import Foundation
import SwiftData
import SwiftUI

/// One shortcut in the user's Shortcuts library, plus everything ShortLibrary layers on top of it.
///
/// Every stored property has a default and every relationship is optional so the model
/// is compatible with SwiftData's CloudKit mirroring.
@Model
final class ShortcutItem {
    /// Stable identity. On macOS this is the UUID that Shortcuts Events reports.
    /// Records that originate on iOS (where no identifier is exposed) use `name:<name>`
    /// until a Mac sync upgrades them to the real UUID.
    var identifier: String = ""
    var name: String = ""
    var subtitle: String = ""
    /// The single-level folder Shortcuts itself keeps the shortcut in, if any.
    var nativeFolderName: String = ""
    /// Hex RGB string of the shortcut's tile color as reported by Shortcuts.
    var colorHex: String = ""
    /// White glyph alpha mask extracted from Shortcuts' icon (see IconProcessing).
    @Attribute(.externalStorage) var iconData: Data? = nil
    /// Exact tile gradient sampled from the icon; empty until an icon has been processed.
    var iconTopHex: String = ""
    var iconBottomHex: String = ""
    /// Position in the Shortcuts app's own library order at the last sync.
    var libraryOrder: Int = 0
    /// App whose icon Shortcuts shows for this shortcut (from Shortcuts' database), empty for glyph icons.
    var appBundleID: String = ""
    /// Bundle id whose app icon is currently stored in `iconData`, so it isn't replaced by the generic glyph.
    var iconAppBundleID: String = ""
    var acceptsInput: Bool = false
    var actionCount: Int = 0

    /// Dates reported by Shortcuts when the source platform exposes them (iOS helper shortcut).
    var nativeCreatedAt: Date? = nil
    var nativeModifiedAt: Date? = nil
    /// First time any device saw this shortcut.
    var firstSeenAt: Date = Date()
    /// Last time a sync detected a change in the synced properties.
    var lastChangedAt: Date = Date()
    /// Last time a sync confirmed the shortcut still exists.
    var lastSeenAt: Date = Date()
    /// A full sync no longer found this shortcut.
    var isMissing: Bool = false

    var isFavorite: Bool = false
    var lastRunAt: Date? = nil
    var runCount: Int = 0
    var notes: String = ""

    var folder: LibraryFolder? = nil
    var tags: [Tag]? = nil

    init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
        self.tags = []
    }

    var tagList: [Tag] { (tags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    var hasNameOnlyIdentifier: Bool { identifier.hasPrefix("name:") }

    static func nameIdentifier(for name: String) -> String { "name:\(name)" }

    /// Best available "created" date for sorting and smart lists.
    var createdDate: Date { nativeCreatedAt ?? firstSeenAt }
    /// Best available "modified" date for sorting and smart lists.
    var modifiedDate: Date { nativeModifiedAt ?? lastChangedAt }

    var tileColor: TileColor { TileColor(hex: colorHex) }
    /// How much lighter Shortcuts draws its tiles than the colors in its icon renders.
    static let tileLift = 0.12

    func applyProcessedIcon(_ processed: IconProcessing.Result) {
        // Glyph sources never replace a rendered app icon.
        if iconAppBundleID.isEmpty || iconData == nil {
            if iconData != processed.glyphPNG { iconData = processed.glyphPNG }
            iconAppBundleID = ""
        }
        iconTopHex = processed.topHex
        iconBottomHex = processed.bottomHex
    }

    var showsAppIcon: Bool { !iconAppBundleID.isEmpty && iconData != nil }

    /// Vertical gradient matching Shortcuts' tile: sampled from the icon when available.
    var tileGradient: LinearGradient {
        if !iconTopHex.isEmpty && !iconBottomHex.isEmpty {
            let top = TileColor(hex: iconTopHex).lightened(by: Self.tileLift).color
            let bottom = TileColor(hex: iconBottomHex).lightened(by: Self.tileLift).color
            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
        return tileColor.gradient
    }
}
