import SwiftData
import SwiftUI

/// The middle column: whatever the sidebar selected, searchable and sortable, as a grid or list.
struct ShortcutCollectionView: View {
    let section: LibrarySection
    @Binding var selectedShortcut: ShortcutItem?

    @Environment(\.modelContext) private var context
    @Query private var shortcuts: [ShortcutItem]
    @Query private var folders: [LibraryFolder]
    @Query private var tags: [Tag]
    @Query private var smartLists: [SmartList]

    @AppStorage("viewMode") private var viewMode: ViewMode = .grid
    @AppStorage("sortKey") private var sortKey: ShortcutSort = .libraryOrder
    @AppStorage("sortAscending") private var sortAscending = true
    @AppStorage("includeSubfolders") private var includeSubfolders = true
    @AppStorage("doubleClickRuns") private var doubleClickRuns = true
    @State private var searchText = ""
    @State private var inputPrompt: ShortcutItem?
    @State private var inputText = ""
    private var runner = ShortcutRunner.shared
    private var syncer = LibrarySyncController.shared

    enum ViewMode: String { case grid, list }

    init(section: LibrarySection, selectedShortcut: Binding<ShortcutItem?>) {
        self.section = section
        self._selectedShortcut = selectedShortcut
    }

    // MARK: Derived data

    private var currentSmartList: SmartList? {
        if case .smartList(let uuid) = section { return smartLists.first { $0.uuid == uuid } }
        return nil
    }

    private var sectionItems: [ShortcutItem] {
        switch section {
        case .all: return shortcuts.filter { !$0.isMissing }
        case .favorites: return shortcuts.filter { $0.isFavorite && !$0.isMissing }
        case .recent: return shortcuts.filter { $0.lastRunAt != nil && !$0.isMissing }
        case .unfiled: return shortcuts.filter { $0.folder == nil && !$0.isMissing }
        case .untagged: return shortcuts.filter { $0.tagList.isEmpty && !$0.isMissing }
        case .missing: return shortcuts.filter(\.isMissing)
        case .folder(let uuid):
            guard let folder = folders.first(where: { $0.uuid == uuid }) else { return [] }
            return (includeSubfolders ? folder.allShortcuts : folder.directShortcuts).filter { !$0.isMissing }
        case .tag(let uuid):
            return tags.first { $0.uuid == uuid }?.allTaggedShortcuts.filter { !$0.isMissing } ?? []
        case .smartList(let uuid):
            guard let list = smartLists.first(where: { $0.uuid == uuid }) else { return [] }
            let rules = list.rules
            return shortcuts.filter { rules.matches($0) }
        case .nativeFolder(let name):
            return shortcuts.filter { $0.nativeFolderName == name && !$0.isMissing }
        }
    }

