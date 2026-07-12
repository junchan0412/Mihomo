import Foundation
import Yams

final class ConfigFragmentStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
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
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              let root = yamlRoot(content),
              let proxies = root["proxies"] as? [Any]
        else { return [] }
        return proxies.compactMap { item in
            (item as? [String: Any])?["name"].map(String.init(describing:))
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
