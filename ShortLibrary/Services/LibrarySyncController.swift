import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Owns the sync lifecycle: pulling the library from Shortcuts, reporting progress, and
/// backfilling icons on macOS. On iOS the sync itself arrives through App Intents, so this
/// object mostly tracks state for the UI there.
@MainActor
@Observable
final class LibrarySyncController {
    static let shared = LibrarySyncController()

    enum Phase: Equatable {
        case idle
        case syncing
        case icons(done: Int, total: Int)

        var isBusy: Bool { self != .idle }
    }

    private(set) var phase: Phase = .idle
    private(set) var lastSummary: SyncSummary?
    private(set) var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    var lastError: String?

    /// iOS: when a helper-shortcut sync began (so the finishing intent can flag stragglers).
    var incrementalSyncStartedAt: Date? {
        get { UserDefaults.standard.object(forKey: "incrementalSyncStartedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "incrementalSyncStartedAt") }
    }

    var context: ModelContext { Persistence.context }

    // MARK: Buffered imports from the helper shortcut

    private var pendingImports: [ShortcutSnapshot] = []
    private var flushTask: Task<Void, Never>?

    /// Intents call this once per shortcut. Writes are coalesced so the UI re-renders about once a
    /// second instead of once per shortcut, which is what keeps a 2,500-item helper run fast.
    func enqueueImport(_ snapshot: ShortcutSnapshot) {
        pendingImports.append(snapshot)
        if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.flushImports()
            }
        }
    }

