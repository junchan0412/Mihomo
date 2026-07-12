import Foundation
import Yams

extension ProfileQualityAnalyzer {
    func yamlRoot(_ content: String) -> YAMLMap? {
        guard let object = try? Yams.load(yaml: content) else { return nil }
        return normalizeYAMLValue(object) as? YAMLMap
    }

    func normalizeYAMLValue(_ value: Any) -> Any {
        if let map = value as? YAMLMap {
            return map.reduce(into: YAMLMap()) { result, pair in
                result[pair.key] = normalizeYAMLValue(pair.value)
            }
        }
        if let map = value as? [AnyHashable: Any] {
            return map.reduce(into: YAMLMap()) { result, pair in
                result[String(describing: pair.key)] = normalizeYAMLValue(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }

    func stringValue(_ value: Any?) -> String {
        guard let value else { return "-" }
        return "\(value)"
    }

    func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        return false
    }

    func arrayCount(_ value: Any?) -> Int {
        (value as? [Any])?.count ?? 0
    }

    func topLevelKeys(in fragments: [ConfigFragment]) -> Set<String> {
        fragments.reduce(into: Set<String>()) { result, fragment in
            guard let root = yamlRoot(fragment.content) else { return }
            result.formUnion(root.keys)
        }
    }

    func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    func valuesDiffer(_ lhs: Any?, _ rhs: Any?) -> Bool {
        fieldValueSummary(lhs) != fieldValueSummary(rhs)
    }

    func fieldValueSummary(_ value: Any?) -> String {
        guard let value else { return "未写入" }
        if let map = value as? YAMLMap {
            return "\(map.count) 个字段"
        }
        if let array = value as? [Any] {
            return "\(array.count) 项"
        }
        return "\(value)"
    }
}
