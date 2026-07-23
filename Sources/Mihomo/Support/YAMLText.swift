import Foundation
import Yams

enum YAMLText {
    /// Prefer human-readable Unicode when dumping maps that users edit.
    static func dump(_ object: Any, indent: Int = 2) throws -> String {
        try Yams.dump(
            object: object,
            indent: indent,
            width: -1,
            allowUnicode: true,
            lineBreak: .ln,
            explicitStart: false,
            explicitEnd: false,
            version: nil,
            sortKeys: false
        )
    }

    static func loadMap(_ content: String) throws -> [String: Any] {
        let object = try Yams.load(yaml: content) ?? [String: Any]()
        guard let map = object as? [String: Any] else {
            throw NSError(
                domain: "YAMLText",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "YAML 顶层必须是映射。"]
            )
        }
        return map
    }
}

enum RuleMatchKey {
    static func normalizeType(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let upper = trimmed.uppercased()
        let compact = upper.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        let aliases: [String: String] = [
            "DOMAIN": "DOMAIN",
            "DOMAINSUFFIX": "DOMAIN-SUFFIX",
            "DOMAINKEYWORD": "DOMAIN-KEYWORD",
            "DOMAINREGEX": "DOMAIN-REGEX",
            "GEOSITE": "GEOSITE",
            "IPCIDR": "IP-CIDR",
            "IPCIDR6": "IP-CIDR6",
            "IPSUFFIX": "IP-SUFFIX",
            "IPASN": "IP-ASN",
            "GEOIP": "GEOIP",
            "SRCIPCIDR": "SRC-IP-CIDR",
            "SRCIPORT": "SRC-PORT",
            "SRCPORT": "SRC-PORT",
            "DSTPORT": "DST-PORT",
            "INPORT": "IN-PORT",
            "PROCESSNAME": "PROCESS-NAME",
            "PROCESSPATH": "PROCESS-PATH",
            "PROCESSNAME_REGEX": "PROCESS-NAME-REGEX",
            "PROCESSPATHREGEX": "PROCESS-PATH-REGEX",
            "NETWORK": "NETWORK",
            "UID": "UID",
            "INUSER": "IN-USER",
            "INNAME": "IN-NAME",
            "SUBRULES": "SUB-RULE",
            "SUBRULE": "SUB-RULE",
            "RULESET": "RULE-SET",
            "AND": "AND",
            "OR": "OR",
            "NOT": "NOT",
            "MATCH": "MATCH"
        ]
        if let mapped = aliases[compact] {
            return mapped
        }
        return upper
    }

    static func make(type: String, payload: String) -> String {
        let normalizedType = normalizeType(type)
        let normalizedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedType.isEmpty == false else { return "" }
        if normalizedType == "MATCH" {
            return "MATCH"
        }
        return normalizedPayload.isEmpty ? normalizedType : "\(normalizedType),\(normalizedPayload)"
    }

    static func make(content: String) -> String {
        let parts = content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.isEmpty == false else { return "" }
        if normalizeType(parts[0]) == "MATCH" {
            return "MATCH"
        }
        if parts.count >= 2 {
            return make(type: parts[0], payload: parts[1])
        }
        return normalizeType(parts[0])
    }

    static func make(from connection: ConnectionItem) -> String {
        if connection.ruleType.isEmpty == false {
            return make(type: connection.ruleType, payload: connection.rulePayload)
        }
        return make(content: connection.rule)
    }
}
