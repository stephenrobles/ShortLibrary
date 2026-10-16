import Foundation

/// A saved filter. Evaluated in memory against the whole library, which is small enough
/// (hundreds of shortcuts, not millions) that a predicate pipeline isn't worth its rigidity.
struct SmartRuleSet: Codable, Hashable {
    var matchAll: Bool = true
    var rules: [SmartRule] = [SmartRule()]
    var sort: ShortcutSort = .libraryOrder
    var ascending: Bool = true
    var includeMissing: Bool = false

    func matches(_ item: ShortcutItem) -> Bool {
        if !includeMissing && item.isMissing { return false }
        let active = rules
        if active.isEmpty { return true }
        if matchAll { return active.allSatisfy { $0.matches(item) } }
        return active.contains { $0.matches(item) }
    }
}

struct SmartRule: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var field: Field = .name
    var textOp: TextOp = .contains
    var numberOp: NumberOp = .greaterThan
    var dateOp: DateOp = .withinDays
    var boolValue: Bool = true
    var text: String = ""
    var number: Int = 0
    var days: Int = 7
    /// `Tag.uuid` or `LibraryFolder.uuid`, depending on the field.
    var referenceUUID: String = ""

    enum Field: String, Codable, CaseIterable, Identifiable {
        case name, subtitle, notes, nativeFolder, tag, folder, favorite, acceptsInput, actionCount, runCount, dateAdded, modified, lastRun, color, missing
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: "Name"
            case .subtitle: "Subtitle"
            case .notes: "Notes"
            case .nativeFolder: "Shortcuts Folder"
            case .tag: "Tag"
            case .folder: "Folder"
            case .favorite: "Favorite"
            case .acceptsInput: "Accepts Input"
            case .actionCount: "Action Count"
            case .runCount: "Run Count"
            case .dateAdded: "Date Added"
            case .modified: "Last Modified"
            case .lastRun: "Last Run"
            case .color: "Color"
            case .missing: "Missing from Shortcuts"
            }
        }
        var kind: Kind {
            switch self {
            case .name, .subtitle, .notes, .nativeFolder: .text
            case .tag: .tag
            case .folder: .folder
            case .favorite, .acceptsInput, .missing: .bool
            case .actionCount, .runCount: .number
            case .dateAdded, .modified, .lastRun: .date
            case .color: .color
            }
        }
        enum Kind { case text, tag, folder, bool, number, date, color }
    }

    enum TextOp: String, Codable, CaseIterable, Identifiable {
        case contains, notContains, equals, beginsWith, endsWith
        var id: String { rawValue }
        var title: String {
            switch self {
            case .contains: "contains"
            case .notContains: "does not contain"
            case .equals: "is"
            case .beginsWith: "begins with"
            case .endsWith: "ends with"
            }
        }
    }

    enum NumberOp: String, Codable, CaseIterable, Identifiable {
        case equals, greaterThan, lessThan
        var id: String { rawValue }
        var title: String {
            switch self {
            case .equals: "is"
            case .greaterThan: "is greater than"
            case .lessThan: "is less than"
            }
        }
    }

    enum DateOp: String, Codable, CaseIterable, Identifiable {
        case withinDays, notWithinDays, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .withinDays: "in the last"
            case .notWithinDays: "not in the last"
            case .never: "never"
            }
        }
    }

    func matches(_ item: ShortcutItem) -> Bool {
        switch field.kind {
        case .text:
            let haystack: String
            switch field {
            case .name: haystack = item.name
            case .subtitle: haystack = item.subtitle
            case .notes: haystack = item.notes
            default: haystack = item.nativeFolderName
            }
            return textMatches(haystack)
        case .tag:
            let tags = item.tagList
            if referenceUUID.isEmpty { return boolValue ? !tags.isEmpty : tags.isEmpty }
            let has = tags.contains { tag in tag.path.contains { $0.uuid == referenceUUID } }
            return boolValue ? has : !has
        case .folder:
            guard let folder = item.folder else { return referenceUUID.isEmpty ? boolValue : !boolValue }
            if referenceUUID.isEmpty { return !boolValue }
            let inside = folder.path.contains { $0.uuid == referenceUUID }
            return boolValue ? inside : !inside
        case .bool:
            let value: Bool
            switch field {
            case .favorite: value = item.isFavorite
            case .acceptsInput: value = item.acceptsInput
            default: value = item.isMissing
            }
            return value == boolValue
        case .number:
            let value = field == .actionCount ? item.actionCount : item.runCount
            switch numberOp {
            case .equals: return value == number
            case .greaterThan: return value > number
            case .lessThan: return value < number
            }
        case .date:
            let date: Date?
            switch field {
            case .dateAdded: date = item.createdDate
            case .modified: date = item.modifiedDate
            default: date = item.lastRunAt
            }
            switch dateOp {
            case .never: return date == nil
            case .withinDays:
                guard let date else { return false }
                return date >= Date().addingTimeInterval(-Double(max(days, 0)) * 86_400)
            case .notWithinDays:
                guard let date else { return true }
                return date < Date().addingTimeInterval(-Double(max(days, 0)) * 86_400)
            }
        case .color:
            let has = item.tileColor.family == text
            return boolValue ? has : !has
        }
    }

    private func textMatches(_ value: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return true }
        let a = value.lowercased(), b = needle.lowercased()
        switch textOp {
        case .contains: return a.contains(b)
        case .notContains: return !a.contains(b)
        case .equals: return a == b
        case .beginsWith: return a.hasPrefix(b)
        case .endsWith: return a.hasSuffix(b)
        }
    }
}

enum ShortcutSort: String, Codable, CaseIterable, Identifiable {
    case libraryOrder, name, dateAdded, modified, lastRun, actionCount, runCount
    var id: String { rawValue }
    var title: String {
        switch self {
        case .libraryOrder: "Shortcuts Order"
        case .name: "Name"
        case .dateAdded: "Date Added"
        case .modified: "Last Modified"
        case .lastRun: "Last Run"
        case .actionCount: "Action Count"
        case .runCount: "Run Count"
        }
    }
    /// Whether "ascending" is the natural default for this key.
    var defaultAscending: Bool { self == .name || self == .libraryOrder }
    var ascendingLabel: String {
        switch self {
        case .libraryOrder: "As in Shortcuts"
        case .name: "A to Z"
        default: "Oldest First"
        }
    }
    var descendingLabel: String {
        switch self {
        case .libraryOrder: "Reversed"
        case .name: "Z to A"
        default: "Newest First"
        }
    }

    func sorted(_ items: [ShortcutItem], ascending: Bool) -> [ShortcutItem] {
        let base: [ShortcutItem]
        switch self {
        case .libraryOrder:
            base = items.sorted { ($0.libraryOrder, $0.name) < ($1.libraryOrder, $1.name) }
        case .name:
            base = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateAdded:
            base = items.sorted { $0.createdDate < $1.createdDate }
        case .modified:
            base = items.sorted { $0.modifiedDate < $1.modifiedDate }
        case .lastRun:
            base = items.sorted { ($0.lastRunAt ?? .distantPast) < ($1.lastRunAt ?? .distantPast) }
        case .actionCount:
            base = items.sorted { $0.actionCount < $1.actionCount }
        case .runCount:
            base = items.sorted { $0.runCount < $1.runCount }
        }
        return ascending ? base : Array(base.reversed())
    }
}
