import Foundation

extension MihomoControllerClient {
    static func parseProxyGroups(from json: [String: Any]) -> [ProxyGroup] {
        guard let proxies = json["proxies"] as? [String: [String: Any]] else { return [] }
        return proxies.compactMap { name, detail in
            guard let allNames = detail["all"] as? [String], allNames.isEmpty == false else { return nil }
            let nodes = allNames.map { proxyName in
                let proxy = proxies[proxyName]
                let history = proxy?["history"] as? [[String: Any]]
                return ProxyNode(
                    name: proxyName,
                    type: proxy?["type"] as? String ?? "proxy",
                    delay: history?.last?["delay"] as? Int,
                    available: proxy?["alive"] as? Bool
                )
            }
            return ProxyGroup(
                name: name,
                type: detail["type"] as? String ?? "select",
                now: detail["now"] as? String ?? "",
                all: nodes,
                icon: detail["icon"] as? String,
                hidden: detail["hidden"] as? Bool ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.name == "GLOBAL" { return true }
            if rhs.name == "GLOBAL" { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func parseConnections(from json: [String: Any]) -> ([ConnectionItem], Int64, Int64) {
        let uploadTotal = number(json["uploadTotal"])
        let downloadTotal = number(json["downloadTotal"])
        guard let rows = json["connections"] as? [[String: Any]] else {
            return ([], uploadTotal, downloadTotal)
        }

        let dateParser = ConnectionDateParser()
        let items = rows.enumerated().map { index, row -> ConnectionItem in
            let metadata = row["metadata"] as? [String: Any] ?? [:]
            let chains = row["chains"] as? [String] ?? []
            let ruleType = row["rule"] as? String ?? ""
            let rulePayload = row["rulePayload"] as? String ?? ""
            let rule = [ruleType, rulePayload].filter { $0.isEmpty == false }.joined(separator: " ")
            return ConnectionItem(
                id: row["id"] as? String ?? fallbackConnectionID(metadata: metadata, chains: chains, row: row, index: index),
                host: (metadata["host"] as? String)
                    ?? (metadata["sniffHost"] as? String)
                    ?? (metadata["destinationIP"] as? String)
                    ?? (metadata["remoteDestination"] as? String)
                    ?? "-",
                process: ((metadata["type"] as? String) == "Inner" ? "mihomo" : nil)
                    ?? (metadata["process"] as? String)
                    ?? (metadata["processPath"] as? String)
                    ?? "-",
                processPath: metadata["processPath"] as? String ?? "",
                network: metadata["network"] as? String ?? "-",
                metadataType: metadata["type"] as? String ?? "",
                rule: rule.isEmpty ? "-" : rule,
                ruleType: ruleType,
                rulePayload: rulePayload,
                chain: chains.joined(separator: " -> "),
                sourceIP: stringValue(metadata["sourceIP"]),
                sourcePort: stringValue(metadata["sourcePort"]),
                destinationIP: stringValue(metadata["destinationIP"]),
                destinationPort: stringValue(metadata["destinationPort"]),
                remoteDestination: stringValue(metadata["remoteDestination"]),
                upload: number(row["upload"]),
                download: number(row["download"]),
                start: dateParser.date(from: row["start"])
            )
        }
        return (items, uploadTotal, downloadTotal)
    }

    static func parseProviderItems(from json: [String: Any], kind: String) -> [ProviderItem] {
        guard let providers = json["providers"] as? [String: [String: Any]] else { return [] }
        return providers.map { name, detail in
            let count = providerEntryCount(kind: kind, detail: detail)
            let pieces = [
                detail["type"].map { "type: \($0)" },
                detail["vehicleType"].map { "vehicle: \($0)" },
                detail["updatedAt"].map { "updated: \($0)" },
                count > 0 ? "items: \(count)" : nil
            ].compactMap { $0 }
            return ProviderItem(
                kind: kind,
                name: name,
                detail: pieces.isEmpty ? "-" : pieces.joined(separator: " · "),
                providerType: detail["type"].map { "\($0)" } ?? "",
                ruleCount: count,
                memberNames: providerMemberNames(kind: kind, detail: detail)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func number(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    /// Older mihomo builds may omit `id`. Keep this stable across polling reorderings.
    private static func fallbackConnectionID(
        metadata: [String: Any],
        chains: [String],
        row: [String: Any],
        index: Int
    ) -> String {
        let fields = [
            stringValue(metadata["type"]), stringValue(metadata["network"]),
            stringValue(metadata["sourceIP"]), stringValue(metadata["sourcePort"]),
            stringValue(metadata["destinationIP"]), stringValue(metadata["destinationPort"]),
            stringValue(metadata["host"]), stringValue(metadata["remoteDestination"]),
            stringValue(row["start"]), chains.joined(separator: "|")
        ]
        let key = fields.joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return "connection-unknown-\(index)" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "connection-" + String(hash, radix: 16)
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        case let value as Int: return String(value)
        case let value as Int64: return String(value)
        case let value as Double: return value.rounded() == value ? String(Int64(value)) : String(value)
        default: return ""
        }
    }

    private static func providerEntryCount(kind: String, detail: [String: Any]) -> Int {
        if kind == "Proxy" {
            return (detail["proxies"] as? [Any])?.count ?? 0
        }
        return (detail["rules"] as? [Any])?.count ?? detail["ruleCount"] as? Int ?? 0
    }

    private static func providerMemberNames(kind: String, detail: [String: Any]) -> [String] {
        let entries = kind == "Proxy"
            ? detail["proxies"] as? [Any] ?? []
            : detail["rules"] as? [Any] ?? []
        return entries.compactMap { entry in
            if let name = entry as? String { return name }
            guard let map = entry as? [String: Any] else { return nil }
            return (map["name"] as? String)
                ?? (map["payload"] as? String)
                ?? (map["rule"] as? String)
        }
    }

    private struct ConnectionDateParser {
        private let standardFormatter = ISO8601DateFormatter()
        private let fractionalFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func date(from value: Any?) -> Date? {
            if let value = value as? Date { return value }
            if let value = value as? NSNumber {
                let seconds = value.doubleValue > 10_000_000_000 ? value.doubleValue / 1000 : value.doubleValue
                return Date(timeIntervalSince1970: seconds)
            }
            guard let value = value as? String, value.isEmpty == false else { return nil }
            return standardFormatter.date(from: value) ?? fractionalFormatter.date(from: value)
        }
    }
}
