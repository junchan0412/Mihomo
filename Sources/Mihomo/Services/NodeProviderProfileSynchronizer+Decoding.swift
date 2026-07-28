import Foundation
import Yams

extension NodeProviderProfileSynchronizer {
    func nodeProviders(from profileContent: String, profileID: UUID) throws -> [NodeProvider] {
        let root = try rootMap(profileContent)
        let providers = root["proxy-providers"] as? YAMLMap ?? [:]
        return providers.compactMap { name, value in
            let map = value as? YAMLMap ?? [:]
            let type = string(map["type"], fallback: "http")
            let path = string(map["path"], fallback: "")
            let url = string(map["url"], fallback: "")
            let interval = int(map["interval"], fallback: 86_400)
            return NodeProvider(
                name: name,
                url: url,
                path: path.isEmpty ? nil : path,
                providerType: type,
                interval: interval,
                profileIDs: [profileID],
                sourceProfileID: profileID
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func rootMap(_ content: String) throws -> YAMLMap {
        let object = try Yams.load(yaml: content) ?? YAMLMap()
        guard let map = normalize(object) as? YAMLMap else {
            throw syncError("Profile YAML 顶层必须是映射。")
        }
        return map
    }

    private func normalize(_ value: Any) -> Any {
        if let map = value as? YAMLMap {
            return map.reduce(into: YAMLMap()) { $0[$1.key] = normalize($1.value) }
        }
        if let map = value as? [AnyHashable: Any] {
            return map.reduce(into: YAMLMap()) { $0[String(describing: $1.key)] = normalize($1.value) }
        }
        if let array = value as? [Any] { return array.map(normalize) }
        return value
    }

    private func string(_ value: Any?, fallback: String) -> String {
        guard let value else { return fallback }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    private func int(_ value: Any?, fallback: Int) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? String, let parsed = Int(value) { return parsed }
        return fallback
    }
}
