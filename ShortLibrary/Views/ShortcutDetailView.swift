import SwiftData
import SwiftUI

/// Inspector for one shortcut: run it, organize it, annotate it.
struct ShortcutDetailView: View {
    @Bindable var item: ShortcutItem
    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var input = ""
    @State private var tagEdit: TagEditTarget?
    private var runner = ShortcutRunner.shared

    init(item: ShortcutItem) {
        self.item = item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                runControls
                organizeSection
                notesSection
                detailsSection
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle(item.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    item.isFavorite.toggle(); try? context.save()
                } label: {
                    Label("Favorite", systemImage: item.isFavorite ? "star.fill" : "star")
                }
                .help(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                Menu {
                    ShortcutContextMenu(item: item) { _ in }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        #endif
        .sheet(item: $tagEdit) { target in TagEditor(target: target, applyTo: item) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ShortcutIconView(item: item, size: 76, style: .standalone)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.title2.weight(.bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle.isEmpty ? "\(item.actionCount) actions" : item.subtitle).foregroundStyle(.secondary)
                if item.isMissing {
                    Label("Not found in Shortcuts during the last sync", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if item.hasNameOnlyIdentifier {
                    Label("Added from iPhone or iPad; a Mac sync will link its identifier", systemImage: "iphone")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.acceptsInput {
                TextField("Input to pass to the shortcut (optional)", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
            }
            HStack(spacing: 10) {
                Button {
                    runner.run(item, input: item.acceptsInput ? input : nil)
                } label: {
                    if runner.isRunning(item) {
                        Label { Text("Running…") } icon: { ProgressView().controlSize(.small) }
                    } else {
                        Label("Run Shortcut", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(runner.isRunning(item) || item.isMissing)

                Button {
                    ShortcutURLs.openInShortcuts(item)
                } label: {
                    Label("Open in Shortcuts", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
            }
            #if !os(macOS)
            Text("Shortcuts opens to run it and returns here when it finishes.")
                .font(.caption).foregroundStyle(.secondary)
            #endif
        }
    }

    private var organizeSection: some View {
        GroupBox("Organize") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Folder") {
                    Menu {
                        Button("None") { item.folder = nil; try? context.save() }
                        Divider()
                        ForEach(LibraryActions.flattenedFolders(folders), id: \.folder.uuid) { entry in
                            Button {
                                item.folder = entry.folder; try? context.save()
                            } label: {
                                Label(String(repeating: "    ", count: entry.depth) + entry.folder.name,
                                      systemImage: item.folder === entry.folder ? "checkmark" : entry.folder.symbolName)
                            }
                        }
                    } label: {
                        if let folder = item.folder {
                            Label(folder.path.map(\.name).joined(separator: " › "), systemImage: folder.symbolName)
                        } else {
                            Label("None", systemImage: "folder")
                        }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags")
                    TagChipFlow(tags: item.tagList, onRemove: { tag in
                        LibraryActions.remove(tag, from: item); try? context.save()
                    }, trailing: {
                        Menu {
                            ForEach(LibraryActions.flattenedTags(tags).filter { entry in !item.tagList.contains { $0 === entry.tag } }, id: \.tag.uuid) { entry in
                                Button {
                                    LibraryActions.add(entry.tag, to: item); try? context.save()
                                } label: {
                                    Label(String(repeating: "    ", count: entry.depth) + entry.tag.name, systemImage: "tag.fill")
                                }
                            }
                            if !tags.isEmpty { Divider() }
                            Button("New Tag…", systemImage: "plus") { tagEdit = .new(parent: nil) }
                        } label: {
                            Label("Add Tag", systemImage: "plus.circle.fill").labelStyle(.titleAndIcon)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                    })
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notesSection: some View {
        GroupBox("Notes") {
            TextEditor(text: $item.notes)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .onChange(of: item.notes) { _, _ in try? context.save() }
        }
    }

    private var detailsSection: some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 8) {
                detail("Shortcuts Folder", item.nativeFolderName.isEmpty ? "None" : item.nativeFolderName)
                detail("Accepts Input", item.acceptsInput ? "Yes" : "No")
                detail("Actions", "\(item.actionCount)")
                detail("Color", item.tileColor.family)
                detail(item.nativeCreatedAt == nil ? "Added to Library" : "Created", item.createdDate.formatted(date: .abbreviated, time: .shortened))
                detail(item.nativeModifiedAt == nil ? "Last Changed" : "Last Modified", item.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                detail("Last Run", item.lastRunAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                detail("Run Count", "\(item.runCount)")
                detail("Identifier", item.identifier)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).textSelection(.enabled).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

/// Wrapping row of tag chips.
struct TagChipFlow<Trailing: View>: View {
    let tags: [Tag]
    var onRemove: (Tag) -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: tag.colorHex)).frame(width: 8, height: 8)
                    Text(tag.name).font(.callout)
                    Button { onRemove(tag) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color(hex: tag.colorHex).opacity(0.16), in: Capsule())
            }
            trailing
        }
    }
}

/// Minimal left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
