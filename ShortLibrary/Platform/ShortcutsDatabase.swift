#if os(macOS)
import AppKit
import Foundation
import SQLite3

/// Read-only access to Shortcuts' own database (~/Library/Shortcuts/Shortcuts.sqlite), which is the only
/// place that records which app a shortcut's icon comes from. Access is granted by the user through an
/// Open panel and kept as a security-scoped bookmark, so this stays inside the App Sandbox.
@MainActor
enum ShortcutsDatabase {
    private static let bookmarkKey = "shortcutsFolderBookmark"

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Shortcuts", isDirectory: true)
    }

    static var isLinked: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Asks the user to grant access to the Shortcuts folder.
    static func link() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultFolder
        panel.message = "Select the Shortcuts folder so ShortLibrary can show app icons the way Shortcuts does."
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            return true
        } catch {
            return false
        }
    }

    static func unlink() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }

    private static func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }

    /// Copies the database (and its WAL) into our container so sqlite can open a consistent snapshot.
    private static func snapshotDatabase(in folder: URL) throws -> URL {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("ShortcutsSnapshot", isDirectory: true)
        try? fm.removeItem(at: temp)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        for name in ["Shortcuts.sqlite", "Shortcuts.sqlite-wal", "Shortcuts.sqlite-shm"] {
            let source = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: temp.appendingPathComponent(name))
            }
        }
        return temp.appendingPathComponent("Shortcuts.sqlite")
    }

    struct Row: Sendable {
        var workflowID: String
        var appBundleID: String?
        var userProvidedIcon: Bool
        var createdAt: Date?
        var modifiedAt: Date?
        var lastRunAt: Date?
    }

    /// Reads every shortcut's associated app and dates. Returns nil when the folder isn't linked or readable.
    static func readRows() -> [String: Row]? {
        withFolder { folder in
            guard let dbURL = try? snapshotDatabase(in: folder) else { return [:] }
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [:] }
            defer { sqlite3_close(db) }
            let sql = "select ZWORKFLOWID, ZASSOCIATEDAPPBUNDLEIDENTIFIER, ZHASUSERPROVIDEDNAMEORICON, ZCREATIONDATE, ZMODIFICATIONDATE, ZLASTRUNEVENTDATE from ZSHORTCUT where ZTOMBSTONED = 0 or ZTOMBSTONED is null"
            var rows: [String: Row] = [:]
            for r in query(db, sql) {
                guard let id = r["ZWORKFLOWID"], id != "NULL" else { continue }
                func date(_ key: String) -> Date? {
                    guard let v = r[key], v != "NULL", let t = Double(v) else { return nil }
                    return Date(timeIntervalSinceReferenceDate: t)
                }
                let bundle = r["ZASSOCIATEDAPPBUNDLEIDENTIFIER"].flatMap { $0 == "NULL" || $0.isEmpty ? nil : $0 }
                rows[id] = Row(workflowID: id, appBundleID: bundle,
                               userProvidedIcon: (r["ZHASUSERPROVIDEDNAMEORICON"] ?? "0") == "1",
                               createdAt: date("ZCREATIONDATE"), modifiedAt: date("ZMODIFICATIONDATE"), lastRunAt: date("ZLASTRUNEVENTDATE"))
            }
            return rows
        }
    }

    /// Runs a query and returns rows as text dictionaries (blobs reported by size).
    static func query(_ db: OpaquePointer, _ sql: String) -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        let count = sqlite3_column_count(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_NULL: row[name] = "NULL"
                case SQLITE_BLOB: row[name] = "<blob \(sqlite3_column_bytes(statement, i))B>"
                default: row[name] = sqlite3_column_text(statement, i).map { String(cString: $0) } ?? ""
                }
            }
            rows.append(row)
        }
        return rows
    }
}
#endif
