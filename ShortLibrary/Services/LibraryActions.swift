import Foundation
import SwiftData

/// Organization edits that several views trigger (drag and drop, context menus, the inspector).
@MainActor
enum LibraryActions {
    static func items(for identifiers: [String], context: ModelContext) -> [ShortcutItem] {
        let wanted = Set(identifiers)
        let all = (try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []
        return all.filter { wanted.contains($0.identifier) }
    }

    static func move(identifiers: [String], to folder: LibraryFolder?, context: ModelContext) {
        for item in items(for: identifiers, context: context) { item.folder = folder }
        try? context.save()
    }

    static func addTag(_ tag: Tag, toIdentifiers identifiers: [String], context: ModelContext) {
        for item in items(for: identifiers, context: context) { add(tag, to: item) }
        try? context.save()
    }

    static func add(_ tag: Tag, to item: ShortcutItem) {
        guard !(item.tags ?? []).contains(where: { $0 === tag }) else { return }
        if item.tags == nil { item.tags = [] }
        item.tags?.append(tag)
    }

    static func remove(_ tag: Tag, from item: ShortcutItem) {
        item.tags?.removeAll { $0 === tag }
    }

    static func toggle(_ tag: Tag, on item: ShortcutItem) {
        if (item.tags ?? []).contains(where: { $0 === tag }) { remove(tag, from: item) } else { add(tag, to: item) }
        try? item.modelContext?.save()
    }

    /// Deleting a folder lifts its contents into the parent rather than orphaning anything.
    static func delete(folder: LibraryFolder, context: ModelContext) {
        let parent = folder.parent
        for child in folder.childFolders { child.parent = parent }
        for item in folder.directShortcuts { item.folder = parent }
        context.delete(folder)
        try? context.save()
    }

    /// Deleting a tag lifts nested tags into its parent; shortcuts simply lose the tag.
    static func delete(tag: Tag, context: ModelContext) {
        let parent = tag.parent
        for child in tag.childTags { child.parent = parent }
        context.delete(tag)
        try? context.save()
    }

    static func move(folder: LibraryFolder, into parent: LibraryFolder?) {
        guard parent !== folder, !(parent?.isDescendant(of: folder) ?? false) else { return }
        folder.parent = parent
        try? folder.modelContext?.save()
    }

    static func move(tag: Tag, into parent: Tag?) {
        guard parent !== tag, !(parent?.isDescendant(of: tag) ?? false) else { return }
        tag.parent = parent
        try? tag.modelContext?.save()
    }

    /// Flattened tag tree with depth, for pickers and menus.
    static func flattenedTags(_ tags: [Tag]) -> [(tag: Tag, depth: Int)] {
        var result: [(Tag, Int)] = []
        func walk(_ tag: Tag, depth: Int) {
            result.append((tag, depth))
            for child in tag.childTags { walk(child, depth: depth + 1) }
        }
        let roots = tags.filter { $0.parent == nil }
            .sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
        for root in roots { walk(root, depth: 0) }
        return result
    }

    /// Flattened folder tree with depth, for pickers and menus.
    static func flattenedFolders(_ folders: [LibraryFolder]) -> [(folder: LibraryFolder, depth: Int)] {
        var result: [(LibraryFolder, Int)] = []
        func walk(_ folder: LibraryFolder, depth: Int) {
            result.append((folder, depth))
            for child in folder.childFolders { walk(child, depth: depth + 1) }
        }
        let roots = folders.filter { $0.parent == nil }
            .sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
        for root in roots { walk(root, depth: 0) }
        return result
    }
}
