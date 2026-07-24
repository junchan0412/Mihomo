import Foundation
import Yams

struct NodeProviderProfileSynchronizer {
    private typealias YAMLMap = [String: Any]

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
                profileIDs: [profileID]
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func synchronizing(_ nodeProviders: [NodeProvider], into profileContent: String) throws -> String {
        var root = try rootMap(profileContent)
        var current = root["proxy-providers"] as? YAMLMap ?? [:]
        for provider in nodeProviders where provider.enabled {
            let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { continue }
            var definition = current[name] as? YAMLMap ?? [:]
            definition["type"] = provider.providerType
            definition["path"] = provider.path
            if provider.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                definition.removeValue(forKey: "url")
            } else {
                definition["url"] = provider.url
            }
            if provider.interval > 0 {
                definition["interval"] = provider.interval
            } else {
                definition.removeValue(forKey: "interval")
            }
            current[name] = definition
        }
        if current.isEmpty == false {
            root["proxy-providers"] = current
        }
        return try YAMLText.dump(root)
    }

    func preservingExistingProviders(from previousContent: String, in refreshedContent: String) throws -> String {
        let previous = try rootMap(previousContent)
        let existing = previous["proxy-providers"] as? YAMLMap ?? [:]
        guard existing.isEmpty == false else { return refreshedContent }

        var refreshed = try rootMap(refreshedContent)
        var incoming = refreshed["proxy-providers"] as? YAMLMap ?? [:]
        for (name, definition) in existing where incoming[name] == nil {
            incoming[name] = definition
        }
        refreshed["proxy-providers"] = incoming
        return try YAMLText.dump(refreshed)
    }

    private func rootMap(_ content: String) throws -> YAMLMap {
        let object = try Yams.load(yaml: content) ?? YAMLMap()
        guard let map = normalize(object) as? YAMLMap else {
            throw NSError(domain: "Mihomo.NodeProviderProfile", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Profile YAML 顶层必须是映射。"
            ])
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
