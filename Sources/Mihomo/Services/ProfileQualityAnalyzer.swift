import Foundation
import Yams

struct ProfileQualityAnalyzer {
    private typealias YAMLMap = [String: Any]

    private let runtimeConfigBuilder = RuntimeConfigBuilder()
    private let jsOverrideRunner = JSOverrideRunner()
    private let structureEditor = ProfileYAMLStructureEditor()
    private let fragmentStore = ConfigFragmentStore()

    func analyze(
        profile: ProfileItem,
        profileContent: String,
        settings: AppSettings,
        fragments: [ConfigFragment],
        disabledRules: Set<String>,
        migrationLog: [String] = []
    ) -> ProfileQualityReport {
        var issues: [ProfileQualityIssue] = []
        let originalContent = profileContent
        var transformedContent = profileContent
        let enabledJSFragments = fragments.filter { $0.enabled && $0.kind == .javascript }
        let enabledYAMLFragments = fragments.filter { $0.enabled && $0.kind == .yaml }

        if settings.jsOverrideEnabled {
            do {
                transformedContent = try jsOverrideRunner.apply(fragments: fragments, to: profileContent)
            } catch {
                issues.append(.init(
                    severity: .error,
                    title: "JS Transform 失败",
                    detail: error.localizedDescription
                ))
            }
        }

        let snapshot: ProfileStructureSnapshot
        do {
            snapshot = try structureEditor.snapshot(content: transformedContent)
        } catch {
            issues.append(.init(
                severity: .error,
                title: "Profile YAML 结构不可解析",
                detail: error.localizedDescription
            ))
            return makeReport(
                issues: issues,
                runtimeItems: [],
                diffLayers: diffLayers(
                    profileContent: originalContent,
                    transformedContent: transformedContent,
                    generatedConfig: "",
                    settings: settings,
                    enabledJSFragments: enabledJSFragments,
                    enabledYAMLFragments: enabledYAMLFragments
                ),
                migrationLog: migrationLog,
                generatedConfig: ""
            )
        }

        let providers = fragmentStore.parseProviders(profileContent: transformedContent)
        issues.append(contentsOf: profileHealthIssues(profile: profile, snapshot: snapshot, providers: providers, settings: settings))
        for rule in snapshot.rules {
            issues.append(contentsOf: validateRule(rule, snapshot: snapshot, providers: providers))
        }

        let generatedConfig: String
        do {
            generatedConfig = try runtimeConfigBuilder.build(
                profileContent: transformedContent,
                settings: settings,
                fragments: fragments,
                disabledRules: disabledRules
            )
        } catch {
            issues.append(.init(
                severity: .error,
                title: "运行时配置生成失败",
                detail: error.localizedDescription
            ))
            return makeReport(
                issues: issues,
                runtimeItems: [],
                diffLayers: diffLayers(
                    profileContent: originalContent,
                    transformedContent: transformedContent,
                    generatedConfig: "",
                    settings: settings,
                    enabledJSFragments: enabledJSFragments,
                    enabledYAMLFragments: enabledYAMLFragments
                ),
                migrationLog: migrationLog,
                generatedConfig: ""
            )
        }

        return makeReport(
            issues: issues,
            runtimeItems: runtimeItems(from: generatedConfig, transformedContent: transformedContent),
            diffLayers: diffLayers(
                profileContent: originalContent,
                transformedContent: transformedContent,
                generatedConfig: generatedConfig,
                settings: settings,
                enabledJSFragments: enabledJSFragments,
                enabledYAMLFragments: enabledYAMLFragments
            ),
            migrationLog: migrationLog,
            generatedConfig: generatedConfig
        )
    }

