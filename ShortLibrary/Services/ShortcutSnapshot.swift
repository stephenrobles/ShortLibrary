import Foundation

/// What a sync source knows about one shortcut. Produced by the Mac scripting bridge or by
/// the iOS helper shortcut, consumed by `LibraryImporter`.
nonisolated struct ShortcutSnapshot: Sendable, Hashable {
    /// Shortcuts' UUID when known, otherwise empty (iOS).
    var identifier: String
    var name: String
    var subtitle: String = ""
    var colorHex: String = ""
    var acceptsInput: Bool = false
    var actionCount: Int = 0
    var folderName: String = ""
    var createdAt: Date? = nil
    var modifiedAt: Date? = nil
    /// Raw icon image when the source supplied one in the same pass (processed by IconProcessing).
    var iconImageData: Data? = nil
    /// Already-processed icon, when the source did the work off the main thread.
    var processedIcon: IconProcessing.Result? = nil
    /// Position in the Shortcuts app's library order, when known.
    var libraryOrder: Int? = nil
}

nonisolated struct SyncSummary: Sendable {
    var added = 0
    var updated = 0
    var missing = 0
    var total = 0

    var message: String {
        var parts: [String] = ["\(total) shortcuts"]
        if added > 0 { parts.append("\(added) new") }
        if updated > 0 { parts.append("\(updated) changed") }
        if missing > 0 { parts.append("\(missing) missing") }
        return parts.joined(separator: " · ")
    }
}
