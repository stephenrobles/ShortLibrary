import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var selection: LibrarySection?
    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \SmartList.sortOrder) private var smartLists: [SmartList]
    @Query private var shortcuts: [ShortcutItem]

    @State private var folderEdit: FolderEditTarget?
    @State private var tagEdit: TagEditTarget?
    @State private var smartListEdit: SmartListEditTarget?
    @State private var showNativeFolders = false
    private var syncer = LibrarySyncController.shared

    private var live: [ShortcutItem] { shortcuts.filter { !$0.isMissing } }
    private var rootFolders: [LibraryFolder] {
        folders.filter { $0.parent == nil }.sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
    }
    private var rootTags: [Tag] {
        tags.filter { $0.parent == nil }.sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
    }
    private var nativeFolderNames: [String] {
        Array(Set(live.map(\.nativeFolderName).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                row(.all, "All Shortcuts", "square.grid.2x2", count: live.count)
                row(.favorites, "Favorites", "star.fill", count: live.filter(\.isFavorite).count)
                row(.recent, "Recently Run", "clock.arrow.circlepath", count: live.filter { $0.lastRunAt != nil }.count)
                row(.unfiled, "Not in a Folder", "tray", count: live.filter { $0.folder == nil }.count)
                row(.untagged, "Untagged", "tag.slash", count: live.filter { $0.tagList.isEmpty }.count)
                let missing = shortcuts.filter(\.isMissing).count
                if missing > 0 {
                    row(.missing, "Missing from Shortcuts", "questionmark.folder", count: missing)
                }
            }

            if !smartLists.isEmpty {
                Section("Smart Lists") {
                    ForEach(smartLists) { list in
                        Label {
                            HStack {
                                Text(list.name)
                                Spacer()
                                Text("\(shortcuts.filter { list.rules.matches($0) }.count)").foregroundStyle(.tertiary).monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: list.symbolName).foregroundStyle(Color(hex: list.colorHex))
                        }
                        .tag(LibrarySection.smartList(list.uuid))
                        .sidebarRowPadding()
                        .contextMenu {
                            Button("Edit Smart List…", systemImage: "pencil") { smartListEdit = .edit(list) }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(list) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(list) }
                        }
                    }
                }
            }

            Section("Folders") {
                ForEach(rootFolders) { folder in
                    FolderOutlineRow(folder: folder, allFolders: folders, folderEdit: $folderEdit, selection: $selection)
                }
                if rootFolders.isEmpty {
                    Text("Use + above to create a folder, then drag shortcuts onto it.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Section("Tags") {
                ForEach(rootTags) { tag in
                    TagOutlineRow(tag: tag, allTags: tags, tagEdit: $tagEdit, selection: $selection)
                }
                if rootTags.isEmpty {
                    Text("Use + above to create a tag.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            if !nativeFolderNames.isEmpty {
                Section(isExpanded: $showNativeFolders) {
                    ForEach(nativeFolderNames, id: \.self) { name in
                        Label {
                            HStack {
                                Text(name)
                                Spacer()
                                Text("\(live.filter { $0.nativeFolderName == name }.count)").foregroundStyle(.tertiary).monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .tag(LibrarySection.nativeFolder(name))
                        .sidebarRowPadding()
                    }
                } header: {
                    Text("Shortcuts App Folders")
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 34)
        .navigationTitle("ShortLibrary")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("New Smart List", systemImage: "sparkles") { smartListEdit = .new }
                    Button("New Folder", systemImage: "folder.badge.plus") { folderEdit = .new(parent: nil) }
                    Button("New Tag", systemImage: "tag") { tagEdit = .new(parent: nil) }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("New Smart List, Folder, or Tag")
            }
        }
        .sheet(item: $folderEdit) { target in FolderEditor(target: target) }
        .sheet(item: $tagEdit) { target in TagEditor(target: target) }
        .sheet(item: $smartListEdit) { target in SmartListEditor(target: target) }
    }

    private func row(_ section: LibrarySection, _ title: String, _ symbol: String, count: Int) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)").foregroundStyle(.tertiary).monospacedDigit()
            }
        } icon: {
            Image(systemName: symbol)
        }
        .tag(section)
        .sidebarRowPadding()
    }

    private func duplicate(_ list: SmartList) {
        let copy = SmartList(name: list.name + " Copy", rules: list.rules)
        copy.symbolName = list.symbolName
        copy.colorHex = list.colorHex
        copy.sortOrder = list.sortOrder + 1
        context.insert(copy)
        try? context.save()
    }

    private func delete(_ list: SmartList) {
        if selection == .smartList(list.uuid) { selection = .all }
        context.delete(list)
        try? context.save()
    }
}

// MARK: - Folder rows

struct FolderOutlineRow: View {
    let folder: LibraryFolder
    let allFolders: [LibraryFolder]
    @Binding var folderEdit: FolderEditTarget?
    @Binding var selection: LibrarySection?
    @Environment(\.modelContext) private var context
    @State private var expanded = true