    func validateRule(
        _ rule: EditableProfileRule,
        snapshot: ProfileStructureSnapshot,
        providers: [ProviderItem]
    ) -> [ProfileQualityIssue] {
        var issues: [ProfileQualityIssue] = []
        let type = rule.type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let payload = rule.payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = rule.target.trimmingCharacters(in: .whitespacesAndNewlines)
        let builtInTargets: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"]
        let groupNames = Set(snapshot.groups.map(\.name))

        if type.isEmpty {
            issues.append(.init(severity: .error, title: "规则类型缺失", detail: "第 \(rule.index) 条规则没有类型。"))
        }
        if target.isEmpty {
            issues.append(.init(severity: .error, title: "规则策略缺失", detail: "第 \(rule.index) 条规则没有目标策略。"))
        } else if builtInTargets.contains(target.uppercased()) == false && groupNames.contains(target) == false {
            issues.append(.init(
                severity: .error,
                title: "目标策略不存在",
                detail: "第 \(rule.index) 条规则指向 \(target)，但 Profile 中没有同名策略组。"
            ))
        }

        if type == "MATCH" {
            if payload.isEmpty == false {
                issues.append(.init(
                    severity: .warning,
                    title: "MATCH 不需要匹配内容",
                    detail: "第 \(rule.index) 条 MATCH 规则的 payload 会被忽略。"
                ))
            }
        } else if payload.isEmpty {
            issues.append(.init(
                severity: .error,
                title: "规则字段缺失",
                detail: "第 \(rule.index) 条 \(type) 规则缺少匹配内容。"
            ))
        }

        if type == "RULE-SET" {
            let ruleProviders = providers.filter { $0.kind == "Rule" }
            let proxyProviders = providers.filter { $0.kind == "Proxy" }
            if ruleProviders.contains(where: { $0.name == payload }) == false {
                if proxyProviders.contains(where: { $0.name == payload }) {
                    issues.append(.init(
                        severity: .error,
                        title: "Provider 类型不匹配",
                        detail: "第 \(rule.index) 条 RULE-SET 引用了 Proxy Provider \(payload)，需要改为 Rule Provider。"
                    ))
                } else {
                    issues.append(.init(
                        severity: .error,
                        title: "Rule Provider 不存在",
                        detail: "第 \(rule.index) 条 RULE-SET 引用了不存在的 Provider：\(payload)。"
                    ))
                }
            }
        }

        if type == "IP-CIDR" || type == "IP-CIDR6" {
            let maxPrefix = type == "IP-CIDR6" ? 128 : 32
            let parts = payload.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count != 2 || Int(parts[1]).map({ $0 >= 0 && $0 <= maxPrefix }) != true {
                issues.append(.init(
                    severity: .warning,
                    title: "CIDR 格式可疑",
                    detail: "第 \(rule.index) 条 \(type) 的 CIDR 应包含 /0...\(maxPrefix) 前缀。"
                ))
            }
        }

        return issues
    }

    private func profileHealthIssues(
        profile: ProfileItem,
        snapshot: ProfileStructureSnapshot,
        providers: [ProviderItem],
        settings: AppSettings
    ) -> [ProfileQualityIssue] {
        var issues: [ProfileQualityIssue] = []
        if profile.source == .remote {
            if let expireAt = profile.expireAt, expireAt < Date() {
                issues.append(.init(
                    severity: .warning,
                    title: "订阅已过期",
                    detail: "\(profile.name) 的订阅到期时间为 \(Formatters.shortDate.string(from: expireAt))。"
                ))
            }
            if URL(string: profile.location)?.scheme == nil {
                issues.append(.init(
                    severity: .warning,
                    title: "订阅 URL 无效",
                    detail: "远程配置来源不是有效 URL：\(profile.location)。"
                ))
            }
        }

        if snapshot.proxyNames.isEmpty {
            issues.append(.init(severity: .warning, title: "节点为空", detail: "Profile 未声明任何 proxies，启动后可能没有可用出站。"))
        }
        if snapshot.rules.isEmpty {
            issues.append(.init(severity: .warning, title: "规则为空", detail: "Profile 未声明 rules，Rule 模式下可能无法按预期分流。"))
        }

        for provider in providers {
            if let remoteURL = provider.remoteURL, remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                guard let url = URL(string: remoteURL), url.scheme?.hasPrefix("http") == true else {
                    issues.append(.init(
                        severity: .warning,
                        title: "Provider URL 无效",
                        detail: "\(provider.kind) Provider \(provider.name) 的 URL 格式不可用。"
                    ))
                    continue
                }
            } else if provider.path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(.init(
                    severity: .warning,
                    title: "Provider 来源缺失",
                    detail: "\(provider.kind) Provider \(provider.name) 未声明 url 或 path。"
                ))
            }

