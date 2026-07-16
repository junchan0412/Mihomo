import Foundation
import Yams

struct ProfileSettingsSynchronizer {
    private typealias YAMLMap = [String: Any]

    func applyingProfile(_ content: String, to settings: AppSettings) throws -> AppSettings {
        let root = try rootMap(content)
        var updated = settings

        if let value = intValue(root["mixed-port"]) { updated.mixedPort = value }
        if let value = intValue(root["socks-port"]) { updated.socksPort = value }
        if let value = boolValue(root["allow-lan"]) { updated.allowLAN = value }
        if let value = root["log-level"] as? String { updated.logLevel = value }

        if let tun = root["tun"] as? YAMLMap,
           let enabled = boolValue(tun["enable"]) {
            updated.tunEnabled = enabled
        }

        if let dns = root["dns"] as? YAMLMap {
            if let enabled = boolValue(dns["enable"]) { updated.dnsEnabled = enabled }
            if let mode = dns["enhanced-mode"] as? String { updated.dnsEnhancedMode = mode }
            if dns["nameserver"] != nil { updated.dnsNameservers = stringList(dns["nameserver"]) }
            if dns["fallback"] != nil { updated.dnsFallbacks = stringList(dns["fallback"]) }
        }

        if let sniffer = root["sniffer"] as? YAMLMap {
            updated.snifferManagedByApp = true
            if let enabled = boolValue(sniffer["enable"]) { updated.snifferEnabled = enabled }
            if let value = boolValue(sniffer["parse-pure-ip"]) { updated.snifferParsePureIP = value }
            if let value = boolValue(sniffer["force-dns-mapping"]) { updated.snifferForceDNSMapping = value }
            if let value = boolValue(sniffer["override-destination"]) { updated.snifferOverrideDestination = value }
            if sniffer["force-domain"] != nil { updated.snifferForceDomains = lineText(sniffer["force-domain"]) }
            if sniffer["skip-domain"] != nil { updated.snifferSkipDomains = lineText(sniffer["skip-domain"]) }
            if sniffer["skip-dst-address"] != nil { updated.snifferSkipDestinationAddresses = lineText(sniffer["skip-dst-address"]) }
            if sniffer["skip-src-address"] != nil { updated.snifferSkipSourceAddresses = lineText(sniffer["skip-src-address"]) }

            if let sniff = sniffer["sniff"] as? YAMLMap {
                if let http = protocolMap("HTTP", in: sniff) {
                    if http["ports"] != nil { updated.snifferHTTPPorts = portText(http["ports"]) }
                    if let value = boolValue(http["override-destination"]) {
                        updated.snifferOverrideDestination = value
                    }
                }
                if let tls = protocolMap("TLS", in: sniff), tls["ports"] != nil {
                    updated.snifferTLSPorts = portText(tls["ports"])
                }
                if let quic = protocolMap("QUIC", in: sniff), quic["ports"] != nil {
                    updated.snifferQUICPorts = portText(quic["ports"])
                }
            }
        }

        return updated
    }

    func syncingAppChanges(
        from previous: AppSettings,
        to updated: AppSettings,
        in content: String
    ) throws -> String {
        let old = LinkedSettings(previous)
        let new = LinkedSettings(updated)
        guard old != new else { return content }

        var root = try rootMap(content)
        if old.mixedPort != new.mixedPort { root["mixed-port"] = new.mixedPort }
        if old.socksPort != new.socksPort {
            if new.socksPort > 0 { root["socks-port"] = new.socksPort }
            else { root.removeValue(forKey: "socks-port") }
        }
        if old.allowLAN != new.allowLAN { root["allow-lan"] = new.allowLAN }
        if old.logLevel != new.logLevel { root["log-level"] = new.logLevel }

        if old.tunEnabled != new.tunEnabled {
            var tun = root["tun"] as? YAMLMap ?? [:]
            tun["enable"] = new.tunEnabled
            if new.tunEnabled {
                if tun["stack"] == nil { tun["stack"] = "mixed" }
                if tun["auto-route"] == nil { tun["auto-route"] = true }
                if tun["auto-detect-interface"] == nil { tun["auto-detect-interface"] = true }
                if tun["dns-hijack"] == nil { tun["dns-hijack"] = ["any:53"] }
                var dns = root["dns"] as? YAMLMap ?? [:]
                dns["enable"] = true
                if dns["enhanced-mode"] == nil { dns["enhanced-mode"] = "fake-ip" }
                root["dns"] = dns
            }
            root["tun"] = tun
        }

        if old.dns != new.dns {
            var dns = root["dns"] as? YAMLMap ?? [:]
            if old.dns.enabled != new.dns.enabled { dns["enable"] = new.dns.enabled || new.tunEnabled }
            if old.dns.enhancedMode != new.dns.enhancedMode { dns["enhanced-mode"] = new.dns.enhancedMode }
            if old.dns.nameservers != new.dns.nameservers {
                dns["nameserver"] = new.dns.nameservers.isEmpty ? ["system"] : new.dns.nameservers
            }
            if old.dns.fallbacks != new.dns.fallbacks {
                if new.dns.fallbacks.isEmpty { dns.removeValue(forKey: "fallback") }
                else { dns["fallback"] = new.dns.fallbacks }
            }
            if dns["enable"] == nil { dns["enable"] = true }
            root["dns"] = dns
        }

        if old.sniffer != new.sniffer {
            root["sniffer"] = synchronizedSniffer(
                existing: root["sniffer"] as? YAMLMap ?? [:],
                previous: old.sniffer,
                updated: new.sniffer
            )
        }

        return try Yams.dump(object: root, sortKeys: false)
    }

