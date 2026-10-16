import Foundation
import SwiftData

/// A tag in ShortLibrary. Tags nest like folders; a shortcut tagged "Podcasts/Editing" also shows under "Podcasts".
@Model
final class Tag {
    var uuid: String = UUID().uuidString
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var parent: Tag? = nil
    @Relationship(deleteRule: .nullify, inverse: \Tag.parent)
    var children: [Tag]? = nil
    @Relationship(inverse: \ShortcutItem.tags)
    var shortcuts: [ShortcutItem]? = nil

    init(name: String, colorHex: String = "#8E8E93", parent: Tag? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.parent = parent
        self.children = []
        self.shortcuts = []
    }

    var taggedShortcuts: [ShortcutItem] { shortcuts ?? [] }

    var childTags: [Tag] {
        (children ?? []).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Shortcuts carrying this tag or any tag nested beneath it, without duplicates.
    var allTaggedShortcuts: [ShortcutItem] {
        var seen = Set<ObjectIdentifier>()
        var result: [ShortcutItem] = []
        func walk(_ tag: Tag) {
            for item in tag.taggedShortcuts where seen.insert(ObjectIdentifier(item)).inserted { result.append(item) }
            for child in tag.childTags { walk(child) }
        }
        walk(self)
        return result
    }

    /// Root-first chain of ancestors, ending with this tag.
    var path: [Tag] {
        var chain: [Tag] = [self]
        var cursor = parent
        var guardCount = 0
        while let p = cursor, guardCount < 64 {
            chain.insert(p, at: 0)
            cursor = p.parent
            guardCount += 1
        }
        return chain
    }

    func isDescendant(of other: Tag) -> Bool {
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
