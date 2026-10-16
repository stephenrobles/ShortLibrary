import SwiftData
import SwiftUI

struct SmartListEditor: View {
    let target: SmartListEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var shortcuts: [ShortcutItem]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @Query private var smartLists: [SmartList]

    @State private var name = ""
    @State private var symbol = "sparkles"
    @State private var colorHex = "#AF52DE"
    @State private var rules = SmartRuleSet()

    private var matchCount: Int { shortcuts.filter { rules.matches($0) }.count }

    var body: some View {
        EditorSheet(title: isNew ? "New Smart List" : "Edit Smart List",
                    canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            Section {
                TextField("Name", text: $name)
                Picker("Match", selection: $rules.matchAll) {
                    Text("All of the rules").tag(true)
                    Text("Any of the rules").tag(false)
                }
                Toggle("Include shortcuts missing from Shortcuts", isOn: $rules.includeMissing)
            }

            Section {
                ForEach($rules.rules) { $rule in
                    SmartRuleRow(rule: $rule, tags: tags, folders: folders) {
                        rules.rules.removeAll { $0.id == rule.id }
                    }
                }
                Button("Add Rule", systemImage: "plus.circle.fill") {
                    rules.rules.append(SmartRule())
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    Text("\(matchCount.formatted()) match").foregroundStyle(.secondary).monospacedDigit()
                }
            }

            Section("Sort") {
                Picker("Sort by", selection: $rules.sort) {
                    ForEach(ShortcutSort.allCases) { Text($0.title).tag($0) }
                }
                Picker("Order", selection: $rules.ascending) {
                    Text(rules.sort.ascendingLabel).tag(true)
                    Text(rules.sort.descendingLabel).tag(false)
                }
            }

            Section("Color") { ColorSwatchPicker(hex: $colorHex) }
            Section("Icon") { SymbolPicker(symbol: $symbol, tint: Color(hex: colorHex)) }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
        .onAppear {
            if case .edit(let list) = target {
                name = list.name; symbol = list.symbolName; colorHex = list.colorHex; rules = list.rules
            }
        }
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .edit(let list):
            list.name = trimmed; list.symbolName = symbol; list.colorHex = colorHex; list.rules = rules
        case .new:
            let list = SmartList(name: trimmed, rules: rules)
            list.symbolName = symbol; list.colorHex = colorHex
            list.sortOrder = (smartLists.map(\.sortOrder).max() ?? -1) + 1
            context.insert(list)
        }
        try? context.save()
        dismiss()
    }
}

struct SmartRuleRow: View {
    @Binding var rule: SmartRule
    let tags: [Tag]
    let folders: [LibraryFolder]
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Field", selection: $rule.field) {
                    ForEach(SmartRule.Field.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            operand
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var operand: some View {
        switch rule.field.kind {
        case .text:
            HStack {
                Picker("Comparison", selection: $rule.textOp) {
                    ForEach(SmartRule.TextOp.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                TextField("Text", text: $rule.text).textFieldStyle(.roundedBorder)
            }
        case .number:
            HStack {
                Picker("Comparison", selection: $rule.numberOp) {
                    ForEach(SmartRule.NumberOp.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                TextField("Number", value: $rule.number, format: .number).textFieldStyle(.roundedBorder).frame(maxWidth: 100)
            }
        case .date:
            HStack {
                Picker("Comparison", selection: $rule.dateOp) {
                    ForEach(SmartRule.DateOp.allCases.filter { rule.field == .lastRun || $0 != .never }) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                if rule.dateOp != .never {
                    Stepper(value: $rule.days, in: 1...3650) {
                        Text("\(rule.days) \(rule.days == 1 ? "day" : "days")")
                    }
                    .fixedSize()
                }
            }
        case .bool:
            Picker("Value", selection: $rule.boolValue) {
                Text(rule.field == .missing ? "is missing" : "is on").tag(true)
                Text(rule.field == .missing ? "is present" : "is off").tag(false)
            }
            .labelsHidden().fixedSize()
        case .tag:
            HStack {
                Picker("Has", selection: $rule.boolValue) {
                    Text("has").tag(true)
                    Text("does not have").tag(false)
                }
                .labelsHidden().fixedSize()
                Picker("Tag", selection: $rule.referenceUUID) {
                    Text("any tag").tag("")
                    ForEach(tags) { Text($0.name).tag($0.uuid) }
                }
                .labelsHidden().fixedSize()
            }
        case .folder:
            HStack {
                Picker("In", selection: $rule.boolValue) {
                    Text("is in").tag(true)
                    Text("is not in").tag(false)
                }
                .labelsHidden().fixedSize()
                Picker("Folder", selection: $rule.referenceUUID) {
                    Text("any folder").tag("")
                    ForEach(LibraryActions.flattenedFolders(folders), id: \.folder.uuid) { entry in
                        Text(String(repeating: "    ", count: entry.depth) + entry.folder.name).tag(entry.folder.uuid)
                    }
                }
                .labelsHidden().fixedSize()
            }
        case .color:
            HStack {
                Picker("Is", selection: $rule.boolValue) {
                    Text("is").tag(true)
                    Text("is not").tag(false)
                }
                .labelsHidden().fixedSize()
                Picker("Color", selection: $rule.text) {
                    ForEach(TileColor.families, id: \.name) { family in
                        Label(family.name, systemImage: "circle.fill").tag(family.name)
                    }
                }
                .labelsHidden().fixedSize()
                .onAppear { if rule.text.isEmpty { rule.text = "Blue" } }
            }
        }
    }
}
