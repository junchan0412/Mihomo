import Foundation

struct ProfileQualityAnalyzer {
    typealias YAMLMap = [String: Any]

    private let appDefaultKeys: Set<String> = [
        "mixed-port",
        "socks-port",
        "allow-lan",
        "mode",
        "log-level",
        "external-controller",
        "external-ui",
        "external-ui-name",
        "external-ui-url",
        "secret",
        "dns",
        "sniffer",
        "tun"
    ]

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
                sourceItems: [],
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
                sourceItems: [],
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

        if let root = yamlRoot(generatedConfig) {
            issues.append(contentsOf: validateRuntimeSchema(root: root, providers: providers, settings: settings))
        }

        return makeReport(
            issues: issues,
            runtimeItems: runtimeItems(from: generatedConfig, transformedContent: transformedContent),
            sourceItems: runtimeSourceItems(
                profileContent: originalContent,
                transformedContent: transformedContent,
                generatedConfig: generatedConfig,
                settings: settings,
                enabledYAMLFragments: enabledYAMLFragments
            ),
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
            .init(title: "Mixed Port", value: stringValue(root["mixed-port"]), detail: "最终运行端口；配置声明优先于应用默认"),
            .init(title: "SOCKS Port", value: stringValue(root["socks-port"]), detail: root["socks-port"] == nil ? "未启用独立 SOCKS 端口" : "来自 App 设置"),
            .init(title: "Controller", value: stringValue(root["external-controller"]), detail: "外部控制器监听地址"),
            .init(title: "DNS", value: dns == nil ? "未启用" : "\(stringValue(dns?["enhanced-mode"])) · \(arrayCount(dns?["nameserver"])) 个 nameserver", detail: "最终运行配置；未声明字段使用应用默认"),
            .init(title: "TUN", value: boolValue(tun?["enable"]) ? "已启用" : "未启用", detail: tun?["stack"].map { "stack: \($0)" } ?? "未写入 tun 配置"),
            .init(title: "Provider", value: "Proxy \(proxyProviders.count) / Rule \(ruleProviders.count)", detail: "最终 runtime config 中的 Provider 数量"),
            .init(title: "规则", value: "\(rules.count)", detail: sourceRules == rules.count ? "来自 Profile/JS 输出" : "已应用禁用规则过滤"),
            .init(title: "策略组", value: "\(proxyGroups.count)", detail: "最终 runtime config 中的 proxy-groups 数量")
        ]
    }

    private func runtimeSourceItems(
        profileContent: String,
        transformedContent: String,
        generatedConfig: String,
        settings: AppSettings,
        enabledYAMLFragments: [ConfigFragment]
    ) -> [RuntimeConfigSourceItem] {
        guard let generatedRoot = yamlRoot(generatedConfig) else { return [] }
        let originalRoot = yamlRoot(profileContent) ?? [:]
        let transformedRoot = yamlRoot(transformedContent) ?? [:]
        let yamlFragmentKeys = settings.yamlOverrideEnabled ? topLevelKeys(in: enabledYAMLFragments) : []
        let inspectedKeys = orderedUnique([
            "mixed-port",
            "socks-port",
            "allow-lan",
            "mode",
            "log-level",
            "external-controller",
            "secret",
            "dns",
            "sniffer",
            "tun",
            "external-ui",
            "proxies",
            "proxy-groups",
            "rules",
            "proxy-providers",
            "rule-providers"
        ] + generatedRoot.keys.sorted())

        return inspectedKeys.compactMap { key in
            let finalValue = generatedRoot[key]
            let hasAppDefault = appDefaultKeys.contains(key)
            guard finalValue != nil || hasAppDefault else { return nil }
            let source = sourceTitle(
                for: key,
                hasAppDefault: hasAppDefault,
                originalRoot: originalRoot,
                transformedRoot: transformedRoot,
                yamlFragmentKeys: yamlFragmentKeys
            )
            return RuntimeConfigSourceItem(
                path: key,
                source: source,
                value: fieldValueSummary(finalValue),
                detail: sourceDetail(
                    for: key,
                    source: source,
                    hasAppDefault: hasAppDefault,
                    value: finalValue
                ),
                usesAppDefault: source == "应用默认"
            )
        }
    }

    private func sourceTitle(
        for key: String,
        hasAppDefault: Bool,
        originalRoot: YAMLMap,
        transformedRoot: YAMLMap,
        yamlFragmentKeys: Set<String>
    ) -> String {
        if yamlFragmentKeys.contains(key) {
            return "YAML 覆写"
        }
        if transformedRoot.keys.contains(key) {
            if valuesDiffer(originalRoot[key], transformedRoot[key]) {
                return "JS Transform"
            }
            return "Profile 配置"
        }
        if hasAppDefault { return "应用默认" }
        return "生成结果"
    }

    private func sourceDetail(for key: String, source: String, hasAppDefault: Bool, value: Any?) -> String {
        switch source {
        case "YAML 覆写":
            return "由启用的 YAML 覆写片段合并，优先级高于 Profile、JS Transform 与应用内设置。"
        case "JS Transform":
            return "由 JS Transform 修改 Profile 后写入，优先级高于应用内同名设置。"
        case "Profile 配置":
            return "来自当前 Profile / 订阅；配置中声明的值优先于应用内同名设置。"
        case "应用默认":
            let state = value == nil ? "当前未写入" : "当前生效"
            return "\(state)；仅当 Profile、JS Transform 与 YAML 覆写均未声明此字段时使用应用内设置。"
        default:
            return hasAppDefault
                ? "由生成流程保留；配置未覆盖时回退到应用默认值。"
                : "由生成流程保留在最终 runtime config。"
        }
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
            .init(name: "应用默认", changed: generatedConfig.isEmpty == false, summary: appOverlayFields.joined(separator: "、")),
            .init(name: "Profile 配置", changed: profileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, summary: "\(profileLines) 行，\(Formatters.bytes(Int64(profileBytes)))"),
            .init(
                name: "JS Transform",
                changed: settings.jsOverrideEnabled && profileContent != transformedContent,
                summary: settings.jsOverrideEnabled ? "\(enabledJSFragments.count) 个启用片段" : "未启用"
            ),
            .init(
                name: "YAML 覆写",
                changed: settings.yamlOverrideEnabled && enabledYAMLFragments.isEmpty == false,
                summary: settings.yamlOverrideEnabled ? enabledYAMLFragments.map(\.name).prefix(3).joined(separator: "、") : "未启用"
            )
        ]
    }

    private func makeReport(
        issues: [ProfileQualityIssue],
        runtimeItems: [RuntimeInspectorItem],
        sourceItems: [RuntimeConfigSourceItem],
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
            sourceItems: sourceItems,
            diffLayers: diffLayers,
            migrationLog: migrationLog,
            generatedConfig: generatedConfig
        )
    }
}
