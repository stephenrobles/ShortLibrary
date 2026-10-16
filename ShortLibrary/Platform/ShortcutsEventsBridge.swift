#if os(macOS)
import AppKit
import Foundation

/// Talks to the "Shortcuts Events" background scripting target with Apple Events.
/// Everything runs on a private serial queue so long shortcut runs never block the UI.
nonisolated final class ShortcutsEventsBridge: Sendable {
    static let shared = ShortcutsEventsBridge()

    private let queue = DispatchQueue(label: "fm.beard.ShortLibrary.shortcuts-events", qos: .userInitiated)

    enum BridgeError: LocalizedError {
        case script(number: Int, message: String)
        case unexpectedReply

        /// The sandbox's scripting-targets entitlement doesn't cover this property or command.
        var isPrivilegeViolation: Bool {
            if case .script(let number, _) = self { return number == -10004 }
            return false
        }

        var errorDescription: String? {
            switch self {
            case .script(let number, let message):
                switch number {
                case -1743:
                    return "ShortLibrary isn't allowed to control Shortcuts. Enable it under System Settings › Privacy & Security › Automation."
                case -600:
                    return "Shortcuts Events isn't available on this Mac."
                case -10004:
                    return "Shortcuts doesn't allow this from a sandboxed app."
                default:
                    return "\(message) (\(number))"
                }
            case .unexpectedReply:
                return "Shortcuts returned a reply ShortLibrary didn't understand."
            }
        }
    }

    // MARK: Public API

    func fetchLibrary() async throws -> [ShortcutSnapshot] {
        let source = """
        tell application "Shortcuts Events"
            set theNames to name of every shortcut
            set theIDs to id of every shortcut
            set theSubtitles to subtitle of every shortcut
            set theColors to color of every shortcut
            set theInputs to accepts input of every shortcut
            set theCounts to action count of every shortcut
            set folderNames to name of every folder
            set memberships to {}
            -- Index access only: the sandbox's scripting-targets grant rejects folder references and "folder id" lookups.
            repeat with i from 1 to count of folders
                set end of memberships to id of every shortcut of folder i
            end repeat
            return {theNames, theIDs, theSubtitles, theColors, theInputs, theCounts, folderNames, memberships}
        end tell
        """
        let reply = try await execute(source)
        return try Self.parseLibrary(reply)
    }

    /// Fetches one icon as the raw TIFF Shortcuts renders (512px, tile gradient plus white glyph).
    func fetchIconData(identifier: String) async throws -> Data? {
        let source = "tell application \"Shortcuts Events\" to get icon of shortcut id \(Self.quote(identifier))"
        let reply = try await execute(source)
        return Self.imageData(from: reply)
    }

    /// Runs a shortcut in the background and returns its textual output, if any.
    /// Tries the stable identifier first and falls back to the name if the sandbox rejects "shortcut id".
    func run(identifier: String, name: String, input: String?) async throws -> String? {
        var suffix = ""
        if let input, !input.isEmpty { suffix = " with input \(Self.quote(input))" }
        if !identifier.isEmpty && !identifier.hasPrefix("name:") {
            do {
                let reply = try await execute("tell application \"Shortcuts Events\" to run shortcut id \(Self.quote(identifier))\(suffix)")
                return Self.describe(reply)
            } catch let error as BridgeError where error.isPrivilegeViolation {
                // Fall through to the name form.
            }
        }
        let reply = try await execute("tell application \"Shortcuts Events\" to run shortcut \(Self.quote(name))\(suffix)")
        return Self.describe(reply)
    }

    /// Runs a shortcut by name (used for the helper shortcut, which has no stored identifier).
    func run(named name: String) async throws -> String? {
        let source = "tell application \"Shortcuts Events\" to run shortcut \(Self.quote(name))"
        return Self.describe(try await execute(source))
    }

    /// Moves a shortcut into one of Shortcuts' own folders (the only writable property).
    func setNativeFolder(identifier: String, folderName: String?) async throws {
        let target = folderName.map { "folder \(Self.quote($0))" } ?? "missing value"
        let source = "tell application \"Shortcuts Events\" to set folder of shortcut id \(Self.quote(identifier)) to \(target)"
        _ = try await execute(source)
    }

    // MARK: Execution

    private func execute(_ source: String) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: BridgeError.unexpectedReply)
                    return
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                    continuation.resume(throwing: BridgeError.script(number: number, message: message))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: Parsing

    private static func parseLibrary(_ reply: NSAppleEventDescriptor) throws -> [ShortcutSnapshot] {
        guard reply.numberOfItems == 8,
              let names = reply.atIndex(1), let ids = reply.atIndex(2), let subtitles = reply.atIndex(3),
              let colors = reply.atIndex(4), let inputs = reply.atIndex(5), let counts = reply.atIndex(6),
              let folderNames = reply.atIndex(7), let memberships = reply.atIndex(8)
        else { throw BridgeError.unexpectedReply }

        var folderByShortcut: [String: String] = [:]
        for f in 0..<folderNames.numberOfItems {
            let folderName = folderNames.atIndex(f + 1)?.stringValue ?? ""
            guard let members = memberships.atIndex(f + 1) else { continue }
            for m in 0..<members.numberOfItems {
                if let id = members.atIndex(m + 1)?.stringValue { folderByShortcut[id] = folderName }
            }
        }

        var result: [ShortcutSnapshot] = []
        result.reserveCapacity(names.numberOfItems)
        for i in 1...max(names.numberOfItems, 1) where i <= names.numberOfItems {
            guard let id = ids.atIndex(i)?.stringValue, let name = names.atIndex(i)?.stringValue else { continue }
            var snapshot = ShortcutSnapshot(identifier: id, name: name)
            snapshot.subtitle = subtitles.atIndex(i)?.stringValue ?? ""
            snapshot.colorHex = colorHex(from: colors.atIndex(i))
            snapshot.acceptsInput = inputs.atIndex(i)?.booleanValue ?? false
            snapshot.actionCount = Int(counts.atIndex(i)?.int32Value ?? 0)
            snapshot.folderName = folderByShortcut[id] ?? ""
            result.append(snapshot)
        }
        return result
    }

    /// Shortcuts reports colors as 16-bit RGB triples.
    private static func colorHex(from descriptor: NSAppleEventDescriptor?) -> String {
        guard let descriptor else { return "" }
        var components: [Double] = []
        if descriptor.numberOfItems == 3 {
            for i in 1...3 { components.append(Double(descriptor.atIndex(i)?.int32Value ?? 0)) }
        } else if descriptor.data.count == 6 {
            let bytes = [UInt8](descriptor.data)
            for i in stride(from: 0, to: 6, by: 2) {
                components.append(Double(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])))
            }
        } else {
            return ""
        }
        let scaled = components.map { min(max($0 / 65535, 0), 1) }
        return TileColor(red: scaled[0], green: scaled[1], blue: scaled[2]).hex
    }

    private static func imageData(from descriptor: NSAppleEventDescriptor) -> Data? {
        if descriptor.data.count > 0 { return descriptor.data }
        if let coerced = descriptor.coerce(toDescriptorType: DescType(0x54494646 /* TIFF */)), coerced.data.count > 0 {
            return coerced.data
        }
        return nil
    }

    private static func describe(_ descriptor: NSAppleEventDescriptor) -> String? {
        if descriptor.descriptorType == typeNull { return nil }
        if descriptor.numberOfItems > 0 && descriptor.descriptorType == typeAEList {
            let parts = (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0).flatMap(describe) }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        if let text = descriptor.stringValue, !text.isEmpty { return text }
        if let url = descriptor.fileURLValue { return url.path }
        return nil
    }

    private static func quote(_ string: String) -> String {
        var escaped = string.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
#endif
