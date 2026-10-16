import SwiftData
import SwiftUI

/// Context menu shared by tiles, rows, and the inspector.
struct ShortcutContextMenu: View {
    let item: ShortcutItem
    var onRunWithInput: (ShortcutItem) -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    private var runner = ShortcutRunner.shared

    init(item: ShortcutItem, onRunWithInput: @escaping (ShortcutItem) -> Void) {
        self.item = item
        self.onRunWithInput = onRunWithInput
    }

    var body: some View {
        Button("Run", systemImage: "play.fill") { runner.run(item) }
        Button("Run with Input…", systemImage: "text.cursor") { onRunWithInput(item) }
        Divider()
        Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: item.isFavorite ? "star.slash" : "star") {
            item.isFavorite.toggle()
            try? context.save()
        }
        Menu("Move to Folder", systemImage: "folder") {
            Button("None") { item.folder = nil; try? context.save() }
            Divider()
            ForEach(LibraryActions.flattenedFolders(folders), id: \.folder.uuid) { entry in
                Button {
                    item.folder = entry.folder
                    try? context.save()
                } label: {
                    Label(String(repeating: "    ", count: entry.depth) + entry.folder.name,
                          systemImage: item.folder === entry.folder ? "checkmark" : entry.folder.symbolName)
                }
            }
        }
        Menu("Tags", systemImage: "tag") {
            if tags.isEmpty { Text("No tags yet") }
            ForEach(LibraryActions.flattenedTags(tags), id: \.tag.uuid) { entry in
                Toggle(String(repeating: "    ", count: entry.depth) + entry.tag.name, isOn: Binding(
                    get: { item.tagList.contains { $0 === entry.tag } },
                    set: { _ in LibraryActions.toggle(entry.tag, on: item) }
                ))
            }
        }
        Divider()
        Button("Open in Shortcuts", systemImage: "arrow.up.forward.app") { ShortcutURLs.openInShortcuts(item) }
        Button("Copy Name", systemImage: "doc.on.doc") { Clipboard.copy(item.name) }
        if item.isMissing {
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive) {
                if LibraryNavigation.shared.selectedShortcut === item { LibraryNavigation.shared.selectedShortcut = nil }
                context.delete(item)
                try? context.save()
            }
        }
    }
}

enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
