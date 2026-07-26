import Foundation
import Yams

enum ConfigRevisionDiff {
    static func changedFields(
        currentContent: String,
        revisionContent: String,
        kind: ConfigRevisionKind
    ) -> [String] {
        switch kind {
        case .profile:
            return changedProfileFields(currentContent: currentContent, revisionContent: revisionContent)
        case .overrides:
            return changedOverrideFields(currentContent: currentContent, revisionContent: revisionContent)
        }
    }

    private static func changedProfileFields(currentContent: String, revisionContent: String) -> [String] {
        let current = topLevelFields(in: currentContent)
        let revision = topLevelFields(in: revisionContent)
        if current.isEmpty, revision.isEmpty { return currentContent == revisionContent ? [] : ["内容"] }
        return Array(Set(current.keys).union(revision.keys))
            .filter { current[$0] != revision[$0] }
            .sorted()
    }

    private static func changedOverrideFields(currentContent: String, revisionContent: String) -> [String] {
        guard let current = decodeFragments(currentContent), let revision = decodeFragments(revisionContent) else {
            return currentContent == revisionContent ? [] : ["覆写内容"]
        }
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let revisionByID = Dictionary(uniqueKeysWithValues: revision.map { ($0.id, $0) })
        let identifiers = Set(currentByID.keys).union(revisionByID.keys)
        return identifiers.flatMap { identifier -> [String] in
            switch (currentByID[identifier], revisionByID[identifier]) {
            case let (.some(fragment), .none): return ["新增：\(fragment.name)"]
            case let (.none, .some(fragment)): return ["删除：\(fragment.name)"]
            case let (.some(current), .some(revision)): return changedFields(for: current, comparedTo: revision)
            case (.none, .none): return []
            }
        }
        .sorted()
    }

    private static func changedFields(for current: ConfigFragment, comparedTo revision: ConfigFragment) -> [String] {
        let prefix = current.name
        var fields: [String] = []
        if current.name != revision.name { fields.append("\(prefix).名称") }
        if current.kind != revision.kind { fields.append("\(prefix).类型") }
        if current.enabled != revision.enabled { fields.append("\(prefix).状态") }
        if current.content != revision.content { fields.append("\(prefix).内容") }
        if current.appliesGlobally != revision.appliesGlobally || Set(current.profileIDs) != Set(revision.profileIDs) { fields.append("\(prefix).作用范围") }
        if current.source != revision.source || current.location != revision.location { fields.append("\(prefix).来源") }
        return fields
    }

    private static func topLevelFields(in content: String) -> [String: String] {
        guard let loaded = try? Yams.load(yaml: content), let fields = loaded as? [String: Any] else { return [:] }
        return fields.reduce(into: [:]) { result, entry in result[entry.key] = String(describing: entry.value) }
    }

    private static func decodeFragments(_ content: String) -> [ConfigFragment]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ConfigFragment].self, from: Data(content.utf8))
    }
}
