import Foundation
import Yams

struct ProfileQualityAnalyzer {
    private typealias YAMLMap = [String: Any]

    private let appManagedKeys: Set<String> = [
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

    private func validateRuntimeSchema(
        root: YAMLMap,
        providers: [ProviderItem],
        settings: AppSettings
    ) -> [ProfileQualityIssue] {
        var issues: [ProfileQualityIssue] = []

        issues.append(contentsOf: validatePort(root["mixed-port"], title: "mixed-port"))
        if let socksPort = root["socks-port"] {
            issues.append(contentsOf: validatePort(socksPort, title: "socks-port"))
        }

        if let controller = root["external-controller"].map({ "\($0)" }) {
            let parts = controller.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count < 2 || Int(parts.last ?? "").map({ (1...65_535).contains($0) }) != true {
                issues.append(.init(
                    severity: .error,
                    title: "Controller 地址无效",
                    detail: "external-controller 应包含有效端口，当前为 \(controller)。"
                ))
            }
        }

        if let dns = root["dns"] as? YAMLMap {
            let mode = stringValue(dns["enhanced-mode"])
            if ["fake-ip", "redir-host"].contains(mode) == false {
                issues.append(.init(
                    severity: .warning,
                    title: "DNS enhanced-mode 可疑",
                    detail: "mihomo 常用 enhanced-mode 为 fake-ip 或 redir-host，当前为 \(mode)。"
                ))
            }
            if arrayCount(dns["nameserver"]) == 0 {
                issues.append(.init(
                    severity: .error,
                    title: "DNS nameserver 缺失",
                    detail: "最终 runtime config 启用了 dns，但 nameserver 为空。"
                ))
            }
        } else if settings.autoSetSystemDNS {
            issues.append(.init(
                severity: .warning,
                title: "系统 DNS 接管缺少 runtime DNS",
                detail: "已启用系统 DNS 接管，但 runtime config 未写入 dns；请确认 DNS 设置或关闭系统 DNS 接管。"
            ))
        }

        if settings.tunEnabled {
            if let tun = root["tun"] as? YAMLMap {
                if boolValue(tun["enable"]) == false {
                    issues.append(.init(
                        severity: .error,
                        title: "TUN 未启用",
                        detail: "设置中开启了 TUN，但最终 runtime config 的 tun.enable 不是 true。"
                    ))
                }
                let stack = stringValue(tun["stack"])
                if stack.isEmpty || stack == "-" {
                    issues.append(.init(severity: .warning, title: "TUN stack 缺失", detail: "建议显式写入 tun.stack，当前未找到 stack。"))
                }
                if arrayCount(tun["dns-hijack"]) == 0 {
                    issues.append(.init(severity: .warning, title: "TUN DNS 劫持缺失", detail: "TUN 模式未声明 dns-hijack，DNS 流量可能不进入 mihomo。"))
                }
            } else {
                issues.append(.init(
                    severity: .error,
                    title: "TUN 配置缺失",
                    detail: "设置中开启了 TUN，但最终 runtime config 没有 tun 字段。"
                ))
            }
        }

        if settings.snifferEnabled {
            if let sniffer = root["sniffer"] as? YAMLMap {
                if boolValue(sniffer["enable"]) == false {
                    issues.append(.init(severity: .warning, title: "Sniffer 未启用", detail: "设置中开启了 Sniffer，但最终 sniffer.enable 不是 true。"))
                }
                if (sniffer["sniff"] as? YAMLMap)?.isEmpty != false {
                    issues.append(.init(severity: .warning, title: "Sniffer sniff 规则缺失", detail: "最终 runtime config 未包含 HTTP/TLS sniff 端口。"))
                }
            } else {
                issues.append(.init(severity: .warning, title: "Sniffer 配置缺失", detail: "设置中开启了 Sniffer，但最终 runtime config 没有 sniffer 字段。"))
            }
            for port in lineList(settings.snifferPorts) where isValidSnifferPortToken(port) == false {
                issues.append(.init(
                    severity: .warning,
                    title: "Sniffer 端口可疑",
                    detail: "端口 \(port) 不是 1...65535 的整数或 start-end 范围。"
                ))
            }
        }

        for provider in providers {
            issues.append(contentsOf: validateProvider(provider))
        }

        return issues
    }

    private func validateProvider(_ provider: ProviderItem) -> [ProfileQualityIssue] {
        var issues: [ProfileQualityIssue] = []
        let type = provider.providerType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type.isEmpty == false, ["http", "file", "inline"].contains(type) == false {
            issues.append(.init(
                severity: .warning,
                title: "Provider 类型可疑",
                detail: "\(provider.kind) Provider \(provider.name) 的 type 为 \(type)，请确认 mihomo 是否支持。"
            ))
        }
        if type == "http" && provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(.init(
                severity: .error,
                title: "HTTP Provider 缺少 URL",
                detail: "\(provider.kind) Provider \(provider.name) 声明为 http，但未提供 url。"
            ))
        }
        if type == "file" && provider.path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(.init(
                severity: .error,
                title: "File Provider 缺少 Path",
                detail: "\(provider.kind) Provider \(provider.name) 声明为 file，但未提供 path。"
            ))
        }
        if let path = provider.path, path.contains("..") {
            issues.append(.init(
                severity: .error,
                title: "Provider path 不安全",
                detail: "\(provider.kind) Provider \(provider.name) 的 path 包含 ..：\(path)。"
            ))
        }
        if let interval = provider.interval, interval <= 0 {
            issues.append(.init(
                severity: .warning,
                title: "Provider interval 可疑",
                detail: "\(provider.kind) Provider \(provider.name) 的 interval 应大于 0。"
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
            let isAppManaged = appManagedKeys.contains(key)
            guard finalValue != nil || isAppManaged else { return nil }
            let source = sourceTitle(
                for: key,
                isAppManaged: isAppManaged,
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
                    isAppManaged: isAppManaged,
                    value: finalValue
                ),
                isAppManaged: isAppManaged
            )
        }
    }