    var body: some View {
        if folder.childFolders.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(folder.childFolders) { child in
                    FolderOutlineRow(folder: child, allFolders: allFolders, folderEdit: $folderEdit, selection: $selection)
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        Label {
            HStack {
                Text(folder.name)
                Spacer()
                Text("\(folder.allShortcuts.filter { !$0.isMissing }.count)").foregroundStyle(.tertiary).monospacedDigit()
            }
        } icon: {
            Image(systemName: folder.symbolName).foregroundStyle(folder.colorHex.isEmpty ? Color.accentColor : Color(hex: folder.colorHex))
        }
        .tag(LibrarySection.folder(folder.uuid))
        .sidebarRowPadding()
        .dropDestination(for: String.self) { ids, _ in
            LibraryActions.move(identifiers: ids, to: folder, context: context); return true
        }
        .contextMenu {
            Button("New Folder Inside…", systemImage: "folder.badge.plus") { folderEdit = .new(parent: folder) }
            Button("Edit Folder…", systemImage: "pencil") { folderEdit = .edit(folder) }
            Divider()
            Menu("Move To", systemImage: "arrow.right.doc.on.clipboard") {
                Button { LibraryActions.move(folder: folder, into: nil) } label: {
                    Label("Top Level", systemImage: folder.parent == nil ? "checkmark" : "rectangle.split.3x1")
                }
                Divider()
                ForEach(LibraryActions.flattenedFolders(allFolders).filter { $0.folder !== folder && !$0.folder.isDescendant(of: folder) }, id: \.folder.uuid) { entry in
                    Button { LibraryActions.move(folder: folder, into: entry.folder) } label: {
                        Label(String(repeating: "    ", count: entry.depth) + entry.folder.name,
                              systemImage: folder.parent === entry.folder ? "checkmark" : entry.folder.symbolName)
                    }
                }
            }
            if let parent = folder.parent {
                Button("Move Out of \(parent.name)", systemImage: "arrow.up.left") {
                    LibraryActions.move(folder: folder, into: parent.parent)
                }
            }
            Divider()
            Button("Delete Folder", systemImage: "trash", role: .destructive) {
                if selection == .folder(folder.uuid) { selection = .all }
                LibraryActions.delete(folder: folder, context: context)
            }
        }
    }
}

// MARK: - Tag rows

struct TagOutlineRow: View {
    let tag: Tag
    let allTags: [Tag]
    @Binding var tagEdit: TagEditTarget?
    @Binding var selection: LibrarySection?
    @Environment(\.modelContext) private var context
    @State private var expanded = true

    var body: some View {
        if tag.childTags.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(tag.childTags) { child in
                    TagOutlineRow(tag: child, allTags: allTags, tagEdit: $tagEdit, selection: $selection)
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        Label {
            HStack {
                Text(tag.name)
                Spacer()
                Text("\(tag.allTaggedShortcuts.filter { !$0.isMissing }.count)").foregroundStyle(.tertiary).monospacedDigit()
            }
        } icon: {
            Image(systemName: "tag.fill").foregroundStyle(Color(hex: tag.colorHex))
        }
        .tag(LibrarySection.tag(tag.uuid))
        .sidebarRowPadding()
        .dropDestination(for: String.self) { ids, _ in
            LibraryActions.addTag(tag, toIdentifiers: ids, context: context); return true
        }
        .contextMenu {
            Button("New Tag Inside…", systemImage: "tag") { tagEdit = .new(parent: tag) }
            Button("Edit Tag…", systemImage: "pencil") { tagEdit = .edit(tag) }
            Divider()
            Menu("Move To", systemImage: "arrow.right.doc.on.clipboard") {
                Button { LibraryActions.move(tag: tag, into: nil) } label: {
                    Label("Top Level", systemImage: tag.parent == nil ? "checkmark" : "rectangle.split.3x1")
                }
                Divider()
                ForEach(LibraryActions.flattenedTags(allTags).filter { $0.tag !== tag && !$0.tag.isDescendant(of: tag) }, id: \.tag.uuid) { entry in
                    Button { LibraryActions.move(tag: tag, into: entry.tag) } label: {
                        Label(String(repeating: "    ", count: entry.depth) + entry.tag.name,
                              systemImage: tag.parent === entry.tag ? "checkmark" : "tag")
                    }
                }
            }
            if let parent = tag.parent {
                Button("Move Out of \(parent.name)", systemImage: "arrow.up.left") {
                    LibraryActions.move(tag: tag, into: parent.parent)
                }
            }
            Divider()
            Button("Delete Tag", systemImage: "trash", role: .destructive) {
                if selection == .tag(tag.uuid) { selection = .all }
                LibraryActions.delete(tag: tag, context: context)
            }
        }
    }
}

// MARK: - Editor targets

enum FolderEditTarget: Identifiable {
    case new(parent: LibraryFolder?)
    case edit(LibraryFolder)
    var id: String {
        switch self {
        case .new(let parent): "new-\(parent?.uuid ?? "root")"
        case .edit(let folder): "edit-\(folder.uuid)"
        }
    }
}

enum TagEditTarget: Identifiable {
    case new(parent: Tag?)
    case edit(Tag)
    var id: String {
        switch self {
        case .new(let parent): "new-\(parent?.uuid ?? "root")"
        case .edit(let tag): "edit-\(tag.uuid)"
        }
    }
}

enum SmartListEditTarget: Identifiable {
    case new
    case edit(SmartList)
    var id: String {
        switch self {
        case .new: "new"
        case .edit(let list): "edit-\(list.uuid)"
        }
    }
}

private extension View {
    /// Breathing room inside sidebar rows: taller lines and text inset from the row edges.
    func sidebarRowPadding() -> some View {
        self.padding(.vertical, 3).padding(.horizontal, 4)
    }
}
