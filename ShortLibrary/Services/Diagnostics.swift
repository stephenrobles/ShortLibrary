#if DEBUG
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Debug-only: `shortlibrary://diagnostics?name=<shortcut name>` copies that record's synced fields and
/// its stored icon (base64 PNG) to the clipboard, so imports can be inspected without UI automation.
@MainActor
enum Diagnostics {
    static func copy(forName name: String?) {
        let context = Persistence.context
        let all = (try? context.fetch(FetchDescriptor<ShortcutItem>())) ?? []
        var lines: [String] = ["count=\(all.count)"]
        let targets: [ShortcutItem]
        if name == "__apps" {
            // Summary of app-based shortcuts: which bundle ids resolved to an icon and which didn't.
            var resolved: [String: Int] = [:], unresolved: [String: Int] = [:]
            for item in all where !item.appBundleID.isEmpty {
                if item.iconAppBundleID == item.appBundleID { resolved[item.appBundleID, default: 0] += 1 }
                else { unresolved[item.appBundleID, default: 0] += 1 }
            }
            lines.append("resolved apps=\(resolved.count) shortcuts=\(resolved.values.reduce(0, +))")
            lines.append("unresolved apps=\(unresolved.count) shortcuts=\(unresolved.values.reduce(0, +))")
            for (k, v) in unresolved.sorted(by: { $0.value > $1.value }) { lines.append("  missing \(k) x\(v)") }
            for (k, v) in resolved.sorted(by: { $0.value > $1.value }).prefix(40) { lines.append("  ok \(k) x\(v)") }
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
            #endif
            return
        }
        if let name, !name.isEmpty {
            targets = all.filter { $0.name == name }
        } else {
            targets = Array(all.sorted { $0.libraryOrder < $1.libraryOrder }.prefix(12))
        }
        let formatter = ISO8601DateFormatter()
        for item in targets {
            lines.append("name=\(item.name) | id=\(item.identifier) | order=\(item.libraryOrder) | folder=\(item.nativeFolderName) | actions=\(item.actionCount) | app=\(item.appBundleID) iconApp=\(item.iconAppBundleID) | icon=\(item.iconData?.count ?? 0)B | top=\(item.iconTopHex) bottom=\(item.iconBottomHex) | created=\(item.nativeCreatedAt.map(formatter.string) ?? "nil") modified=\(item.nativeModifiedAt.map(formatter.string) ?? "nil") | seen=\(formatter.string(from: item.lastSeenAt))")
            if name != nil, let data = item.iconData { lines.append("iconbase64=\(data.base64EncodedString())") }
        }
        let text = lines.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
#endif
