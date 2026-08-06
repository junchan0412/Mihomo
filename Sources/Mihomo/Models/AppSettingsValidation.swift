import Darwin
import Foundation

struct AppSettingsValidation: Hashable {
    enum Field: String, CaseIterable, Hashable {
        case maxCrashRestarts
        case controllerPort
        case mixedPort
        case socksPort
        case profileRefreshIntervalHours
        case profileRefreshMaxConcurrent
        case resourceUpdateMaxConcurrent
        case delayTestURL
        case directDelayTestURL
        case softwareUpdateManifestURL
        case delayTestTimeoutMS
        case delayTestConcurrency
        case logRetentionDays
        case logMaxFileSizeMB
        case remoteAPIBindAddress
        case systemDNSServers
        case dnsNameservers
        case dnsFallbacks
        case snifferSkipDestinationAddresses
        case snifferSkipSourceAddresses
    }

    struct Issue: Hashable, Identifiable {
        let field: Field
        let message: String

        var id: String { "\(field.rawValue):\(message)" }
    }

    static func validate(_ settings: AppSettings) -> [Issue] {
        var issues: [Issue] = []

        validatePort(settings.controllerPort, field: .controllerPort, name: "控制端口", minimum: 1, into: &issues)
        validatePort(settings.mixedPort, field: .mixedPort, name: "Mixed 端口", minimum: 1, into: &issues)
        validatePort(settings.socksPort, field: .socksPort, name: "SOCKS 端口", minimum: 0, into: &issues)
        validateRange(settings.maxCrashRestarts, field: .maxCrashRestarts, name: "异常恢复次数上限", range: 0...10, unit: "次", into: &issues)

        let ports = [
            (Field.controllerPort, settings.controllerPort, "控制端口"),
            (Field.mixedPort, settings.mixedPort, "Mixed 端口"),
            (Field.socksPort, settings.socksPort, "SOCKS 端口")
        ].filter { $0.1 > 0 }
        for index in ports.indices {
            for otherIndex in ports.indices where otherIndex > index && ports[index].1 == ports[otherIndex].1 {
                issues.append(.init(field: ports[index].0, message: "\(ports[index].2)与\(ports[otherIndex].2)不能使用同一端口。"))
                issues.append(.init(field: ports[otherIndex].0, message: "\(ports[otherIndex].2)与\(ports[index].2)不能使用同一端口。"))
            }
        }

        validateRange(settings.profileRefreshIntervalHours, field: .profileRefreshIntervalHours, name: "订阅刷新间隔", range: 1...720, unit: "小时", into: &issues)
        validateRange(settings.profileRefreshMaxConcurrent, field: .profileRefreshMaxConcurrent, name: "订阅刷新并发数", range: 1...12, unit: "个", into: &issues)
        validateRange(settings.resourceUpdateMaxConcurrent, field: .resourceUpdateMaxConcurrent, name: "资源更新并发数", range: 1...12, unit: "个", into: &issues)
        validateRange(settings.delayTestTimeoutMS, field: .delayTestTimeoutMS, name: "延迟测试超时", range: 1_000...60_000, unit: "ms", into: &issues)
        validateRange(settings.delayTestConcurrency, field: .delayTestConcurrency, name: "延迟测试并发数", range: 1...32, unit: "个", into: &issues)
        validateRange(settings.logRetentionDays, field: .logRetentionDays, name: "日志保留天数", range: 1...365, unit: "天", into: &issues)
        validateRange(settings.logMaxFileSizeMB, field: .logMaxFileSizeMB, name: "日志单文件大小", range: 1...1_024, unit: "MB", into: &issues)

        validateHTTPURL(settings.delayTestURL, field: .delayTestURL, name: "代理节点测试 URL", required: true, into: &issues)
        validateHTTPURL(settings.directDelayTestURL, field: .directDelayTestURL, name: "DIRECT 测试 URL", required: true, into: &issues)
        validateHTTPURL(settings.softwareUpdateManifestURL, field: .softwareUpdateManifestURL, name: "更新 manifest URL", required: false, into: &issues)
        validateIPAddressOrHostname(settings.remoteAPIBindAddress, field: .remoteAPIBindAddress, name: "远程监听地址", into: &issues)
        validateIPList(settings.systemDNSServers, field: .systemDNSServers, name: "系统 DNS", allowCIDR: false, into: &issues)
        validateDNSList(settings.dnsNameservers, field: .dnsNameservers, name: "Nameserver", into: &issues)
        validateDNSList(settings.dnsFallbacks, field: .dnsFallbacks, name: "Fallback", into: &issues)
        validateCIDRText(settings.snifferSkipDestinationAddresses, field: .snifferSkipDestinationAddresses, name: "不嗅探的目标地址", into: &issues)
        validateCIDRText(settings.snifferSkipSourceAddresses, field: .snifferSkipSourceAddresses, name: "不嗅探的来源地址", into: &issues)

        return issues
    }

