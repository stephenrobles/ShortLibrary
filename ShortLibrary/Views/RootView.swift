import SwiftData
import SwiftUI

struct RootView: View {
    @State private var navigation = LibraryNavigation.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    private var runner = ShortcutRunner.shared
    private var syncer = LibrarySyncController.shared

    var body: some View {
        splitView
            .onOpenURL { url in ShortcutURLs.handleCallback(url, runner: runner) }
            .overlay(alignment: .bottom) { OutcomeBanner() }
            .task {
                #if os(macOS)
                await syncer.migrateStoredIconsIfNeeded()
                await syncer.trimStoredGlyphsIfNeeded()
                syncer.fixGradientOrientationIfNeeded()
                if syncOnLaunch { await syncer.syncNow() } else { syncer.backfillMissingIcons() }
                #endif
            }
            .alert("Sync Failed", isPresented: Binding(get: { syncer.lastError != nil }, set: { if !$0 { syncer.lastError = nil } })) {
                Button("OK") { syncer.lastError = nil }
            } message: {
                Text(syncer.lastError ?? "")
            }
            #if os(macOS)
            .frame(minWidth: 1000, minHeight: 560)
            #endif
    }

    @ViewBuilder
    private var splitView: some View {
        @Bindable var navigation = navigation
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $navigation.section)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 360)
        } detail: {
            ShortcutCollectionView(section: navigation.section ?? .all, selectedShortcut: $navigation.selectedShortcut)
                // Explicit column sizing keeps AppKit from re-deriving minimums from content mid-layout,
                // which is what the SplitViewChildController/_postWindowNeedsUpdateConstraints abort is.
                .navigationSplitViewColumnWidth(min: 440, ideal: 820)
                .inspector(isPresented: $navigation.showInspector) {
                    InspectorPane(item: navigation.selectedShortcut)
                        .inspectorColumnWidth(min: 320, ideal: 360, max: 520)
                }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        #else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $navigation.section)
        } content: {
            ShortcutCollectionView(section: navigation.section ?? .all, selectedShortcut: $navigation.selectedShortcut)
        } detail: {
            if let item = navigation.selectedShortcut {
                ShortcutDetailView(item: item)
            } else {
                ContentUnavailableView("No Shortcut Selected", systemImage: "square.grid.2x2",
                                       description: Text("Pick a shortcut to see its details, tags, and notes."))
            }
        }
        #endif
    }
}

#if os(macOS)
/// Inspector content with a layout footprint that doesn't change when the selection does: the same
/// frame and the same toolbar items whether or not a shortcut is selected.
struct InspectorPane: View {
    let item: ShortcutItem?

    var body: some View {
        ZStack {
            if let item {
                ShortcutDetailView(item: item)
            } else {
                ScrollView {
                    ContentUnavailableView("No Shortcut Selected", systemImage: "square.grid.2x2",
                                           description: Text("Pick a shortcut to see its details, tags, and notes."))
                        .padding(.top, 80)
                }
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
#endif

/// Transient banner showing the result of the most recent run.
struct OutcomeBanner: View {
    private var runner = ShortcutRunner.shared
    @State private var visibleID: UUID?

    var body: some View {
        Group {
            if let outcome = runner.latestOutcome, outcome.id == visibleID {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: outcome.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(outcome.isError ? Color.orange : Color.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.isError ? "\(outcome.shortcutName) failed" : "Ran \(outcome.shortcutName)")
                            .font(.headline)
                        if let text = outcome.error ?? outcome.output, !text.isEmpty {
                            Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { visibleID = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 520)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: visibleID)
        .onChange(of: runner.latestOutcome?.id) { _, newID in
            visibleID = newID
            guard let newID else { return }
            Task {
                try? await Task.sleep(for: .seconds(6))
                if visibleID == newID { visibleID = nil }
            }
        }
    }
}

#if os(macOS)
struct SettingsView: View {
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    @AppStorage("doubleClickRuns") private var doubleClickRuns = true
    @AppStorage("includeSubfolders") private var includeSubfolders = true

    var body: some View {
        Form {
            Toggle("Sync with Shortcuts when ShortLibrary opens", isOn: $syncOnLaunch)
            Toggle("Double-click a shortcut to run it", isOn: $doubleClickRuns)
            Toggle("Folders include shortcuts from their subfolders", isOn: $includeSubfolders)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { AppUpdater.shared.automaticallyChecksForUpdates },
                set: { AppUpdater.shared.automaticallyChecksForUpdates = $0 }))
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}
#endif
