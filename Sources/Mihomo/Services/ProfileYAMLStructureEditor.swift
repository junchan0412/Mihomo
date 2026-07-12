import Foundation
import Yams

struct ProfileYAMLStructureEditor {
    private typealias YAMLMap = [String: Any]

    func snapshot(content: String) throws -> ProfileStructureSnapshot {
        let root = try rootMap(content)
        let groups = (root["proxy-groups"] as? [Any] ?? [])
            .compactMap { $0 as? YAMLMap }
            .compactMap(policyGroup(from:))
        let rules = (root["rules"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .enumerated()
            .map { index, rule in profileRule(from: rule, index: index + 1) }
        let proxyNames = (root["proxies"] as? [Any] ?? [])
            .compactMap { $0 as? YAMLMap }
            .compactMap { $0["name"] as? String }
        return ProfileStructureSnapshot(groups: groups, rules: rules, proxyNames: proxyNames)
    }

    func upsertGroup(content: String, originalName: String?, group: EditablePolicyGroup) throws -> String {
        var root = try rootMap(content)
        var groups = root["proxy-groups"] as? [Any] ?? []
        let map = groupMap(group)
        if let originalName,
           let index = groups.firstIndex(where: { (($0 as? YAMLMap)?["name"] as? String) == originalName }) {
            groups[index] = map
        } else if let index = groups.firstIndex(where: { (($0 as? YAMLMap)?["name"] as? String) == group.name }) {
            groups[index] = map
        } else {
            groups.append(map)
        }
        root["proxy-groups"] = groups
        return try dump(root)
    }

    func deleteGroup(content: String, name: String, replacement: String?, deleteRules: Bool) throws -> String {
        var root = try rootMap(content)
        var groups = root["proxy-groups"] as? [Any] ?? []
        groups.removeAll { (($0 as? YAMLMap)?["name"] as? String) == name }
        root["proxy-groups"] = groups

        var rules = ((root["rules"] as? [Any] ?? []).compactMap { $0 as? String }).map {
            profileRule(from: $0, index: 0)
        }
        let affected = rules.filter { $0.target == name }
        if affected.isEmpty == false {
            if deleteRules {
                rules.removeAll { $0.target == name }
            } else if let replacement, replacement.isEmpty == false {
                rules = rules.map { rule in
                    guard rule.target == name else { return rule }
                    var updated = rule
                    updated.target = replacement
                    return updated
                }
            } else {
                throw editorError("有 \(affected.count) 条规则正在使用策略组 \(name)，需要先选择替换目标或删除引用规则。")
            }
        }
        root["rules"] = rules.map(\.content)
        return try dump(root)
    }

    func upsertRule(content: String, originalIndex: Int?, rule: EditableProfileRule) throws -> String {
        var root = try rootMap(content)
        var rules = (root["rules"] as? [Any] ?? []).compactMap { $0 as? String }
        if let originalIndex, originalIndex > 0, originalIndex <= rules.count {
            rules[originalIndex - 1] = rule.content
        } else {
            rules.append(rule.content)
        }
        root["rules"] = rules
        return try dump(root)
    }

    func deleteRule(content: String, index: Int) throws -> String {
        var root = try rootMap(content)
        var rules = (root["rules"] as? [Any] ?? []).compactMap { $0 as? String }
        guard index > 0, index <= rules.count else { return content }
        rules.remove(at: index - 1)
        root["rules"] = rules
        return try dump(root)
    }

    private func rootMap(_ content: String) throws -> YAMLMap {
        let object = try Yams.load(yaml: content) ?? YAMLMap()
        guard let map = normalizeYAMLValue(object) as? YAMLMap else {
            throw editorError("Profile YAML 顶层必须是映射。")
        }
        return map
    }

    private func policyGroup(from map: YAMLMap) -> EditablePolicyGroup? {
        guard let name = map["name"] as? String else { return nil }
        return EditablePolicyGroup(
            name: name,
            type: map["type"] as? String ?? "select",
            proxies: (map["proxies"] as? [Any] ?? []).compactMap { $0 as? String },
            uses: (map["use"] as? [Any] ?? []).compactMap { $0 as? String },
            hidden: map["hidden"] as? Bool ?? false,
            icon: map["icon"] as? String
        )
    }

    private func groupMap(_ group: EditablePolicyGroup) -> YAMLMap {
        var map: YAMLMap = [
            "name": group.name,
            "type": group.type
        ]
        let proxies = group.proxies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let uses = group.uses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        if proxies.isEmpty == false {
            map["proxies"] = proxies
        }
        if uses.isEmpty == false {
            map["use"] = uses
        }
        if group.hidden {
            map["hidden"] = true
        }
        if let icon = group.icon?.trimmingCharacters(in: .whitespacesAndNewlines), icon.isEmpty == false {
            map["icon"] = icon
        }
        return map
    }

    private func profileRule(from content: String, index: Int) -> EditableProfileRule {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 3 {
            return EditableProfileRule(
                index: index,
                type: parts[0],
                payload: parts[1],
                target: parts[2],
                options: Array(parts.dropFirst(3))
            )
        }
        if parts.count == 2 {
            return EditableProfileRule(index: index, type: parts[0], payload: "", target: parts[1], options: [])
        }
        return EditableProfileRule(index: index, type: parts.first ?? "MATCH", payload: "", target: "DIRECT", options: [])
    }

    private func dump(_ root: YAMLMap) throws -> String {
        try Yams.dump(object: root, sortKeys: false)
    }

    private func normalizeYAMLValue(_ value: Any) -> Any {
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

    private func editorError(_ message: String) -> NSError {
        NSError(domain: "ProfileYAMLStructureEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
