import Foundation
import JavaScriptCore
import Yams

enum ConfigFragmentAnalysisSeverity: String, Hashable {
    case info
    case warning
    case error
}

struct ConfigFragmentAnalysisIssue: Identifiable, Hashable {
    var id: String { "\(severity.rawValue)|\(line ?? 0)|\(column ?? 0)|\(message)" }
    var severity: ConfigFragmentAnalysisSeverity
    var message: String
    var line: Int?
    var column: Int?

    var locationText: String? {
        guard let line else { return nil }
        if let column, column > 0 {
            return "第 \(line) 行，第 \(column) 列"
        }
        return "第 \(line) 行"
    }
}

struct ConfigFragmentOverviewReport: Hashable {
    var lineCount: Int
    var byteCount: Int
    var topLevelKeys: [String]
    var issues: [ConfigFragmentAnalysisIssue]

    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }

    var statusTitle: String {
        if errorCount > 0 { return "发现 \(errorCount) 个错误" }
        if warningCount > 0 { return "发现 \(warningCount) 个警告" }
        return "语法检查通过"
    }
}

struct ConfigFragmentAnalyzer {
    func analyze(_ fragment: ConfigFragment) -> ConfigFragmentOverviewReport {
        let content = fragment.content
        var report = ConfigFragmentOverviewReport(
            lineCount: max(content.components(separatedBy: .newlines).count, 1),
            byteCount: content.lengthOfBytes(using: .utf8),
            topLevelKeys: [],
            issues: []
        )

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report.issues.append(.init(severity: .error, message: "覆写内容不能为空", line: 1, column: 1))
            return report
        }

