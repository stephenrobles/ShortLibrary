import Foundation
import SwiftData

/// A folder in ShortLibrary's own organization tree. Unlike Shortcuts' folders these nest.
@Model
final class LibraryFolder {
    /// Device-independent identity so smart lists and iOS clients can refer to a folder.
    var uuid: String = UUID().uuidString
    var name: String = ""
    var symbolName: String = "folder"
    var colorHex: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var parent: LibraryFolder? = nil
    @Relationship(deleteRule: .nullify, inverse: \LibraryFolder.parent)
    var children: [LibraryFolder]? = nil
    @Relationship(deleteRule: .nullify, inverse: \ShortcutItem.folder)
    var shortcuts: [ShortcutItem]? = nil

    init(name: String, parent: LibraryFolder? = nil) {
        self.name = name
        self.parent = parent
        self.children = []
        self.shortcuts = []
    }

    var childFolders: [LibraryFolder] {
        (children ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var directShortcuts: [ShortcutItem] { shortcuts ?? [] }

    /// Shortcuts in this folder and every folder beneath it.
    var allShortcuts: [ShortcutItem] {
        var result = directShortcuts
        for child in childFolders { result.append(contentsOf: child.allShortcuts) }
        return result
    }

    /// Root-first chain of ancestors, ending with this folder.
    var path: [LibraryFolder] {
        var chain: [LibraryFolder] = [self]
        var cursor = parent
        var guardCount = 0
        while let p = cursor, guardCount < 64 {
            chain.insert(p, at: 0)
            cursor = p.parent
            guardCount += 1
        }
        return chain
    }

    var depth: Int { path.count - 1 }

    func isDescendant(of other: LibraryFolder) -> Bool {
        var cursor = parent
        var guardCount = 0
        while let p = cursor, guardCount < 64 {
            if p === other { return true }
            cursor = p.parent
            guardCount += 1
        }
        return false
    }
}
