import Darwin
import Foundation

extension ProfileQualityAnalyzer {
    func validatePort(_ value: Any?, title: String) -> [ProfileQualityIssue] {
        guard let value else {
            return [.init(severity: .error, title: "\(title) 缺失", detail: "最终 runtime config 缺少 \(title)。")]
        }
        let port: Int?
        if let intValue = value as? Int {
            port = intValue
        } else {
            port = Int("\(value)")
        }
        guard let port, (1...65_535).contains(port) else {
            return [.init(severity: .error, title: "\(title) 无效", detail: "\(title) 应为 1...65535，当前为 \(value)。")]
        }
        return []
    }

    func lineList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    func isValidSnifferPortToken(_ token: String) -> Bool {
        if let port = Int(token) {
            return (1...65_535).contains(port)
        }
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1])
        else { return false }
        return (1...65_535).contains(start) && (1...65_535).contains(end) && start <= end
    }

    func isValidPortRulePayload(_ payload: String) -> Bool {
        isValidSnifferPortToken(payload.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func isValidASNRulePayload(_ payload: String) -> Bool {
        guard let asn = UInt64(payload.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return (1...4_294_967_295).contains(asn)
    }

    func isValidCIDRAddress(_ address: String, type: String) -> Bool {
        switch type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "IP-CIDR":
            var ipv4 = in_addr()
            return address.withCString { inet_pton(AF_INET, $0, &ipv4) == 1 }
        case "IP-CIDR6":
            var ipv6 = in6_addr()
            return address.withCString { inet_pton(AF_INET6, $0, &ipv6) == 1 }
        default:
            return false
        }
    }

    func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [Any] {
            return values.map { "\($0)" }
        }
        if let value {
            return ["\(value)"]
        }
        return []
    }

    func isPlausibleDNSResolver(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }

        if trimmed == "system" || trimmed.hasPrefix("rcode://") {
            return true
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            return ["https", "tls", "quic", "dhcp"].contains(scheme)
        }
        if trimmed.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d{1,5})?(#.+)?$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[0-9A-Fa-f:]+(#.+)?$"#, options: .regularExpression) != nil,
           trimmed.contains(":") {
            return true
        }
        return false
    }

    func isSupportedTunStack(_ stack: String) -> Bool {
        ["system", "gvisor", "mixed"].contains(stack.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    func isValidSnifferDomainToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.contains("/") == false,
              URL(string: trimmed)?.scheme == nil
        else { return false }
        return true
    }

    func isValidSnifferAddressToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        let address = String(parts[0])
        let isIPv6 = address.contains(":")
        let type = isIPv6 ? "IP-CIDR6" : "IP-CIDR"
        guard isValidCIDRAddress(address, type: type) else { return false }
        guard parts.count == 2 else { return true }

        let maximumPrefix = isIPv6 ? 128 : 32
        return Int(parts[1]).map { (0...maximumPrefix).contains($0) } == true
    }

    func isSupportedRuleType(_ type: String) -> Bool {
        [
            "DOMAIN",
            "DOMAIN-SUFFIX",
            "DOMAIN-KEYWORD",
            "GEOIP",
            "GEOSITE",
            "IP-CIDR",
            "IP-CIDR6",
            "IP-ASN",
            "SRC-IP-CIDR",
            "SRC-IP-CIDR6",
            "SRC-PORT",
            "DST-PORT",
            "PROCESS-NAME",
            "PROCESS-NAME-REGEX",
            "PROCESS-PATH",
            "PROCESS-PATH-REGEX",
            "RULE-SET",
            "MATCH",
            "NETWORK",
            "IN-TYPE",
            "IN-USER",
            "IN-NAME",
            "UID",
            "DSCP",
            "AND",
            "OR",
            "NOT",
            "SUB-RULE"
        ].contains(type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    func isPlausibleDomainRulePayload(_ payload: String) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.contains("/") == false,
              URL(string: trimmed)?.scheme == nil
        else { return false }
        return true
    }

    func isPlausibleGeoIPPayload(_ payload: String) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.contains("/") == false,
              URL(string: trimmed)?.scheme == nil
        else { return false }
        let uppercased = trimmed.uppercased()
        return uppercased == "LAN" || uppercased == "PRIVATE" || uppercased.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil
    }

    func isPlausibleProcessNamePayload(_ payload: String) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              trimmed.contains("/") == false
        else { return false }
        return true
    }

    func isPlausibleProcessPathPayload(_ payload: String) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else { return false }
        return trimmed.hasPrefix("/")
    }
}