    private func sourceTitle(
        for key: String,
        isAppManaged: Bool,
        originalRoot: YAMLMap,
        transformedRoot: YAMLMap,
        yamlFragmentKeys: Set<String>
    ) -> String {
        if isAppManaged {
            return "App overlay"
        }
        if yamlFragmentKeys.contains(key) {
            return "YAML 片段"
        }
        if transformedRoot.keys.contains(key) {
            if valuesDiffer(originalRoot[key], transformedRoot[key]) {
                return "JS Transform"
            }
            return "Profile"
        }
        return "生成结果"
    }

    private func sourceDetail(for key: String, source: String, isAppManaged: Bool, value: Any?) -> String {
        if isAppManaged {
            let state = value == nil ? "当前未写入" : "最终由 App 设置写入"
            return "\(state)；Profile、JS 或 YAML 片段中的同名字段会被移除后重写。"
        }
        switch source {
        case "YAML 片段":
            return "由启用的 YAML 片段合并到 Profile 后进入 runtime config。"
        case "JS Transform":
            return "由 JS Transform 修改 Profile 后进入 runtime config。"
        case "Profile":
            return "保留自当前 Profile / 订阅。"
        default:
            return "由生成流程保留在最终 runtime config。"
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

    private func validatePort(_ value: Any?, title: String) -> [ProfileQualityIssue] {
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

    private func lineList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func isValidSnifferPortToken(_ token: String) -> Bool {
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

    private func topLevelKeys(in fragments: [ConfigFragment]) -> Set<String> {
        fragments.reduce(into: Set<String>()) { result, fragment in
            guard let root = yamlRoot(fragment.content) else { return }
            result.formUnion(root.keys)
        }
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private func valuesDiffer(_ lhs: Any?, _ rhs: Any?) -> Bool {
        fieldValueSummary(lhs) != fieldValueSummary(rhs)
    }

    private func fieldValueSummary(_ value: Any?) -> String {
        guard let value else { return "未写入" }
        if let map = value as? YAMLMap {
            return "\(map.count) 个字段"
        }
        if let array = value as? [Any] {
            return "\(array.count) 项"
        }
        return "\(value)"
    }
}