    func flushImports() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingImports.isEmpty else { return }
        let batch = pendingImports
        pendingImports.removeAll()
        do {
            try LibraryImporter.applyItems(batch, context: context)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Called by the Finish intent once the helper shortcut has delivered everything.
    func noteIncrementalSyncFinished(_ summary: SyncSummary) {
        lastSummary = summary
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
        if phase != .syncing { phase = .idle }
    }

    #if os(macOS)
    /// Shortcuts Events refuses the icon property from a sandboxed app (-10004). When that happens
    /// icons come from the helper shortcut instead, and we stop asking until the user retries.
    private(set) var iconFetchBlocked = UserDefaults.standard.bool(forKey: "iconFetchBlocked")
    private var iconTask: Task<Void, Never>?
    private var priorityIdentifiers: [String] = []
    private var iconQueue: [String] = []
    private var iconsCompleted = 0
    private var iconsTotal = 0

    /// Full metadata sync from Shortcuts Events, then icon backfill for anything new.
    func syncNow() async {
        guard phase != .syncing else { return }
        phase = .syncing
        lastError = nil
        do {
            let snapshots = try await ShortcutsEventsBridge.shared.fetchLibrary()
            let summary = try LibraryImporter.applyFullSync(snapshots, context: context)
            lastSummary = summary
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
            phase = .idle
            await enrichFromShortcutsDatabase()
            backfillMissingIcons()
        } catch {
            lastError = error.localizedDescription
            phase = .idle
        }
    }

    /// Whether the user has granted access to Shortcuts' database folder.
    var databaseLinked: Bool { ShortcutsDatabase.isLinked }

    /// Prompts for the Shortcuts folder, then pulls app icons and dates right away.
    func linkShortcutsDatabase() async {
        guard ShortcutsDatabase.link() else { return }
        await enrichFromShortcutsDatabase()
    }

    /// Reads Shortcuts' own database for each shortcut's associated app and real dates, then renders
    /// app icons the way Shortcuts shows them. No-op until the user has linked the folder.
    func enrichFromShortcutsDatabase() async {
        guard let rows = ShortcutsDatabase.readRows(), !rows.isEmpty else { return }
        let items = (try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []
        // Bump when drawn stand-ins change so they re-render once.
        let drawnVersion = 2
        if UserDefaults.standard.integer(forKey: "drawnAppIconVersion") < drawnVersion {
            for item in items where AppIconProvider.drawnFallbacks[item.iconAppBundleID] != nil { item.iconAppBundleID = "" }
            UserDefaults.standard.set(drawnVersion, forKey: "drawnAppIconVersion")
        }
        var needingIcons: [ShortcutItem] = []
        for item in items {
            guard let row = rows[item.identifier] else { continue }
            if let created = row.createdAt, item.nativeCreatedAt != created { item.nativeCreatedAt = created }
            if let modified = row.modifiedAt, item.nativeModifiedAt != modified { item.nativeModifiedAt = modified }
            if let lastRun = row.lastRunAt, (item.lastRunAt ?? .distantPast) < lastRun { item.lastRunAt = lastRun }
            let bundle = row.userProvidedIcon ? "" : (row.appBundleID ?? "")
            if item.appBundleID != bundle { item.appBundleID = bundle }
            if bundle.isEmpty {
                if !item.iconAppBundleID.isEmpty {
                    // Icon reverted to a glyph; drop the app icon so the glyph backfill refetches it.
                    item.iconAppBundleID = ""
                    item.iconData = nil
                }
            } else if item.iconAppBundleID != bundle {
                needingIcons.append(item)
            }
        }
        try? context.save()
        guard !needingIcons.isEmpty else { return }

        // Phase 1: installed apps and drawn stand-ins, grouped by bundle id so each icon renders once.
        let groups = Dictionary(grouping: needingIcons, by: \.appBundleID)
        var remote: [String] = []
        for (bundle, items) in groups {
            if let png = AppIconProvider.shared.installedIcon(for: bundle) {
                for item in items { item.iconData = png; item.iconAppBundleID = bundle }
            } else {
                remote.append(bundle)
            }
        }
        try? context.save()

        // Phase 2: App Store artwork for everything else, a few lookups at a time.
        guard !remote.isEmpty else { return }
        let results = await withTaskGroup(of: (String, Data?).self, returning: [String: Data?].self) { group in
            var pending = remote[...]
            var collected: [String: Data?] = [:]
            var active = 0
            while !pending.isEmpty || active > 0 {
                while active < 4, let bundle = pending.popFirst() {
                    active += 1
                    group.addTask { (bundle, await AppIconProvider.shared.remoteIcon(for: bundle)) }
                }
                if let (bundle, png) = await group.next() {
                    active -= 1
                    collected[bundle] = png
                }
            }
            return collected
        }
        for (bundle, png) in results {
            guard let items = groups[bundle] else { continue }
            for item in items {
                if let png { item.iconData = png; item.iconAppBundleID = bundle } else { item.iconAppBundleID = "" }
            }
        }
        try? context.save()
    }

    /// Runs the bundled helper shortcut through Shortcuts Events. It calls back into the app's
    /// intents with icons and dates, which the scripting interface can't provide from the sandbox.
    func runHelperShortcut() async {
        lastError = nil
        do {
            _ = try await ShortcutsEventsBridge.shared.run(named: HelperShortcut.name)
        } catch let error as ShortcutsEventsBridge.BridgeError {
            if case .script(let number, _) = error, number == -1728 {
                lastError = "The “\(HelperShortcut.name)” shortcut isn't installed yet. Use File › Install Helper Shortcut first."
            } else {
                lastError = error.localizedDescription
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Opens the bundled signed helper shortcut so Shortcuts offers to add it.
    func installHelperShortcut() {
        guard let url = HelperShortcut.bundledFileURL else {
            lastError = "The helper shortcut isn't bundled with this build."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Icons stored before glyph extraction existed are full tiles; convert them in place once.
    func migrateStoredIconsIfNeeded() async {
        let key = "iconFormatVersion"
        guard UserDefaults.standard.integer(forKey: key) < 2 else { return }
        let items = ((try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []).filter { $0.iconData != nil && $0.iconTopHex.isEmpty }
        defer { UserDefaults.standard.set(2, forKey: key) }
        var index = 0
        while index < items.count {
            let slice = Array(items[index..<min(index + 50, items.count)])
            let payload = slice.map { ($0.identifier, $0.iconData!) }
            let results = await Task.detached(priority: .utility) {
                payload.compactMap { id, data in IconProcessing.process(data).map { (id, $0) } }
            }.value
            let byID = Dictionary(slice.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, processed) in results { byID[id]?.applyProcessedIcon(processed) }
            try? context.save()
            index += 50
        }
        UserDefaults.standard.set(2, forKey: key)
    }

    /// Version 3 trims stored glyph masks to their bounds (version 2 kept the icon's empty margins).
    func trimStoredGlyphsIfNeeded() async {
        let key = "iconFormatVersion"
        guard UserDefaults.standard.integer(forKey: key) < 3 else { return }
        let items = ((try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []).filter { $0.iconData != nil }
        var index = 0
        while index < items.count {
            let slice = Array(items[index..<min(index + 50, items.count)])
            let payload = slice.map { ($0.identifier, $0.iconData!) }
            let results = await Task.detached(priority: .utility) {
                payload.compactMap { id, data in IconProcessing.trimmedGlyphPNG(data).map { (id, $0) } }
            }.value
            let byID = Dictionary(slice.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
            for (id, png) in results { byID[id]?.iconData = png }
            try? context.save()
            index += 50
        }
        UserDefaults.standard.set(3, forKey: key)
    }

    /// Version 4: gradient colors stored before the sampling fix are upside down; swap them.
    func fixGradientOrientationIfNeeded() {
        let key = "iconFormatVersion"
        guard UserDefaults.standard.integer(forKey: key) < 4 else { return }
        let items = (try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []
        for item in items where !item.iconTopHex.isEmpty {
            let top = item.iconTopHex
            item.iconTopHex = item.iconBottomHex
            item.iconBottomHex = top
        }
        try? context.save()
        UserDefaults.standard.set(4, forKey: key)
    }

    /// Queue icons for every shortcut that doesn't have one yet.
    func backfillMissingIcons() {
        guard !iconFetchBlocked else { return }
        let descriptor = FetchDescriptor<ShortcutItem>(predicate: #Predicate { $0.iconData == nil && !$0.isMissing })
        let ids = ((try? context.fetch(descriptor)) ?? []).map(\.identifier).filter { !$0.hasPrefix("name:") }
        enqueueIcons(ids)
    }

    /// Re-fetch every icon, for when the user has changed glyphs inside Shortcuts.
    func refreshAllIcons() {
        setIconFetchBlocked(false)
        let items = (try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []
        enqueueIcons(items.filter { !$0.isMissing && !$0.hasNameOnlyIdentifier }.map(\.identifier))
    }

    /// Visible tiles call this so icons on screen arrive first.
    func prioritizeIcon(for item: ShortcutItem) {
        guard item.iconData == nil, !item.hasNameOnlyIdentifier, iconQueue.contains(item.identifier) else { return }
        if !priorityIdentifiers.contains(item.identifier) { priorityIdentifiers.append(item.identifier) }
    }

    private func enqueueIcons(_ identifiers: [String]) {
        let pending = Set(iconQueue)
        let fresh = identifiers.filter { !pending.contains($0) }
        guard !fresh.isEmpty else { return }
        iconQueue.append(contentsOf: fresh)
        iconsTotal += fresh.count
        if iconTask == nil { startIconTask() }
    }

    private func startIconTask() {
        iconTask = Task { [weak self] in
            guard let self else { return }
            let batchSize = 8
            outer: while !Task.isCancelled {
                // Fetch a batch off the main actor first, then apply it in one pass so SwiftUI
                // re-renders once per batch instead of once per icon.
                var batch: [(String, IconProcessing.Result)] = []
                var attempted = 0
                while batch.count < batchSize, attempted < batchSize, let identifier = nextIconIdentifier() {
                    attempted += 1
                    do {
                        if let raw = try await ShortcutsEventsBridge.shared.fetchIconData(identifier: identifier),
                           let processed = await Task.detached(priority: .utility, operation: { IconProcessing.process(raw) }).value {
                            batch.append((identifier, processed))
                        }
                    } catch let error as ShortcutsEventsBridge.BridgeError where error.isPrivilegeViolation {
                        setIconFetchBlocked(true)
                        iconQueue.removeAll()
                        priorityIdentifiers.removeAll()
                        break outer
                    } catch {
                        // Keep going; a single bad icon shouldn't stop the backfill.
                    }
                }
                if attempted == 0 { break }
                if !batch.isEmpty {
                    let wanted = Set(batch.map(\.0))
                    let descriptor = FetchDescriptor<ShortcutItem>(predicate: #Predicate { wanted.contains($0.identifier) })
                    let items = (try? context.fetch(descriptor)) ?? []
                    let byID = Dictionary(items.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
                    for (identifier, processed) in batch { byID[identifier]?.applyProcessedIcon(processed) }
                    try? context.save()
                }
                iconsCompleted += attempted
                if phase != .syncing { phase = .icons(done: iconsCompleted, total: iconsTotal) }
            }
            try? context.save()
            iconsCompleted = 0
            iconsTotal = 0
            if phase != .syncing { phase = .idle }
            iconTask = nil
        }
    }

    private func setIconFetchBlocked(_ blocked: Bool) {
        iconFetchBlocked = blocked
        UserDefaults.standard.set(blocked, forKey: "iconFetchBlocked")
    }

    private func nextIconIdentifier() -> String? {
        while let priority = priorityIdentifiers.first {
            priorityIdentifiers.removeFirst()
            if let index = iconQueue.firstIndex(of: priority) {
                iconQueue.remove(at: index)
                return priority
            }
        }
        guard !iconQueue.isEmpty else { return nil }
        return iconQueue.removeFirst()
    }
    #else
    func syncNow() async {
        // iOS and visionOS can't enumerate the library directly. Launch the helper shortcut,
        // which calls back into the app's sync intents.
        lastError = nil
        let url = ShortcutURLs.run(name: HelperShortcut.name, input: nil)
        let opened = await UIApplication.shared.open(url)
        if !opened { lastError = "Couldn't open Shortcuts. Install the \(HelperShortcut.name) helper shortcut first." }
    }

    func prioritizeIcon(for item: ShortcutItem) {}
    #endif
}

/// Names shared between the app and the helper shortcut that feeds it on iOS.
enum HelperShortcut {
    static let name = "Sync ShortLibrary"
}