    private var visibleItems: [ShortcutItem] {
        var items = sectionItems
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            items = items.filter { item in
                item.name.lowercased().contains(needle)
                    || item.notes.lowercased().contains(needle)
                    || item.nativeFolderName.lowercased().contains(needle)
                    || item.tagList.contains { $0.name.lowercased().contains(needle) }
            }
        }
        if section == .recent && (sortKey == .name || sortKey == .libraryOrder) {
            return ShortcutSort.lastRun.sorted(items, ascending: false)
        }
        return sortKey.sorted(items, ascending: sortAscending)
    }

    private var title: String {
        switch section {
        case .all: "All Shortcuts"
        case .favorites: "Favorites"
        case .recent: "Recently Run"
        case .unfiled: "Not in a Folder"
        case .untagged: "Untagged"
        case .missing: "Missing from Shortcuts"
        case .folder(let uuid): folders.first { $0.uuid == uuid }?.name ?? "Folder"
        case .tag(let uuid): tags.first { $0.uuid == uuid }?.name ?? "Tag"
        case .smartList(let uuid): smartLists.first { $0.uuid == uuid }?.name ?? "Smart List"
        case .nativeFolder(let name): name
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
        false
        #else
        horizontalSizeClass == .compact
        #endif
    }
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: Body

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                emptyState
            } else if viewMode == .grid {
                grid
            } else {
                list
            }
        }
        .navigationTitle(title)
        #if !os(visionOS)
        .navigationSubtitle(subtitle)
        #endif
        #if os(macOS)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search shortcuts, tags, notes")
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .onChange(of: section) { _, _ in
            if let list = currentSmartList {
                sortKey = list.rules.sort
                sortAscending = list.rules.ascending
            }
        }
        .alert("Run \(inputPrompt?.name ?? "Shortcut") with Input", isPresented: Binding(get: { inputPrompt != nil }, set: { if !$0 { inputPrompt = nil } })) {
            TextField("Input text", text: $inputText)
            Button("Run") {
                if let item = inputPrompt { runner.run(item, input: inputText) }
                inputPrompt = nil
            }
            Button("Cancel", role: .cancel) { inputPrompt = nil }
        } message: {
            Text("The text is passed to the shortcut as its input.")
        }
        #if !os(macOS)
        .navigationDestination(for: ShortcutItem.self) { item in ShortcutDetailView(item: item) }
        #endif
    }

    private var subtitle: String {
        let count = visibleItems.count
        return count == 1 ? "1 shortcut" : "\(count.formatted()) shortcuts"
    }

    private var emptyState: some View {
        Group {
            if shortcuts.isEmpty {
                #if os(macOS)
                ContentUnavailableView {
                    Label("No Shortcuts Yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("ShortLibrary reads your library from the Shortcuts app. Sync to get started.")
                } actions: {
                    Button("Sync with Shortcuts") { Task { await syncer.syncNow() } }.buttonStyle(.borderedProminent)
                }
                #else
                HelperShortcutView()
                #endif
            } else if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ContentUnavailableView("Nothing Here", systemImage: "tray",
                                       description: Text(emptyHint))
            }
        }
    }

    private var emptyHint: String {
        switch section {
        case .favorites: "Star a shortcut to keep it here."
        case .folder: "Drag shortcuts onto this folder in the sidebar, or use Move to Folder."
        case .tag: "Drag shortcuts onto this tag in the sidebar, or use the Tags menu."
        case .smartList: "No shortcuts match these rules yet."
        default: "No shortcuts in this view."
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 156), spacing: 13)], spacing: 13) {
                ForEach(visibleItems) { item in
                    tileCell(item)
                }
            }
            .padding(16)
        }
        .background(Color.canvas)
    }

    @ViewBuilder
    private func tileCell(_ item: ShortcutItem) -> some View {
        let tile = ShortcutTile(item: item, isSelected: selectedShortcut === item)
        if isCompact {
            NavigationLink(value: item) { tile }
                .buttonStyle(.plain)
                .contextMenu { ShortcutContextMenu(item: item) { prompt($0) } }
        } else {
            tile
                .onTapGesture(count: 2) {
                    if doubleClickRuns { runner.run(item) }
                }
                .onTapGesture { selectedShortcut = item }
                .contextMenu { ShortcutContextMenu(item: item) { prompt($0) } }
                .draggable(item.identifier)
        }
    }

    private var list: some View {
        List {
            ForEach(visibleItems) { item in
                let row = ShortcutRow(item: item, isSelected: selectedShortcut === item)
                Group {
                    if isCompact {
                        NavigationLink(value: item) { row }
                    } else {
                        row
                            .onTapGesture(count: 2) { if doubleClickRuns { runner.run(item) } }
                            .onTapGesture { selectedShortcut = item }
                            .listRowBackground(selectedShortcut === item ? Color.accentColor.opacity(0.14) : Color.clear)
                            .draggable(item.identifier)
                    }
                }
                .contextMenu { ShortcutContextMenu(item: item) { prompt($0) } }
            }
        }
        .listStyle(.plain)
    }

    private func prompt(_ item: ShortcutItem) {
        inputText = ""
        inputPrompt = item
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItemGroup(placement: .primaryAction) {
            sortMenu
            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .help("Grid or list")
            syncButton
            Button {
                LibraryNavigation.shared.showInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the details pane")
            Button {
                guard let item = selectedShortcut else { return }
                item.isFavorite.toggle()
                try? context.save()
            } label: {
                Label("Favorite", systemImage: selectedShortcut?.isFavorite == true ? "star.fill" : "star")
            }
            .disabled(selectedShortcut == nil)
            .help(selectedShortcut?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites")
            Menu {
                if let item = selectedShortcut {
                    ShortcutContextMenu(item: item) { prompt($0) }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(selectedShortcut == nil)
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $sortKey) {
                    ForEach(ShortcutSort.allCases) { key in Text(key.title).tag(key) }
                }
                .onChange(of: sortKey) { _, newValue in sortAscending = newValue.defaultAscending }
                Picker("Order", selection: $sortAscending) {
                    Text(sortKey.ascendingLabel).tag(true)
                    Text(sortKey.descendingLabel).tag(false)
                }
                Picker("View", selection: $viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                    Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                }
            } label: {
                Label("View Options", systemImage: "ellipsis.circle")
            }
            syncButton
        }
        #endif
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortKey) {
                ForEach(ShortcutSort.allCases) { key in Text(key.title).tag(key) }
            }
            .onChange(of: sortKey) { _, newValue in sortAscending = newValue.defaultAscending }
            Divider()
            Picker("Order", selection: $sortAscending) {
                Text(sortKey.ascendingLabel).tag(true)
                Text(sortKey.descendingLabel).tag(false)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort by \(sortKey.title)")
    }

    private var syncButton: some View {
        Button {
            Task { await syncer.syncNow() }
        } label: {
            if syncer.phase == .syncing {
                ProgressView().controlSize(.small)
            } else {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(syncer.phase == .syncing)
        .help("Sync with Shortcuts (⌘R)")
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            switch syncer.phase {
            case .syncing:
                ProgressView().controlSize(.mini)
                Text("Syncing with Shortcuts…")
            case .icons(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 110)
                Text("Loading icons \(done.formatted()) of \(total.formatted())")
            case .idle:
                if let date = syncer.lastSyncDate {
                    Text("Synced \(date, format: .relative(presentation: .named))")
                    if let summary = syncer.lastSummary { Text("·"); Text(summary.message) }
                    #if os(macOS)
                    if !syncer.databaseLinked {
                        Text("·")
                        Button("Link Shortcuts database for app icons") { Task { await syncer.linkShortcutsDatabase() } }
                            .buttonStyle(.link).font(.caption)
                    }
                    if syncer.iconFetchBlocked && shortcuts.contains(where: { $0.iconData == nil && !$0.isMissing }) {
                        Text("·")
                        Button("Get icons with the helper shortcut") { Task { await syncer.runHelperShortcut() } }
                            .buttonStyle(.link).font(.caption)
                    }
                    #endif
                } else {
                    Text("Not synced yet")
                }
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension Color {
    /// Window background behind the grid.
    static var canvas: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}
