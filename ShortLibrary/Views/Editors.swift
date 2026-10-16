import SwiftData
import SwiftUI

let editorSymbols = [
    "folder", "folder.fill", "star", "heart", "bolt", "house", "briefcase", "car", "airplane", "music.note",
    "camera", "photo", "video", "mic", "bell", "calendar", "clock", "list.bullet", "checkmark.circle", "doc.text",
    "book", "gamecontroller", "tv", "cart", "creditcard", "gift", "leaf", "flame", "drop", "moon",
    "sun.max", "cloud", "globe", "map", "location", "wrench", "hammer", "gearshape", "terminal", "network",
    "person", "person.2", "message", "envelope", "phone", "tag", "sparkles", "wand.and.stars", "lightbulb", "flag",
]

let editorColors: [(name: String, hex: String)] = [
    ("Red", "#F36F74"), ("Orange", "#FF8E73"), ("Yellow", "#F8AE5F"), ("Gold", "#E8CA45"), ("Green", "#53CD6B"),
    ("Teal", "#57CFB4"), ("Cyan", "#5ACCDE"), ("Blue", "#24BAF7"), ("Navy", "#5874CA"), ("Purple", "#9164C7"),
    ("Lavender", "#C085E6"), ("Pink", "#F694D8"), ("Gray", "#9099A3"), ("Sage", "#9DA79D"), ("Tan", "#A49995"),
]

/// Grid of color swatches used by every editor.
struct ColorSwatchPicker: View {
    @Binding var hex: String
    var allowNone = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)], spacing: 8) {
            if allowNone {
                swatch(hex: "", color: .secondary.opacity(0.3), label: "Default")
            }
            ForEach(editorColors, id: \.hex) { entry in
                swatch(hex: entry.hex, color: Color(hex: entry.hex), label: entry.name)
            }
        }
    }

    private func swatch(hex value: String, color: Color, label: String) -> some View {
        Button {
            hex = value
        } label: {
            Circle().fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    if hex == value { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct SymbolPicker: View {
    @Binding var symbol: String
    var tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
            ForEach(editorSymbols, id: \.self) { name in
                Button { symbol = name } label: {
                    Image(systemName: name)
                        .font(.body)
                        .frame(width: 32, height: 32)
                        .background(symbol == name ? tint.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(symbol == name ? tint : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Folder

struct FolderEditor: View {
    let target: FolderEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @State private var name = ""
    @State private var symbol = "folder"
    @State private var colorHex = ""
    @State private var parent: LibraryFolder?

    private var editing: LibraryFolder? {
        if case .edit(let folder) = target { return folder }
        return nil
    }

    var body: some View {
        EditorSheet(title: editing == nil ? "New Folder" : "Edit Folder", canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            TextField("Name", text: $name)
            Picker("Inside", selection: $parent) {
                Text("Top Level").tag(LibraryFolder?.none)
                ForEach(LibraryActions.flattenedFolders(folders).filter { candidate in
                    guard let editing else { return true }
                    return candidate.folder !== editing && !candidate.folder.isDescendant(of: editing)
                }, id: \.folder.uuid) { entry in
                    Text(String(repeating: "    ", count: entry.depth) + entry.folder.name).tag(LibraryFolder?.some(entry.folder))
                }
            }
            Section("Color") { ColorSwatchPicker(hex: $colorHex, allowNone: true) }
            Section("Icon") { SymbolPicker(symbol: $symbol, tint: colorHex.isEmpty ? .accentColor : Color(hex: colorHex)) }
        }
        .onAppear {
            switch target {
            case .new(let p): parent = p
            case .edit(let folder):
                name = folder.name; symbol = folder.symbolName; colorHex = folder.colorHex; parent = folder.parent
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let folder = editing {
            folder.name = trimmed; folder.symbolName = symbol; folder.colorHex = colorHex; folder.parent = parent
        } else {
            let folder = LibraryFolder(name: trimmed, parent: parent)
            folder.symbolName = symbol; folder.colorHex = colorHex
            context.insert(folder)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Tag

struct TagEditor: View {
    let target: TagEditTarget
    var applyTo: ShortcutItem? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var name = ""
    @State private var colorHex = "#24BAF7"
    @State private var parent: Tag?

    private var editing: Tag? {
        if case .edit(let tag) = target { return tag }
        return nil
    }

    var body: some View {
        EditorSheet(title: editing == nil ? "New Tag" : "Edit Tag", canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            TextField("Name", text: $name)
            Picker("Nested Under", selection: $parent) {
                Text("Top Level").tag(Tag?.none)
                ForEach(LibraryActions.flattenedTags(tags).filter { candidate in
                    guard let editing else { return true }
                    return candidate.tag !== editing && !candidate.tag.isDescendant(of: editing)
                }, id: \.tag.uuid) { entry in
                    Text(String(repeating: "    ", count: entry.depth) + entry.tag.name).tag(Tag?.some(entry.tag))
                }
            }
            Section("Color") { ColorSwatchPicker(hex: $colorHex) }
        }
        .onAppear {
            switch target {
            case .new(let p): parent = p
            case .edit(let tag): name = tag.name; colorHex = tag.colorHex; parent = tag.parent
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .edit(let tag):
            tag.name = trimmed; tag.colorHex = colorHex; tag.parent = parent
        case .new:
            let tag = Tag(name: trimmed, colorHex: colorHex, parent: parent)
            context.insert(tag)
            if let applyTo { LibraryActions.add(tag, to: applyTo) }
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Shared sheet chrome

struct EditorSheet<Content: View>: View {
    let title: String
    var canSave: Bool
    var onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { content }
                .formStyle(.grouped)
                .navigationTitle(title)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: onSave).disabled(!canSave) }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
