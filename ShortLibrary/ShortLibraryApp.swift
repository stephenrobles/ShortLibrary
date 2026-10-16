import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct ShortLibraryApp: App {
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Persistence.container)
        .commands { LibraryCommands() }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

struct LibraryCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Sync with Shortcuts") {
                Task { await LibrarySyncController.shared.syncNow() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Run Selected Shortcut") {
                if let item = LibraryNavigation.shared.selectedShortcut {
                    ShortcutRunner.shared.run(item)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(LibraryNavigation.shared.selectedShortcut == nil)

            #if os(macOS)
            Divider()
            Button("Install Helper Shortcut…") {
                LibrarySyncController.shared.installHelperShortcut()
            }
            Button("Run Helper Shortcut (Icons & Dates)") {
                Task { await LibrarySyncController.shared.runHelperShortcut() }
            }
            Button("Retry Icons from Shortcuts Events") {
                LibrarySyncController.shared.refreshAllIcons()
            }
            Divider()
            Button(LibrarySyncController.shared.databaseLinked ? "Refresh App Icons from Shortcuts Database" : "Link Shortcuts Database for App Icons…") {
                Task {
                    if LibrarySyncController.shared.databaseLinked {
                        await LibrarySyncController.shared.enrichFromShortcutsDatabase()
                    } else {
                        await LibrarySyncController.shared.linkShortcutsDatabase()
                    }
                }
            }
            #endif
        }
    }
}

/// Shared navigation state so menu commands can reach the current selection.
@MainActor
@Observable
final class LibraryNavigation {
    static let shared = LibraryNavigation()
    var section: LibrarySection? = .all
    var selectedShortcut: ShortcutItem?
    /// macOS detail inspector. Closed by default; the last state is remembered.
    var showInspector: Bool = UserDefaults.standard.bool(forKey: "showInspector") {
        didSet { UserDefaults.standard.set(showInspector, forKey: "showInspector") }
    }
}

/// Everything the sidebar can select.
enum LibrarySection: Hashable {
    case all, favorites, recent, unfiled, untagged, missing
    case folder(String)
    case tag(String)
    case smartList(String)
    case nativeFolder(String)
}
