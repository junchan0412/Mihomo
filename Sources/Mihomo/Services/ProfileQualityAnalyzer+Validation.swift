import Foundation

extension ProfileQualityAnalyzer {
    func profileHealthIssues(
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

        if snapshot.rules.isEmpty {
            issues.append(.init(severity: .warning, title: "规则为空", detail: "Profile 未声明 rules，Rule 模式下可能无法按预期分流。"))
        }

        issues.append(contentsOf: validatePolicyGroupReferences(snapshot: snapshot, providers: providers))

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

    func validatePolicyGroupReferences(
        snapshot: ProfileStructureSnapshot,
        providers: [ProviderItem]
    ) -> [ProfileQualityIssue] {
        var issues: [ProfileQualityIssue] = []
        let builtInMembers: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "COMPATIBLE"]
        let proxyNames = Set(snapshot.proxyNames)
        let groupNames = Set(snapshot.groups.map(\.name))
        let proxyProviderNames = Set(providers.filter { $0.kind == "Proxy" }.map(\.name))
        let ruleProviderNames = Set(providers.filter { $0.kind == "Rule" }.map(\.name))

        for group in snapshot.groups {
            for member in group.proxies.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where member.isEmpty == false &&
                builtInMembers.contains(member.uppercased()) == false &&
                proxyNames.contains(member) == false &&
                groupNames.contains(member) == false {
                issues.append(.init(
                    severity: .error,
                    title: "策略组节点不存在",
                    detail: "策略组 \(group.name) 引用了不存在的节点或策略组：\(member)。"
                ))
            }

            for provider in group.uses.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where provider.isEmpty == false {
                if proxyProviderNames.contains(provider) {
                    continue
                }
                if ruleProviderNames.contains(provider) {
                    issues.append(.init(
                        severity: .error,
                        title: "策略组 Provider 类型不匹配",
                        detail: "策略组 \(group.name) 的 use 引用了 Rule Provider \(provider)，需要改为 Proxy Provider。"
                    ))
                } else {
                    issues.append(.init(
                        severity: .error,
                        title: "Proxy Provider 不存在",
                        detail: "策略组 \(group.name) 的 use 引用了不存在的 Proxy Provider：\(provider)。"
                    ))
                }
            }
        }

        return issues
    }

    func validateRuntimeSchema(
        root: YAMLMap,
        providers: [ProviderItem],
        settings: AppSettings
    ) -> [ProfileQualityIssue] {
        var issues: [ProfileQualityIssue] = []

        let inlineProxyCount = arrayCount(root["proxies"])
        let proxyProviderCount = (root["proxy-providers"] as? YAMLMap)?.count ?? 0
        if inlineProxyCount == 0 && proxyProviderCount == 0 {
            issues.append(.init(
                severity: .warning,
                title: "没有可用出站来源",
                detail: "最终 runtime config 的 proxies 与 proxy-providers 都为空；仅此情况下才可能没有可用代理出站。"
            ))
        }

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
            for resolver in stringArray(dns["nameserver"]) + stringArray(dns["fallback"])
            where isPlausibleDNSResolver(resolver) == false {
                issues.append(.init(
                    severity: .warning,
                    title: "DNS nameserver 格式可疑",
                    detail: "DNS resolver \(resolver) 不是常见 IP、system、DoH/DoT/DoQ 或 dhcp 写法。"
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
                } else if isSupportedTunStack(stack) == false {
                    issues.append(.init(
                        severity: .warning,
                        title: "TUN stack 可疑",
                        detail: "tun.stack 常见值为 system、gvisor 或 mixed，当前为 \(stack)。"
                    ))
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
            for domain in lineList(settings.snifferForceDomains) + lineList(settings.snifferSkipDomains)
            where isValidSnifferDomainToken(domain) == false {
                issues.append(.init(
                    severity: .warning,
                    title: "Sniffer domain 格式可疑",
                    detail: "Sniffer domain \(domain) 不应包含协议、路径或空白字符。"
                ))
            }
        }

        for provider in providers {
            issues.append(contentsOf: validateProvider(provider))
        }

        return issues
    }

    func validateProvider(_ provider: ProviderItem) -> [ProfileQualityIssue] {
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
        if provider.kind == "Rule" {
            let behavior = provider.behavior?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if behavior.isEmpty {
                issues.append(.init(
                    severity: .warning,
                    title: "Rule Provider behavior 缺失",
                    detail: "Rule Provider \(provider.name) 建议声明 behavior: domain、ipcidr 或 classical。"
                ))
            } else if ["domain", "ipcidr", "classical"].contains(behavior) == false {
                issues.append(.init(
                    severity: .warning,
                    title: "Rule Provider behavior 可疑",
                    detail: "Rule Provider \(provider.name) 的 behavior 为 \(behavior)，常见值为 domain、ipcidr 或 classical。"
                ))
            }
        }
        return issues
    }

}
