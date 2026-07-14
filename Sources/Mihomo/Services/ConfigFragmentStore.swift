import Foundation
import Yams

struct ConfigFragmentRemoteResponse {
    var data: Data
    var response: URLResponse
    var certificateFingerprint: String?
}

protocol ConfigFragmentRemoteLoading {
    func fetch(_ url: URL, expectedFingerprint: String?) async throws -> ConfigFragmentRemoteResponse
}

struct CertificatePinnedConfigFragmentRemoteLoader: ConfigFragmentRemoteLoading {
    func fetch(_ url: URL, expectedFingerprint: String?) async throws -> ConfigFragmentRemoteResponse {
        let session = CertificatePinningSession(expectedFingerprint: expectedFingerprint)
        let (data, response, fingerprint) = try await session.fetch(url)
        return ConfigFragmentRemoteResponse(
            data: data,
            response: response,
            certificateFingerprint: fingerprint
        )
    }
}

final class ConfigFragmentStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let remoteLoader: any ConfigFragmentRemoteLoading

    init(remoteLoader: any ConfigFragmentRemoteLoading = CertificatePinnedConfigFragmentRemoteLoader()) {
        self.remoteLoader = remoteLoader
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadFragments() throws -> [ConfigFragment] {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.configFragmentsFile.path) else { return [] }
        let data = try Data(contentsOf: AppPaths.configFragmentsFile)
        return try decoder.decode([ConfigFragment].self, from: data)
    }

    func saveFragments(_ fragments: [ConfigFragment]) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(fragments)
        try data.write(to: AppPaths.configFragmentsFile, options: .atomic)
    }

    func importLocalFragment(
        fileURL: URL,
        name: String? = nil,
        kind explicitKind: ConfigFragmentKind? = nil
    ) throws -> ConfigFragment {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let kind = explicitKind ?? inferredKind(for: fileURL)
        try validateFragmentContent(content, kind: kind)
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ConfigFragment(
            name: normalizedName.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : normalizedName,
            kind: kind,
            enabled: true,
            content: content,
            source: .local,
            location: fileURL.path
        )
    }

    func importRemoteFragment(
        urlString: String,
        name: String? = nil,
        kind: ConfigFragmentKind
    ) async throws -> ConfigFragment {
        let url = try validatedRemoteURL(urlString)
        let payload = try await remoteLoader.fetch(url, expectedFingerprint: nil)
        let content = try validatedRemoteContent(payload, kind: kind)
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackName = url.deletingPathExtension().lastPathComponent
        return ConfigFragment(
            name: normalizedName.isEmpty ? (fallbackName.isEmpty ? url.host ?? "远程覆写" : fallbackName) : normalizedName,
            kind: kind,
            enabled: true,
            content: content,
            source: .remote,
            location: url.absoluteString,
            certificateFingerprint: payload.certificateFingerprint
        )
    }

    func refreshRemoteFragment(_ fragment: ConfigFragment) async throws -> ConfigFragment {
        guard fragment.isRemote else { return fragment }
        let url = try validatedRemoteURL(fragment.location)
        let payload = try await remoteLoader.fetch(url, expectedFingerprint: fragment.certificateFingerprint)
        let content = try validatedRemoteContent(payload, kind: fragment.kind)
        var updated = fragment
        updated.content = content
        updated.updatedAt = Date()
        updated.certificateFingerprint = payload.certificateFingerprint ?? fragment.certificateFingerprint
        return updated
    }

    func validateFragmentContent(_ content: String, kind: ConfigFragmentKind) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw fragmentError("覆写内容不能为空")
        }

        switch kind {
        case .yaml:
            guard content.lengthOfBytes(using: .utf8) <= 2 * 1024 * 1024 else {
                throw fragmentError("YAML 覆写不能超过 2 MiB")
            }
            do {
                guard let loaded = try Yams.load(yaml: content),
                      normalizeYAMLValue(loaded) is [String: Any]
                else {
                    throw fragmentError("YAML 覆写必须是顶层映射")
                }
            } catch let error as NSError where error.domain == "Mihomo.ConfigFragment" {
                throw error
            } catch {
                throw fragmentError("YAML 解析失败：\(error.localizedDescription)")
            }
        case .javascript:
            guard content.lengthOfBytes(using: .utf8) <= JSOverrideRunner.maximumFragmentBytes else {
                throw fragmentError("JavaScript 覆写不能超过 \(JSOverrideRunner.maximumFragmentBytes / 1024) KiB")
            }
        }
    }

    func inferredKind(for fileURL: URL) -> ConfigFragmentKind {
        switch fileURL.pathExtension.lowercased() {
        case "js", "mjs", "cjs": return .javascript
        default: return .yaml
        }
    }

    func loadDisabledRules() throws -> Set<String> {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.disabledRulesFile.path) else { return [] }
        let data = try Data(contentsOf: AppPaths.disabledRulesFile)
        return Set(try decoder.decode([String].self, from: data))
    }

    func saveDisabledRules(_ rules: Set<String>) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(rules.sorted())
        try data.write(to: AppPaths.disabledRulesFile, options: .atomic)
    }

    func parseRules(profileContent: String, disabledRules: Set<String>) -> [RuleItem] {
        guard let root = yamlRoot(profileContent),
              let rules = root["rules"] as? [Any]
        else { return parseRulesFromText(profileContent: profileContent, disabledRules: disabledRules) }

        return rules
            .compactMap { $0 as? String }
            .enumerated()
            .map { index, rule in
                RuleItem(index: index + 1, content: rule, disabled: disabledRules.contains(rule))
            }
    }

    func parseProviders(profileContent: String) -> [ProviderItem] {
        guard let root = yamlRoot(profileContent) else {
            return parseProviderBlock(kind: "Proxy", key: "proxy-providers", in: profileContent)
                + parseProviderBlock(kind: "Rule", key: "rule-providers", in: profileContent)
        }

        let rules = (root["rules"] as? [Any])?.compactMap { $0 as? String } ?? []
        let ruleUsage = ruleProviderUsage(from: rules)
        let proxyUsage = proxyProviderUsage(from: root["proxy-groups"])
        return providerItems(kind: "Proxy", key: "proxy-providers", root: root, usage: proxyUsage)
            + providerItems(kind: "Rule", key: "rule-providers", root: root, usage: ruleUsage)
    }

    func makeDiff(original: String, generated: String) -> String {
        let oldLines = original.components(separatedBy: .newlines)
        let newLines = generated.components(separatedBy: .newlines)
        let count = max(oldLines.count, newLines.count)
        var rows: [String] = []
        for index in 0..<count {
            let oldLine = index < oldLines.count ? oldLines[index] : nil
            let newLine = index < newLines.count ? newLines[index] : nil
            if oldLine == newLine, let oldLine {
                rows.append("  \(oldLine)")
            } else {
                if let oldLine { rows.append("- \(oldLine)") }
                if let newLine { rows.append("+ \(newLine)") }
            }
        }
        return rows.joined(separator: "\n")
    }

    private func parseProviderBlock(kind: String, key: String, in content: String) -> [ProviderItem] {
        guard let block = topLevelBlock(named: key, in: content) else { return [] }
        var providers: [ProviderItem] = []
        var currentName: String?
        var currentDetails: [String] = []

        func commit() {
            guard let currentName else { return }
            let detail = currentDetails
                .filter { $0.hasPrefix("type:") || $0.hasPrefix("url:") || $0.hasPrefix("path:") || $0.hasPrefix("behavior:") || $0.hasPrefix("interval:") }
                .prefix(5)
                .joined(separator: " · ")
            providers.append(ProviderItem(kind: kind, name: currentName, detail: detail.isEmpty ? "-" : detail))
        }

        for line in block.components(separatedBy: .newlines).dropFirst() {
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if indent == 2, trimmed.hasSuffix(":"), trimmed.hasPrefix("-") == false {
                commit()
                currentName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                currentDetails = []
            } else if currentName != nil, trimmed.isEmpty == false {
                currentDetails.append(trimmed)
            }
        }
        commit()
        return providers
    }

    private func parseRulesFromText(profileContent: String, disabledRules: Set<String>) -> [RuleItem] {
        guard let block = topLevelBlock(named: "rules", in: profileContent) else { return [] }
        return block.components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- ") else { return nil }
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .enumerated()
            .map { index, rule in
                RuleItem(index: index + 1, content: rule, disabled: disabledRules.contains(rule))
            }
    }

    private func providerItems(kind: String, key: String, root: [String: Any], usage: [String: Int]) -> [ProviderItem] {
        guard let providers = root[key] as? [String: Any] else { return [] }
        return providers.map { name, value in
            let map = value as? [String: Any] ?? [:]
            let providerType = map["type"].map { "\($0)" } ?? ""
            let remoteURL = map["url"].map { "\($0)" }
            let path = map["path"].map { "\($0)" }
            let behavior = map["behavior"].map { "\($0)" }
            let interval = map["interval"].flatMap { value -> Int? in
                if let intValue = value as? Int { return intValue }
                if let stringValue = value as? String { return Int(stringValue) }
                return nil
            }
            var pieces = ["type", "url", "path", "behavior", "interval", "vehicleType", "updatedAt"]
                .compactMap { field in
                    map[field].map { "\(field): \($0)" }
                }
            let count = usage[name, default: 0]
            let memberNames = kind == "Proxy" ? cachedProxyNames(path: path, providerName: name) : []
            if count > 0 {
                pieces.append(kind == "Rule" ? "rules: \(count)" : "uses: \(count)")
            }
            return ProviderItem(
                kind: kind,
                name: name,
                detail: pieces.isEmpty ? "-" : pieces.prefix(6).joined(separator: " · "),
                providerType: providerType,
                remoteURL: remoteURL,
                path: path,
                behavior: behavior,
                interval: interval,
                ruleCount: count,
                memberNames: memberNames
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func cachedProxyNames(path: String?, providerName: String) -> [String] {
        let relativePath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "proxy_providers/\(ProviderResourceManager.safeResourceFileName(providerName, pathExtension: "yaml"))"
        let value = relativePath?.isEmpty == false ? relativePath! : fallback
        guard !value.hasPrefix("/"), !value.split(separator: "/").contains("..") else { return [] }
        let fileURL = value.split(separator: "/").filter { $0 != "." }.reduce(AppPaths.runtimeDirectory) {
            $0.appendingPathComponent(String($1))
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Self.parseCachedProxyNames(content)
    }

    static func parseCachedProxyNames(_ content: String) -> [String] {
        if let names = proxyNamesFromYAML(content), names.isEmpty == false { return names }
        if let decoded = decodeSubscription(content) {
            if let names = proxyNamesFromYAML(decoded), names.isEmpty == false { return names }
            return proxyNamesFromShareLinks(decoded)
        }
        return proxyNamesFromShareLinks(content)
    }

    private static func proxyNamesFromYAML(_ content: String) -> [String]? {
        guard let loaded = try? Yams.load(yaml: content),
              let root = loaded as? [String: Any],
              let proxies = root["proxies"] as? [Any] else { return nil }
        return proxies.compactMap { item in
            (item as? [String: Any])?["name"].map(String.init(describing:))
        }
    }

    private static func decodeSubscription(_ content: String) -> String? {
        var encoded = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder != 0 { encoded.append(String(repeating: "=", count: 4 - remainder)) }
        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func proxyNamesFromShareLinks(_ content: String) -> [String] {
        let schemes = ["ss://", "ssr://", "vmess://", "vless://", "trojan://", "hysteria://", "hysteria2://", "tuic://", "anytls://", "socks5://", "http://", "https://"]
        return content.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard schemes.contains(where: line.hasPrefix) else { return nil }
            if let fragment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first,
               fragment.isEmpty == false {
                return String(fragment).removingPercentEncoding ?? String(fragment)
            }
            return URL(string: line)?.host
        }
    }

    private func ruleProviderUsage(from rules: [String]) -> [String: Int] {
        rules.reduce(into: [String: Int]()) { result, rule in
            let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2, parts[0].uppercased() == "RULE-SET" else { return }
            result[parts[1], default: 0] += 1
        }
    }

    private func proxyProviderUsage(from value: Any?) -> [String: Int] {
        guard let groups = value as? [Any] else { return [:] }
        var usage: [String: Int] = [:]
        for item in groups {
            guard let group = item as? [String: Any],
                  let providers = group["use"] as? [Any]
            else { continue }
            for provider in providers.compactMap({ $0 as? String }) {
                usage[provider, default: 0] += 1
            }
        }
        return usage
    }

    private func yamlRoot(_ content: String) -> [String: Any]? {
        guard let object = try? Yams.load(yaml: content) else { return nil }
        return normalizeYAMLValue(object) as? [String: Any]
    }

    private func normalizeYAMLValue(_ value: Any) -> Any {
        if let map = value as? [String: Any] {
            return map.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = normalizeYAMLValue(pair.value)
            }
        }
        if let map = value as? [AnyHashable: Any] {
            return map.reduce(into: [String: Any]()) { result, pair in
                result[String(describing: pair.key)] = normalizeYAMLValue(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }

    private func validatedRemoteURL(_ value: String) throws -> URL {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw fragmentError("请输入有效的 HTTP 或 HTTPS URL")
        }
        return url
    }

    private func validatedRemoteContent(
        _ payload: ConfigFragmentRemoteResponse,
        kind: ConfigFragmentKind
    ) throws -> String {
        guard let response = payload.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            let status = (payload.response as? HTTPURLResponse)?.statusCode
            throw fragmentError(status.map { "远程覆写请求失败（HTTP \($0)）" } ?? "远程覆写请求失败")
        }
        guard let content = String(data: payload.data, encoding: .utf8) else {
            throw fragmentError("远程覆写不是有效的 UTF-8 文本")
        }
        let normalized = content.first == "\u{feff}" ? String(content.dropFirst()) : content
        try validateFragmentContent(normalized, kind: kind)
        return normalized
    }

    private func fragmentError(_ message: String) -> NSError {
        NSError(
            domain: "Mihomo.ConfigFragment",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func topLevelBlock(named key: String, in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var capture = false
        var block: [String] = []

        for line in lines {
            if line.first?.isWhitespace == false,
               let colon = line.firstIndex(of: ":") {
                let candidate = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate == key {
                    capture = true
                    block = [line]
                    continue
                }
                if capture {
                    break
                }
            }
            if capture {
                block.append(line)
            }
        }
        return block.isEmpty ? nil : block.joined(separator: "\n")
    }
}