        switch fragment.kind {
        case .yaml:
            analyzeYAML(content, report: &report)
        case .javascript:
            analyzeJavaScript(content, report: &report)
        }
        return report
    }

    private func analyzeYAML(_ content: String, report: inout ConfigFragmentOverviewReport) {
        if report.byteCount > 2 * 1024 * 1024 {
            report.issues.append(.init(severity: .error, message: "YAML 覆写不能超过 2 MiB", line: nil, column: nil))
        }

        do {
            guard let loaded = try Yams.load(yaml: content) else {
                report.issues.append(.init(severity: .error, message: "YAML 内容为空", line: 1, column: 1))
                return
            }
            guard let root = normalizeYAMLValue(loaded) as? [String: Any] else {
                report.issues.append(.init(severity: .error, message: "YAML 覆写必须使用顶层映射", line: 1, column: 1))
                return
            }
            report.topLevelKeys = root.keys.sorted()
            if root.isEmpty {
                report.issues.append(.init(severity: .warning, message: "顶层映射为空，不会改变运行配置", line: 1, column: 1))
            }
            validateSnifferRules(root: root, content: content, report: &report)
        } catch let error as YamlError {
            report.issues.append(yamlIssue(error))
        } catch {
            report.issues.append(.init(severity: .error, message: "YAML 解析失败：\(error.localizedDescription)", line: nil, column: nil))
        }
    }

    private func analyzeJavaScript(_ content: String, report: inout ConfigFragmentOverviewReport) {
        if report.byteCount > JSOverrideRunner.maximumFragmentBytes {
            report.issues.append(.init(
                severity: .error,
                message: "JavaScript 覆写不能超过 \(JSOverrideRunner.maximumFragmentBytes / 1024) KiB",
                line: nil,
                column: nil
            ))
        }

        let context = JSContext()
        guard let context, let script = JSStringCreateWithUTF8CString(content) else {
            report.issues.append(.init(severity: .error, message: "无法创建 JavaScript 语法检查器", line: nil, column: nil))
            return
        }
        defer { JSStringRelease(script) }

        var exception: JSValueRef?
        let valid = JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception)
        if valid == false, let exception,
           let value = JSValue(jsValueRef: exception, in: context) {
            let message = value.toString() ?? "JavaScript 语法错误"
            let line = positiveInt(value.forProperty("line"))
            let column = positiveInt(value.forProperty("column"))
            report.issues.append(.init(severity: .error, message: message, line: line, column: column))
            return
        }

        let transformPattern = #"(?m)(function\s+transform\s*\(|(?:const|let|var)\s+transform\s*=|\btransform\s*=\s*(?:async\s*)?(?:function|\())"#
        if content.range(of: transformPattern, options: .regularExpression) == nil {
            report.issues.append(.init(
                severity: .error,
                message: "未定义 transform(config)，运行时无法应用此覆写",
                line: firstNonEmptyLine(in: content),
                column: 1
            ))
        }
    }

    private func validateSnifferRules(
        root: [String: Any],
        content: String,
        report: inout ConfigFragmentOverviewReport
    ) {
        guard let sniffer = root["sniffer"] as? [String: Any] else { return }
        let validator = ProfileQualityAnalyzer()

        for key in ["force-domain", "skip-domain"] {
            for domain in stringArray(sniffer[key]) where validator.isValidSnifferDomainToken(domain) == false {
                report.issues.append(.init(
                    severity: .warning,
                    message: "域名 \(domain) 不应包含协议、路径或空白字符",
                    line: lineNumber(of: domain, in: content),
                    column: 1
                ))
            }
        }

        for key in ["skip-dst-address", "skip-src-address"] {
            for address in stringArray(sniffer[key]) where validator.isValidSnifferAddressToken(address) == false {
                report.issues.append(.init(
                    severity: .warning,
                    message: "地址 \(address) 应为 IPv4、IPv6 或 CIDR",
                    line: lineNumber(of: address, in: content),
                    column: 1
                ))
            }
        }

        if let protocols = sniffer["sniff"] as? [String: Any] {
            for protocolValue in protocols.values {
                guard let configuration = protocolValue as? [String: Any] else { continue }
                for port in stringArray(configuration["ports"])
                where validator.isValidSnifferPortToken(port) == false {
                    report.issues.append(.init(
                        severity: .warning,
                        message: "端口 \(port) 不是 1...65535 的整数或 start-end 范围",
                        line: lineNumber(of: port, in: content),
                        column: 1
                    ))
                }
            }
        }
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [Any] {
            return values.map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard let value else { return [] }
        return [String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private func lineNumber(of token: String, in content: String) -> Int? {
        content.components(separatedBy: .newlines).firstIndex { line in
            line.localizedCaseInsensitiveContains(token)
        }.map { $0 + 1 }
    }

    private func positiveInt(_ value: JSValue?) -> Int? {
        guard let value else { return nil }
        let number = Int(value.toInt32())
        return number > 0 ? number : nil
    }

    private func firstNonEmptyLine(in content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        return (lines.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false } ?? 0) + 1
    }

    private func yamlIssue(_ error: YamlError) -> ConfigFragmentAnalysisIssue {
        switch error {
        case let .scanner(_, problem, mark, _),
             let .parser(_, problem, mark, _),
             let .composer(_, problem, mark, _):
            return .init(severity: .error, message: "YAML 语法错误：\(problem)", line: mark.line, column: mark.column)
        case let .reader(problem, offset, _, yaml):
            let location = offset.flatMap { lineAndColumn(in: yaml, offset: $0) }
            return .init(
                severity: .error,
                message: "YAML 读取错误：\(problem)",
                line: location?.line,
                column: location?.column
            )
        case .duplicatedKeysInMapping:
            return .init(severity: .error, message: "YAML 顶层或嵌套映射包含重复键", line: nil, column: nil)
        default:
            return .init(severity: .error, message: "YAML 解析失败：\(error.description)", line: nil, column: nil)
        }
    }

    private func lineAndColumn(in text: String, offset: Int) -> (line: Int, column: Int)? {
        guard offset >= 0, offset <= text.count,
              let index = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex)
        else { return nil }
        let prefix = text[..<index]
        let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let lastNewline = prefix.lastIndex(of: "\n")
        let columnStart = lastNewline.map { text.index(after: $0) } ?? text.startIndex
        let column = text.distance(from: columnStart, to: index) + 1
        return (line, column)
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
            return array.map(normalizeYAMLValue)
        }
        return value
    }
}
