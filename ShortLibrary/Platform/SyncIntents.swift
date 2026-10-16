import AppIntents
import CoreGraphics
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension HelperShortcut {
    /// Public iCloud link for the signed helper shortcut. Fill in after publishing it.
    static let downloadURL: URL? = nil
    /// The signed helper shortcut bundled with the app.
    static var bundledFileURL: URL? { Bundle.main.url(forResource: name, withExtension: "shortcut") }
}

struct BeginLibrarySyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Begin ShortLibrary Sync"
    static let description = IntentDescription("Call this before importing shortcuts so ShortLibrary can tell which ones disappeared.")

    @MainActor func perform() async throws -> some IntentResult {
        LibrarySyncController.shared.incrementalSyncStartedAt = Date()
        return .result()
    }
}

struct ImportShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Shortcut into ShortLibrary"
    static let description = IntentDescription("Adds or updates one shortcut in ShortLibrary. Pass values from Get Details of Shortcut.")

    @Parameter(title: "Name") var name: String
    @Parameter(title: "Identifier") var identifier: String?
    @Parameter(title: "Shortcuts Folder") var folder: String?
    @Parameter(title: "Action Count") var actionCount: Int?
    @Parameter(title: "Icon", supportedContentTypes: [.image]) var icon: IntentFile?
    @Parameter(title: "Creation Date") var created: Date?
    @Parameter(title: "Last Modified Date") var modified: Date?
    @Parameter(title: "Position", description: "The Repeat Index, so ShortLibrary can keep Shortcuts' own order.") var position: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$name) into ShortLibrary") {
            \.$identifier
            \.$folder
            \.$actionCount
            \.$icon
            \.$created
            \.$modified
            \.$position
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let trimmedID = (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var snapshot = ShortcutSnapshot(identifier: trimmedID, name: name)
        snapshot.folderName = folder ?? ""
        snapshot.actionCount = actionCount ?? 0
        snapshot.createdAt = created
        snapshot.modifiedAt = modified
        if let position { snapshot.libraryOrder = max(0, position - 1) }
        if let icon {
            let data = icon.data
            if let processed = await Task.detached(priority: .userInitiated, operation: { IconProcessing.process(data) }).value {
                snapshot.processedIcon = processed
                snapshot.colorHex = processed.topHex
            }
        }
        LibrarySyncController.shared.enqueueImport(snapshot)
        return .result(value: name)
    }
}

struct FinishLibrarySyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish ShortLibrary Sync"
    static let description = IntentDescription("Call this after importing so shortcuts that no longer exist are flagged as missing.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let controller = LibrarySyncController.shared
        controller.flushImports()
        let started = controller.incrementalSyncStartedAt ?? .distantPast
        let summary = try LibraryImporter.finishIncrementalSync(startedAt: started, context: Persistence.context)
        controller.noteIncrementalSyncFinished(summary)
        controller.incrementalSyncStartedAt = nil
        return .result(value: summary.message)
    }
}

struct ShortLibraryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FinishLibrarySyncIntent(), phrases: ["Finish \(.applicationName) sync"],
                    shortTitle: "Finish Sync", systemImageName: "checkmark.circle")
    }
}
