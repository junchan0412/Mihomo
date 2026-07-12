import Foundation

extension ProfileQualityAnalyzer {
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
        } else if isSupportedRuleType(type) == false {
            issues.append(.init(
                severity: .warning,
                title: "规则类型可疑",
                detail: "第 \(rule.index) 条规则类型 \(type) 不是常见 mihomo rule type，请检查是否拼写错误。"
            ))
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

        if ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "GEOSITE"].contains(type),
           payload.isEmpty == false,
           isPlausibleDomainRulePayload(payload) == false {
            issues.append(.init(
                severity: .warning,
                title: "规则匹配内容可疑",
                detail: "第 \(rule.index) 条 \(type) 的 payload 不应包含 URL scheme、路径或空白字符：\(payload)。"
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

        if ["IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR", "SRC-IP-CIDR6"].contains(type) {
            let cidrType = type.hasSuffix("CIDR6") ? "IP-CIDR6" : "IP-CIDR"
            let maxPrefix = cidrType == "IP-CIDR6" ? 128 : 32
            let parts = payload.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count != 2 || Int(parts[1]).map({ $0 >= 0 && $0 <= maxPrefix }) != true {
                issues.append(.init(
                    severity: .warning,
                    title: "CIDR 格式可疑",
                    detail: "第 \(rule.index) 条 \(type) 的 CIDR 应包含 /0...\(maxPrefix) 前缀。"
                ))
            } else if isValidCIDRAddress(String(parts[0]), type: cidrType) == false {
                issues.append(.init(
                    severity: .warning,
                    title: "CIDR 地址格式可疑",
                    detail: "第 \(rule.index) 条 \(type) 的地址部分与规则类型不匹配：\(payload)。"
                ))
            }
        }

        if ["SRC-PORT", "DST-PORT"].contains(type),
           payload.isEmpty == false,
           isValidPortRulePayload(payload) == false {
            issues.append(.init(
                severity: .warning,
                title: "端口规则可疑",
                detail: "第 \(rule.index) 条 \(type) 的 payload 应为 1...65535 的端口或 start-end 范围：\(payload)。"
            ))
        }

        if type == "GEOIP",
           payload.isEmpty == false,
           isPlausibleGeoIPPayload(payload) == false {
            issues.append(.init(
                severity: .warning,
                title: "GEOIP 规则可疑",
                detail: "第 \(rule.index) 条 GEOIP 的 payload 通常应为国家/地区代码、LAN 或 PRIVATE：\(payload)。"
            ))
        }

        if type == "IP-ASN",
           payload.isEmpty == false,
           isValidASNRulePayload(payload) == false {
            issues.append(.init(
                severity: .warning,
                title: "IP-ASN 规则可疑",
                detail: "第 \(rule.index) 条 IP-ASN 的 payload 应为 1...4294967295 的 ASN 数字：\(payload)。"
            ))
        }

        if ["PROCESS-NAME", "PROCESS-NAME-REGEX"].contains(type),
           payload.isEmpty == false,
           isPlausibleProcessNamePayload(payload) == false {
            issues.append(.init(
                severity: .warning,
                title: "进程名称规则可疑",
                detail: "第 \(rule.index) 条 \(type) 的 payload 看起来像路径；PROCESS-NAME 通常只写可执行文件名。"
            ))
        }

        if type == "PROCESS-PATH",
           payload.isEmpty == false,
           isPlausibleProcessPathPayload(payload) == false {
            issues.append(.init(
                severity: .warning,
                title: "进程路径规则可疑",
                detail: "第 \(rule.index) 条 PROCESS-PATH 的 payload 通常应为绝对路径：\(payload)。"
            ))
        }

        if type == "NETWORK",
           payload.isEmpty == false,
           ["tcp", "udp"].contains(payload.lowercased()) == false {
            issues.append(.init(
                severity: .warning,
                title: "NETWORK 规则可疑",
                detail: "第 \(rule.index) 条 NETWORK 的 payload 通常应为 tcp 或 udp：\(payload)。"
            ))
        }

        return issues
    }
}
