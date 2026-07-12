import Foundation

enum RuleEditorPresentation: Identifiable {
    case add
    case edit(Int)

    var id: String {
        switch self {
        case .add: return "add"
        case let .edit(index): return "edit-\(index)"
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

struct RuleTableEntry: Identifiable, Hashable {
    var rule: RuleItem
    var type: String
    var value: String
    var policy: String
    var options: [String]

    var id: String { rule.id }
    var optionsText: String { options.joined(separator: ", ") }
    var displayValue: String {
        guard !options.isEmpty else { return value }
        let base = value.isEmpty ? "-" : value
        return "\(base) (\(optionsText))"
    }
    var note: String { "" }
    var searchText: String {
        [rule.content, type, value, policy, optionsText, "\(rule.index)", "\(rule.hitCount)"].joined(separator: " ")
    }

    init(rule: RuleItem) {
        self.rule = rule
        let parts = rule.content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 3 {
            type = parts[0]
            value = parts[1]
            policy = parts[2]
            options = Array(parts.dropFirst(3))
        } else if parts.count == 2 {
            type = parts[0]
            value = ""
            policy = parts[1]
            options = []
        } else {
            type = parts.first ?? "MATCH"
            value = ""
            policy = "DIRECT"
            options = []
        }
    }
}