            if let path = provider.path, path.hasPrefix("/") {
                if FileManager.default.fileExists(atPath: path) == false {
                    issues.append(.init(
                        severity: .warning,
                        title: "Provider 本地文件不存在",
                        detail: "\(provider.kind) Provider \(provider.name) 指向的文件不存在：\(path)。"
                    ))
                }
            }
        }

        if settings.jsOverrideEnabled && providers.isEmpty && snapshot.rules.isEmpty {
            issues.append(.init(
                severity: .info,
                title: "JS Transform 已启用",
                detail: "当前结构统计会基于 JS 输出；请确认 transform(config) 返回完整 YAML。"
            ))
        }
        return issues
    }

    private func runtimeItems(from generatedConfig: String, transformedContent: String) -> [RuntimeInspectorItem] {
        guard let root = yamlRoot(generatedConfig) else {
            return [.init(title: "解析", value: "失败", detail: "最终 runtime config 无法解析为 YAML 映射")]
        }

        let dns = root["dns"] as? YAMLMap
        let tun = root["tun"] as? YAMLMap
        let rules = root["rules"] as? [Any] ?? []
        let proxyGroups = root["proxy-groups"] as? [Any] ?? []
        let proxyProviders = root["proxy-providers"] as? YAMLMap ?? [:]
        let ruleProviders = root["rule-providers"] as? YAMLMap ?? [:]
        let sourceRules = (yamlRoot(transformedContent)?["rules"] as? [Any] ?? []).count

        return [
            .init(title: "Mixed Port", value: stringValue(root["mixed-port"]), detail: "App overlay 最终接管端口"),
            .init(title: "SOCKS Port", value: stringValue(root["socks-port"]), detail: root["socks-port"] == nil ? "未启用独立 SOCKS 端口" : "来自 App 设置"),
            .init(title: "Controller", value: stringValue(root["external-controller"]), detail: "外部控制器监听地址"),
            .init(title: "DNS", value: dns == nil ? "未启用" : "\(stringValue(dns?["enhanced-mode"])) · \(arrayCount(dns?["nameserver"])) 个 nameserver", detail: "由 App overlay 生成"),
            .init(title: "TUN", value: boolValue(tun?["enable"]) ? "已启用" : "未启用", detail: tun?["stack"].map { "stack: \($0)" } ?? "未写入 tun 配置"),
            .init(title: "Provider", value: "Proxy \(proxyProviders.count) / Rule \(ruleProviders.count)", detail: "最终 runtime config 中的 Provider 数量"),
            .init(title: "规则", value: "\(rules.count)", detail: sourceRules == rules.count ? "来自 Profile/JS 输出" : "已应用禁用规则过滤"),
            .init(title: "策略组", value: "\(proxyGroups.count)", detail: "最终 runtime config 中的 proxy-groups 数量")
        ]
    }

    private func diffLayers(
        profileContent: String,
        transformedContent: String,
        generatedConfig: String,
        settings: AppSettings,
        enabledJSFragments: [ConfigFragment],
        enabledYAMLFragments: [ConfigFragment]
    ) -> [ConfigDiffLayer] {
        let profileLines = profileContent.split(separator: "\n", omittingEmptySubsequences: false).count
        let profileBytes = profileContent.data(using: .utf8)?.count ?? 0
        let appOverlayFields = [
            "mixed-port",
            settings.socksPort > 0 ? "socks-port" : nil,
            "allow-lan",
            "external-controller",
            settings.dnsNameservers.isEmpty && settings.dnsFallbacks.isEmpty ? nil : "dns",
            settings.snifferEnabled ? "sniffer" : nil,
            settings.tunEnabled ? "tun" : nil
        ].compactMap { $0 }

        return [
            .init(
                name: "Profile 原文",
                changed: false,
                summary: "\(profileLines) 行，\(Formatters.bytes(Int64(profileBytes)))"
            ),
            .init(
                name: "JS Transform",
                changed: settings.jsOverrideEnabled && profileContent != transformedContent,
                summary: settings.jsOverrideEnabled ? "\(enabledJSFragments.count) 个启用片段" : "未启用"
            ),
            .init(
                name: "YAML 片段",
                changed: settings.yamlOverrideEnabled && enabledYAMLFragments.isEmpty == false,
                summary: settings.yamlOverrideEnabled ? enabledYAMLFragments.map(\.name).prefix(3).joined(separator: "、") : "未启用"
            ),
            .init(
                name: "App overlay",
                changed: generatedConfig.isEmpty == false,
                summary: appOverlayFields.joined(separator: "、")
            )
        ]
    }

    private func makeReport(
        issues: [ProfileQualityIssue],
        runtimeItems: [RuntimeInspectorItem],
        diffLayers: [ConfigDiffLayer],
        migrationLog: [String],
        generatedConfig: String
    ) -> ProfileQualityReport {
        let score = max(0, issues.reduce(100) { result, issue in
            switch issue.severity {
            case .error: return result - 20
            case .warning: return result - 8
            case .info: return result - 2
            }
        })
        let headline: String
        if issues.contains(where: { $0.severity == .error }) {
            headline = "需要修复后再启用"
        } else if score >= 90 {
            headline = "配置质量良好"
        } else if score >= 70 {
            headline = "有可优化项"
        } else {
            headline = "建议先检查配置"
        }

        return ProfileQualityReport(
            score: score,
            headline: headline,
            issues: issues,
            runtimeItems: runtimeItems,
            diffLayers: diffLayers,
            migrationLog: migrationLog,
            generatedConfig: generatedConfig
        )
    }

    private func yamlRoot(_ content: String) -> YAMLMap? {
        guard let object = try? Yams.load(yaml: content) else { return nil }
        return normalizeYAMLValue(object) as? YAMLMap
    }

    private func normalizeYAMLValue(_ value: Any) -> Any {
        if let map = value as? YAMLMap {
            return map.reduce(into: YAMLMap()) { result, pair in
                result[pair.key] = normalizeYAMLValue(pair.value)
            }
        }
        if let map = value as? [AnyHashable: Any] {
            return map.reduce(into: YAMLMap()) { result, pair in
                result[String(describing: pair.key)] = normalizeYAMLValue(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value else { return "-" }
        return "\(value)"
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? String { return ["true", "1", "yes"].contains(value.lowercased()) }
        return false
    }

    private func arrayCount(_ value: Any?) -> Int {
        (value as? [Any])?.count ?? 0
    }
}
