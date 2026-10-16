import Foundation
import SwiftData

@Model
final class SmartList {
    var uuid: String = UUID().uuidString
    var name: String = ""
    var symbolName: String = "sparkles"
    var colorHex: String = "#AF52DE"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    /// JSON-encoded `SmartRuleSet`.
    var rulesData: Data = Data()

    init(name: String, rules: SmartRuleSet = SmartRuleSet()) {
        self.name = name
        self.rules = rules
    }

    var rules: SmartRuleSet {
        get { (try? JSONDecoder().decode(SmartRuleSet.self, from: rulesData)) ?? SmartRuleSet() }
        set { rulesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
