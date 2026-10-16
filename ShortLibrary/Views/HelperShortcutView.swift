#if !os(macOS)
import SwiftUI

/// Explains how iPhone, iPad, and Vision Pro feed the library: a helper shortcut that calls
/// ShortLibrary's own actions, since iOS offers no API to list a user's shortcuts.
struct HelperShortcutView: View {
    private var syncer = LibrarySyncController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(.tint)
                    Text("Sync from the Shortcuts app").font(.title2.weight(.bold))
                    Text("On iPhone, iPad, and Vision Pro, Shortcuts can't be read directly. A small helper shortcut named “\(HelperShortcut.name)” sends your library to ShortLibrary instead. Run it whenever you add or rename shortcuts, or use the Sync button here.")
                        .foregroundStyle(.secondary)
                }

                if let url = HelperShortcut.downloadURL {
                    Link(destination: url) {
                        Label("Get the Helper Shortcut", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    Task { await syncer.syncNow() }
                } label: {
                    Label("Run “\(HelperShortcut.name)”", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                GroupBox("Build it yourself") {
                    VStack(alignment: .leading, spacing: 10) {
                        step(1, "Add **Begin ShortLibrary Sync** (from ShortLibrary).")
                        step(2, "Add **Get My Shortcuts**.")
                        step(3, "Add **Repeat with Each** over the shortcuts. Inside the loop, add **Get Details of Shortcut** for Name, Identifier, Folder, Icon, Action Count, Creation Date, and Last Modified Date, then **Import Shortcut into ShortLibrary** with those values.")
                        step(4, "After the loop, add **Finish ShortLibrary Sync**.")
                        step(5, "Name the shortcut “\(HelperShortcut.name)” so the Sync button can find it.")
                    }
                    .padding(.vertical, 4)
                }

                if let date = syncer.lastSyncDate {
                    Text("Last synced \(date, format: .relative(presentation: .named))").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.18), in: Circle())
            Text(text).font(.callout)
        }
    }
}
#endif
