import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([ShortcutItem.self, LibraryFolder.self, Tag.self, SmartList.self])

    static let container: ModelContainer = {
        let cloud = ModelConfiguration("ShortLibrary", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloud]) { return container }
        let local = ModelConfiguration("ShortLibrary", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Could not open the ShortLibrary store: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}