    static func issue(for field: Field, in settings: AppSettings) -> String? {
        validate(settings).first(where: { $0.field == field })?.message
    }

    private static func validatePort(
        _ value: Int,
        field: Field,
        name: String,
        minimum: Int,
        into issues: inout [Issue]
    ) {
        if (minimum...65_535).contains(value) == false {
            issues.append(.init(field: field, message: "\(name)必须是 \(minimum)–65535 之间的整数。"))
        }
    }

    private static func validateRange(
        _ value: Int,
        field: Field,
        name: String,
        range: ClosedRange<Int>,
        unit: String,
        into issues: inout [Issue]
    ) {
        if range.contains(value) == false {
            issues.append(.init(field: field, message: "\(name)必须是 \(range.lowerBound)–\(range.upperBound) \(unit)。"))
        }
    }

    private static func validateHTTPURL(
        _ value: String,
        field: Field,
        name: String,
        required: Bool,
        into issues: inout [Issue]
    ) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if required {
                issues.append(.init(field: field, message: "\(name)不能为空。"))
            }
            return
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil
        else {
            issues.append(.init(field: field, message: "\(name)必须是不含账号密码的 HTTP(S) URL。"))
            return
        }
        if url.fragment != nil {
            issues.append(.init(field: field, message: "\(name)不能包含 fragment。"))
        }
    }

    private static func validateIPAddressOrHostname(
        _ value: String,
        field: Field,
        name: String,
        into issues: inout [Issue]
    ) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            issues.append(.init(field: field, message: "\(name)不能为空。"))
            return
        }
        if isIPAddress(text) == false && isValidHostname(text) == false {
            issues.append(.init(field: field, message: "\(name)必须是 IP 地址或合法主机名。"))
        }
    }

    private static func validateIPList(
        _ values: [String],
        field: Field,
        name: String,
        allowCIDR: Bool,
        into issues: inout [Issue]
    ) {
        let entries = values
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",\n")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard entries.isEmpty == false else {
            issues.append(.init(field: field, message: "\(name)至少需要一个地址。"))
            return
        }
        for entry in entries where (allowCIDR ? isValidCIDR(entry) : isIPAddress(entry)) == false {
            issues.append(.init(field: field, message: "\(name)包含无效地址：\(entry)。"))
            break
        }
    }

    private static func validateDNSList(
        _ values: [String],
        field: Field,
        name: String,
        into issues: inout [Issue]
    ) {
        let entries = values
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",\n")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        for entry in entries {
            if isIPAddress(entry) || isValidHostname(entry) {
                continue
            }
            if let url = URL(string: entry),
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "tls", "quic"].contains(scheme),
               url.host?.isEmpty == false {
                continue
            }
            issues.append(.init(field: field, message: "\(name)包含无效 DNS 地址：\(entry)。"))
            break
        }
    }

    private static func validateCIDRText(
        _ value: String,
        field: Field,
        name: String,
        into issues: inout [Issue]
    ) {
        let entries = value
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        for entry in entries where isValidCIDR(entry) == false {
            issues.append(.init(field: field, message: "\(name)包含无效 IP/CIDR：\(entry)。"))
            break
        }
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
            || value.withCString { pointer in
                var address = in_addr()
                return inet_pton(AF_INET, pointer, &address) == 1
            }
    }

    private static func isValidCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              isIPAddress(String(parts[0]))
        else { return false }
        let isIPv4 = String(parts[0]).contains(".")
        return isIPv4 ? (0...32).contains(prefix) : (0...128).contains(prefix)
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard value.count <= 253, value.contains(".") || value == "localhost" else { return false }
        guard value == "localhost" || value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return false
        }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard label.isEmpty == false, label.count <= 63,
                  label.first != "-", label.last != "-"
            else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }
        return true
    }
}
