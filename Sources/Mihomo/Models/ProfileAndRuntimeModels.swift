import Foundation

enum ConfigFragmentKind: String, Codable, CaseIterable, Hashable {
    case yaml
    case javascript

    var title: String {
        switch self {
        case .yaml: return "YAML"
        case .javascript: return "JavaScript"
        }
    }
}

struct ConfigFragment: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: ConfigFragmentKind
    var enabled: Bool
    var content: String
    var updatedAt = Date()
}

struct RuleItem: Identifiable, Hashable {
    var id: String { "\(index)-\(content)" }
    var index: Int
    var content: String
    var disabled: Bool
    var hitCount: Int = 0
}

struct ProviderItem: Identifiable, Hashable {
    var id: String { "\(kind)-\(name)" }
    var kind: String
    var name: String
    var detail: String
    var providerType: String = ""
    var remoteURL: String?
    var path: String?
    var behavior: String?
    var interval: Int?
    var ruleCount: Int = 0
    var hitCount: Int = 0
    var memberNames: [String] = []
}

struct ProviderUpdateRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var providerName: String
    var providerKind: String
    var action: String
    var succeeded: Bool
    var targetPath: String
    var message: String
    var backupPath: String?
    var restoredFromPath: String?
}

struct ProfileStats: Hashable {
    var lineCount: Int = 0
    var fileSize: Int = 0
    var policyGroupCount: Int = 0
    var proxyCount: Int = 0
    var ruleCount: Int = 0
    var proxyProviderCount: Int = 0
    var ruleProviderCount: Int = 0
    var errorMessage: String?
}

enum ProfileQualitySeverity: String, Hashable {
    case info
    case warning
    case error

    var title: String {
        switch self {
        case .info: return "提示"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }
}

struct ProfileQualityIssue: Identifiable, Hashable {
    var id = UUID()
    var severity: ProfileQualitySeverity
    var title: String
    var detail: String
}

struct RuntimeInspectorItem: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var value: String
    var detail: String
}

struct RuntimeConfigSourceItem: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var source: String
    var value: String
    var detail: String
    var isAppManaged: Bool
}

struct ConfigDiffLayer: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var changed: Bool
    var summary: String
}

struct ProfileQualityReport: Hashable {
    var score: Int
    var headline: String
    var issues: [ProfileQualityIssue]
    var runtimeItems: [RuntimeInspectorItem]
    var sourceItems: [RuntimeConfigSourceItem]
    var diffLayers: [ConfigDiffLayer]
    var migrationLog: [String]
    var generatedConfig: String
}

extension ProfileQualityReport {
    static let empty = ProfileQualityReport(
        score: 0,
        headline: "未选择配置",
        issues: [],
        runtimeItems: [],
        sourceItems: [],
        diffLayers: [],
        migrationLog: [],
        generatedConfig: ""
    )
}

struct EditablePolicyGroup: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var proxies: [String]
    var uses: [String]
}

struct EditableProfileRule: Identifiable, Hashable {
    var id: String { "\(index)-\(content)" }
    var index: Int
    var type: String
    var payload: String
    var target: String
    var options: [String]

    var content: String {
        if payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ([type, target] + options).joined(separator: ",")
        }
        return ([type, payload, target] + options).joined(separator: ",")
    }
}

struct ProfileStructureSnapshot: Hashable {
    var groups: [EditablePolicyGroup]
    var rules: [EditableProfileRule]
    var proxyNames: [String]
}

struct ProxyNode: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var delay: Int?
}

struct ProxyGroup: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var now: String
    var all: [ProxyNode]
    var icon: String?
}

struct PolicyTableRow: Identifiable, Hashable {
    var group: ProxyGroup
    var node: ProxyNode

    var id: String { "\(group.name)\u{1f}\(node.name)" }
}

struct ConnectionItem: Identifiable, Hashable {
    var id: String
    var host: String
    var process: String
    var processPath: String = ""
    var network: String
    var metadataType: String = ""
    var rule: String
    var ruleType: String = ""
    var rulePayload: String = ""
    var chain: String
    var sourceIP: String = ""
    var sourcePort: String = ""
    var destinationIP: String = ""
    var destinationPort: String = ""
    var remoteDestination: String = ""
    var upload: Int64
    var download: Int64
    var start: Date?
}

struct TrafficSample: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var uploadRate: Int64
    var downloadRate: Int64
}

struct LogEntry: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var level: String
    var message: String
}

enum ProfileRefreshJobState: String, Hashable {
    case pending
    case running
    case succeeded
    case failed

    var title: String {
        switch self {
        case .pending: return "等待"
        case .running: return "运行中"
        case .succeeded: return "成功"
        case .failed: return "失败"
        }
    }
}

struct ProfileRefreshJob: Identifiable, Hashable {
    var id = UUID()
    var profileID: UUID
    var profileName: String
    var state: ProfileRefreshJobState
    var message: String
    var startedAt: Date?
    var finishedAt: Date?
}

enum DiagnosticState: String, Hashable {
    case ok
    case warning
    case failed
}

struct DiagnosticResult: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var state: DiagnosticState
}