    private func synchronizedSniffer(
        existing: YAMLMap,
        previous: SnifferSettings,
        updated: SnifferSettings
    ) -> YAMLMap {
        var result = existing
        if previous.enabled != updated.enabled { result["enable"] = updated.enabled }
        if previous.parsePureIP != updated.parsePureIP { result["parse-pure-ip"] = updated.parsePureIP }
        if previous.forceDNSMapping != updated.forceDNSMapping { result["force-dns-mapping"] = updated.forceDNSMapping }
        if previous.overrideDestination != updated.overrideDestination {
            result["override-destination"] = updated.overrideDestination
        }
        updateList(&result, key: "force-domain", old: previous.forceDomains, new: updated.forceDomains)
        updateList(&result, key: "skip-domain", old: previous.skipDomains, new: updated.skipDomains)
        updateList(&result, key: "skip-dst-address", old: previous.skipDestinationAddresses, new: updated.skipDestinationAddresses)
        updateList(&result, key: "skip-src-address", old: previous.skipSourceAddresses, new: updated.skipSourceAddresses)

        var sniff = result["sniff"] as? YAMLMap ?? [:]
        if previous.httpPorts != updated.httpPorts || previous.overrideDestination != updated.overrideDestination {
            var http = protocolMap("HTTP", in: sniff) ?? [:]
            http["ports"] = portList(updated.httpPorts, fallback: [80, 443])
            http["override-destination"] = updated.overrideDestination
            sniff["HTTP"] = http
        }
        if previous.tlsPorts != updated.tlsPorts {
            var tls = protocolMap("TLS", in: sniff) ?? [:]
            tls["ports"] = portList(updated.tlsPorts, fallback: [443])
            sniff["TLS"] = tls
        }
        if previous.quicPorts != updated.quicPorts {
            if updated.quicPorts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                removeCaseInsensitiveKey("QUIC", from: &sniff)
            } else {
                var quic = protocolMap("QUIC", in: sniff) ?? [:]
                quic["ports"] = portList(updated.quicPorts, fallback: [])
                sniff["QUIC"] = quic
            }
        }
        if sniff.isEmpty == false { result["sniff"] = sniff }
        return result
    }

    private func updateList(_ map: inout YAMLMap, key: String, old: String, new: String) {
        guard old != new else { return }
        let values = lineList(new)
        if values.isEmpty { map.removeValue(forKey: key) }
        else { map[key] = values }
    }

    private func rootMap(_ content: String) throws -> YAMLMap {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [:] }
        let object = try Yams.load(yaml: content) ?? YAMLMap()
        guard let map = normalize(object) as? YAMLMap else {
            throw NSError(domain: "ProfileSettingsSynchronizer", code: 1, userInfo: [
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

    private func protocolMap(_ name: String, in map: YAMLMap) -> YAMLMap? {
        guard let key = map.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return map[key] as? YAMLMap
    }

    private func removeCaseInsensitiveKey(_ name: String, from map: inout YAMLMap) {
        guard let key = map.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        map.removeValue(forKey: key)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? String {
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        return nil
    }

    private func stringList(_ value: Any?) -> [String] {
        if let values = value as? [Any] { return values.map { String(describing: $0) } }
        if let value { return [String(describing: value)] }
        return []
    }

    private func lineText(_ value: Any?) -> String { stringList(value).joined(separator: ",") }
    private func portText(_ value: Any?) -> String { stringList(value).joined(separator: ",") }

    private func lineList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func portList(_ text: String, fallback: [Int]) -> [Any] {
        let values: [Any] = lineList(text).map { Int($0).map { $0 as Any } ?? $0 }
        return values.isEmpty ? fallback.map { $0 as Any } : values
    }
}

private struct LinkedSettings: Equatable {
    var mixedPort: Int
    var socksPort: Int
    var allowLAN: Bool
    var logLevel: String
    var tunEnabled: Bool
    var dns: DNSSettings
    var sniffer: SnifferSettings

    init(_ settings: AppSettings) {
        mixedPort = settings.mixedPort
        socksPort = settings.socksPort
        allowLAN = settings.allowLAN
        logLevel = settings.logLevel
        tunEnabled = settings.tunEnabled
        dns = DNSSettings(settings)
        sniffer = SnifferSettings(settings)
    }
}

private struct DNSSettings: Equatable {
    var enabled: Bool
    var enhancedMode: String
    var nameservers: [String]
    var fallbacks: [String]

    init(_ settings: AppSettings) {
        enabled = settings.dnsEnabled
        enhancedMode = settings.dnsEnhancedMode
        nameservers = settings.dnsNameservers
        fallbacks = settings.dnsFallbacks
    }
}

private struct SnifferSettings: Equatable {
    var enabled: Bool
    var parsePureIP: Bool
    var forceDNSMapping: Bool
    var overrideDestination: Bool
    var httpPorts: String
    var tlsPorts: String
    var quicPorts: String
    var forceDomains: String
    var skipDomains: String
    var skipDestinationAddresses: String
    var skipSourceAddresses: String

    init(_ settings: AppSettings) {
        enabled = settings.snifferEnabled
        parsePureIP = settings.snifferParsePureIP
        forceDNSMapping = settings.snifferForceDNSMapping
        overrideDestination = settings.snifferOverrideDestination
        httpPorts = settings.snifferHTTPPorts
        tlsPorts = settings.snifferTLSPorts
        quicPorts = settings.snifferQUICPorts
        forceDomains = settings.snifferForceDomains
        skipDomains = settings.snifferSkipDomains
        skipDestinationAddresses = settings.snifferSkipDestinationAddresses
        skipSourceAddresses = settings.snifferSkipSourceAddresses
    }
}
