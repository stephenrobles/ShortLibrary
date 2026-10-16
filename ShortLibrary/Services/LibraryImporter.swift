import Foundation
import SwiftData

/// Merges snapshots from a sync source into the SwiftData store. Shared by the Mac bridge and the
/// iOS helper-shortcut intents so both platforms reconcile the same way.
enum LibraryImporter {
    /// Applies a complete picture of the library. Anything not present is flagged missing.
    @discardableResult
    static func applyFullSync(_ snapshots: [ShortcutSnapshot], context: ModelContext) throws -> SyncSummary {
        let now = Date()
        var summary = SyncSummary(total: snapshots.count)
        let existing = try context.fetch(FetchDescriptor<ShortcutItem>())
        var byIdentifier: [String: ShortcutItem] = [:]
        var byName: [String: [ShortcutItem]] = [:]
        for item in existing {
            byIdentifier[item.identifier] = item
            byName[item.name, default: []].append(item)
        }

        var seen = Set<ObjectIdentifier>()
        for (index, snapshot) in snapshots.enumerated() {
            let (item, created) = resolve(snapshot, byIdentifier: &byIdentifier, byName: &byName, context: context, now: now)
            seen.insert(ObjectIdentifier(item))
            if item.libraryOrder != index { item.libraryOrder = index }
            if created { summary.added += 1 }
            else if apply(snapshot, to: item, now: now) { summary.updated += 1 }
            item.lastSeenAt = now
            item.isMissing = false
        }

        for item in existing where !seen.contains(ObjectIdentifier(item)) {
            if !item.isMissing { item.isMissing = true }
            summary.missing += 1
        }
        try context.save()
        return summary
    }

    /// Applies one snapshot from an incremental source (the iOS helper shortcut sends one call per shortcut).
    @discardableResult
    static func applyItem(_ snapshot: ShortcutSnapshot, context: ModelContext, now: Date = Date()) throws -> ShortcutItem {
        let name = snapshot.name
        let identifier = snapshot.identifier
        let nameKey = ShortcutItem.nameIdentifier(for: name)
        let existing = try context.fetch(FetchDescriptor<ShortcutItem>(
            predicate: #Predicate { $0.name == name || $0.identifier == identifier || $0.identifier == nameKey }))
        var byIdentifier: [String: ShortcutItem] = [:]
        var byName: [String: [ShortcutItem]] = [:]
        for item in existing {
            byIdentifier[item.identifier] = item
            byName[item.name, default: []].append(item)
        }
        let (item, created) = resolve(snapshot, byIdentifier: &byIdentifier, byName: &byName, context: context, now: now)
        if !created { _ = apply(snapshot, to: item, now: now) }
        item.lastSeenAt = now
        item.isMissing = false
        try context.save()
        return item
    }

    /// Applies a batch of incremental snapshots in one pass with a single save.
    static func applyItems(_ snapshots: [ShortcutSnapshot], context: ModelContext, now: Date = Date()) throws {
        guard !snapshots.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<ShortcutItem>())
        var byIdentifier: [String: ShortcutItem] = [:]
        var byName: [String: [ShortcutItem]] = [:]
        for item in existing {
            byIdentifier[item.identifier] = item
            byName[item.name, default: []].append(item)
        }
        for snapshot in snapshots {
            let (item, created) = resolve(snapshot, byIdentifier: &byIdentifier, byName: &byName, context: context, now: now)
            if !created { _ = apply(snapshot, to: item, now: now) }
            item.lastSeenAt = now
            item.isMissing = false
        }
        try context.save()
    }

    /// After an incremental sync finishes, flag everything that wasn't touched since it began.
    @discardableResult
    static func finishIncrementalSync(startedAt: Date, context: ModelContext) throws -> SyncSummary {
        let all = try context.fetch(FetchDescriptor<ShortcutItem>())
        var summary = SyncSummary(total: 0)
        for item in all {
            if item.lastSeenAt >= startedAt {
                summary.total += 1
            } else {
                item.isMissing = true
                summary.missing += 1
            }
        }
        try context.save()
        return summary
    }

    // MARK: Matching

    private static func resolve(_ snapshot: ShortcutSnapshot,
                                byIdentifier: inout [String: ShortcutItem],
                                byName: inout [String: [ShortcutItem]],
                                context: ModelContext, now: Date) -> (ShortcutItem, Bool) {
        // 1. Exact identifier (Mac UUID or a previous name-only record).
        if !snapshot.identifier.isEmpty, let item = byIdentifier[snapshot.identifier] { return (item, false) }
        let nameKey = ShortcutItem.nameIdentifier(for: snapshot.name)
        if snapshot.identifier.isEmpty, let item = byIdentifier[nameKey] { return (item, false) }

        // 2. Same name. Prefer a record that only has a name-based identity, then a missing one,
        //    then any record with the name (iOS has no identifiers, so the name is all it can offer).
        if let candidates = byName[snapshot.name], !candidates.isEmpty {
            let pick = candidates.first { $0.hasNameOnlyIdentifier }
                ?? candidates.first { $0.isMissing }
                ?? (snapshot.identifier.isEmpty ? candidates.first : nil)
            if let pick {
                if !snapshot.identifier.isEmpty && pick.identifier != snapshot.identifier {
                    byIdentifier[pick.identifier] = nil
                    pick.identifier = snapshot.identifier
                    byIdentifier[snapshot.identifier] = pick
                }
                return (pick, false)
            }
        }

        // 3. New record.
        let item = ShortcutItem(identifier: snapshot.identifier.isEmpty ? nameKey : snapshot.identifier, name: snapshot.name)
        item.firstSeenAt = now
        item.lastChangedAt = now
        _ = apply(snapshot, to: item, now: now)
        context.insert(item)
        byIdentifier[item.identifier] = item
        byName[item.name, default: []].append(item)
        return (item, true)
    }

    /// Copies synced fields and reports whether anything meaningful changed.
    private static func apply(_ snapshot: ShortcutSnapshot, to item: ShortcutItem, now: Date) -> Bool {
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<ShortcutItem, T>, _ value: T) {
            if item[keyPath: keyPath] != value { item[keyPath: keyPath] = value; changed = true }
        }
        set(\.name, snapshot.name)
        if !snapshot.subtitle.isEmpty { set(\.subtitle, snapshot.subtitle) }
        if !snapshot.colorHex.isEmpty { set(\.colorHex, snapshot.colorHex) }
        set(\.acceptsInput, snapshot.acceptsInput || (snapshot.identifier.isEmpty && item.acceptsInput))
        if snapshot.actionCount > 0 { set(\.actionCount, snapshot.actionCount) }
        set(\.nativeFolderName, snapshot.folderName)
        if let created = snapshot.createdAt { set(\.nativeCreatedAt, created) }
        if let modified = snapshot.modifiedAt { set(\.nativeModifiedAt, modified) }
        if let order = snapshot.libraryOrder, item.libraryOrder != order { item.libraryOrder = order }
        if let processed = snapshot.processedIcon ?? snapshot.iconImageData.flatMap(IconProcessing.process) {
            item.applyProcessedIcon(processed)
        }
        if changed { item.lastChangedAt = snapshot.modifiedAt ?? now }
        return changed
    }
}
