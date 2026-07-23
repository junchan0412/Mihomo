import Foundation
import SwiftUI

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

extension RuleTableEntry {
    var typeCategory: RuleTypeCategory {
        RuleTypeCategory.classify(type)
    }

    var typeBadgeColor: Color {
        typeCategory.color
    }

    var typeSystemImage: String {
        typeCategory.systemImage
    }

    var hitDisplay: String {
        rule.hitCount > 0 ? "\(rule.hitCount)" : "-"
    }
}

enum RuleTypeCategory: String, CaseIterable, Identifiable {
    case domain
    case ip
    case geo
    case process
    case set
    case logic
    case match
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .domain: return "域名"
        case .ip: return "IP"
        case .geo: return "地理"
        case .process: return "进程"
        case .set: return "集合"
        case .logic: return "逻辑"
        case .match: return "兜底"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .domain: return "globe"
        case .ip: return "network"
        case .geo: return "map"
        case .process: return "app.badge"
        case .set: return "square.stack.3d.up"
        case .logic: return "function"
        case .match: return "flag.checkered"
        case .other: return "list.bullet"
        }
    }

    var color: Color {
        switch self {
        case .domain: return .blue
        case .ip: return .purple
        case .geo: return .teal
        case .process: return .orange
        case .set: return .indigo
        case .logic: return .pink
        case .match: return .red
        case .other: return .secondary
        }
    }

    static func classify(_ type: String) -> RuleTypeCategory {
        switch RuleMatchKey.normalizeType(type) {
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX":
            return .domain
        case "IP-CIDR", "IP-CIDR6", "IP-SUFFIX", "IP-ASN", "SRC-IP-CIDR", "SRC-PORT", "DST-PORT", "IN-PORT":
            return .ip
        case "GEOIP", "GEOSITE":
            return .geo
        case "PROCESS-NAME", "PROCESS-PATH", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX", "UID", "IN-USER", "IN-NAME":
            return .process
        case "RULE-SET", "SUB-RULE":
            return .set
        case "AND", "OR", "NOT", "NETWORK":
            return .logic
        case "MATCH":
            return .match
        default:
            return .other
        }
    }
}
