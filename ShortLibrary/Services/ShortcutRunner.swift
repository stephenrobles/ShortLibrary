import Foundation
import SwiftData
import SwiftUI

/// Runs shortcuts and records the outcome. On macOS this goes through Shortcuts Events in the
/// background. On iOS and visionOS it opens the Shortcuts app through its URL scheme.
@MainActor
@Observable
final class ShortcutRunner {
    static let shared = ShortcutRunner()

    struct Outcome: Identifiable {
        let id = UUID()
        var shortcutName: String
        var output: String?
        var error: String?
        var date = Date()
        var isError: Bool { error != nil }
    }

    private(set) var runningIdentifiers: Set<String> = []
    var latestOutcome: Outcome?

    func isRunning(_ item: ShortcutItem) -> Bool { runningIdentifiers.contains(item.identifier) }

    func run(_ item: ShortcutItem, input: String? = nil) {
        let identifier = item.identifier
        let name = item.name
        runningIdentifiers.insert(identifier)
        item.lastRunAt = Date()
        item.runCount += 1
        try? item.modelContext?.save()

        Task {
            defer { runningIdentifiers.remove(identifier) }
            do {
                let output = try await perform(identifier: identifier, name: name, input: input)
                latestOutcome = Outcome(shortcutName: name, output: output, error: nil)
            } catch {
                latestOutcome = Outcome(shortcutName: name, output: nil, error: error.localizedDescription)
            }
        }
    }

    private func perform(identifier: String, name: String, input: String?) async throws -> String? {
        #if os(macOS)
        return try await ShortcutsEventsBridge.shared.run(identifier: identifier, name: name, input: input)
        #else
        let url = ShortcutURLs.run(name: name, input: input)
        let opened = await UIApplication.shared.open(url)
        if !opened { throw RunError.couldNotOpenShortcuts }
        return nil
        #endif
    }

    enum RunError: LocalizedError {
        case couldNotOpenShortcuts
        var errorDescription: String? { "The Shortcuts app couldn't be opened." }
    }
}

/// URL scheme helpers shared by every platform.
enum ShortcutURLs {
    static let callbackScheme = "shortlibrary"

    static func run(name: String, input: String?) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        var items = [URLQueryItem(name: "name", value: name)]
        if let input, !input.isEmpty {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        items.append(URLQueryItem(name: "x-success", value: "\(callbackScheme)://run-success?name=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"))
        items.append(URLQueryItem(name: "x-error", value: "\(callbackScheme)://run-error?name=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"))
        items.append(URLQueryItem(name: "x-cancel", value: "\(callbackScheme)://run-cancel"))
        components.queryItems = items
        return components.url!
    }

    static func open(name: String) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url!
    }

    static func openShortcutsApp() -> URL { URL(string: "shortcuts://")! }

    static func openInShortcuts(_ item: ShortcutItem) {
        let url = open(name: item.name)
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Handles `shortlibrary://` callbacks from Shortcuts after a URL-scheme run.
    @MainActor
    static func handleCallback(_ url: URL, runner: ShortcutRunner) {
        guard url.scheme == callbackScheme else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let name = components?.queryItems?.first { $0.name == "name" }?.value?.removingPercentEncoding ?? "Shortcut"
        switch url.host {
        #if DEBUG
        case "diagnostics":
            Diagnostics.copy(forName: name == "Shortcut" ? nil : name)
        case "inspector":
            LibraryNavigation.shared.showInspector = components?.queryItems?.first { $0.name == "show" }?.value != "0"
            if LibraryNavigation.shared.selectedShortcut == nil {
                LibraryNavigation.shared.selectedShortcut = (try? Persistence.context.fetch(FetchDescriptor<ShortcutItem>()))?.first
            }
        case "stress":
            // Exercises inspector toggling and selection changes rapidly to shake out layout aborts.
            Task { @MainActor in
                let items = (try? Persistence.context.fetch(FetchDescriptor<ShortcutItem>())) ?? []
                for i in 0..<60 {
                    LibraryNavigation.shared.showInspector.toggle()
                    if i % 2 == 0 { LibraryNavigation.shared.selectedShortcut = items.isEmpty ? nil : items[i % items.count] }
                    if i % 7 == 0 { LibraryNavigation.shared.selectedShortcut = nil }
                    if i % 11 == 0 { LibraryNavigation.shared.section = [.favorites, .recent, .all, .untagged][i % 4] }
                    try? await Task.sleep(for: .milliseconds(120))
                }
                LibraryNavigation.shared.section = .all
            }
        #endif
        case "run-success":
            let result = components?.queryItems?.first { $0.name == "result" }?.value
            runner.latestOutcome = ShortcutRunner.Outcome(shortcutName: name, output: result, error: nil)
        case "run-error":
            let message = components?.queryItems?.first { $0.name == "errorMessage" }?.value ?? "The shortcut reported an error."
            runner.latestOutcome = ShortcutRunner.Outcome(shortcutName: name, output: nil, error: message)
        default:
            break
        }
    }
}
