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

enum ConfigFragmentSource: String, Codable, CaseIterable, Hashable {
    case local
    case remote

    var title: String {
        switch self {
        case .local: return "本地"
        case .remote: return "远程"
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
    var appliesGlobally = true
    var profileIDs: [UUID] = []
    var source: ConfigFragmentSource = .local
    var location = ""
    var certificateFingerprint: String?

    var isRemote: Bool { source == .remote }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case enabled
        case content
        case updatedAt
        case appliesGlobally
        case profileIDs
        case source
        case location
        case certificateFingerprint
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: ConfigFragmentKind,
        enabled: Bool,
        content: String,
        updatedAt: Date = Date(),
        appliesGlobally: Bool = true,
        profileIDs: [UUID] = [],
        source: ConfigFragmentSource = .local,
        location: String = "",
        certificateFingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.content = content
        self.updatedAt = updatedAt
        self.appliesGlobally = appliesGlobally
        self.profileIDs = profileIDs
        self.source = source
        self.location = location
        self.certificateFingerprint = certificateFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ConfigFragmentKind.self, forKey: .kind)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        content = try container.decode(String.self, forKey: .content)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        appliesGlobally = try container.decodeIfPresent(Bool.self, forKey: .appliesGlobally) ?? true
        profileIDs = try container.decodeIfPresent([UUID].self, forKey: .profileIDs) ?? []
        source = try container.decodeIfPresent(ConfigFragmentSource.self, forKey: .source) ?? .local
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        certificateFingerprint = try container.decodeIfPresent(String.self, forKey: .certificateFingerprint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(content, forKey: .content)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(appliesGlobally, forKey: .appliesGlobally)
        try container.encode(profileIDs, forKey: .profileIDs)
        try container.encode(source, forKey: .source)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(certificateFingerprint, forKey: .certificateFingerprint)
    }

    func applies(to profileID: UUID) -> Bool {
        enabled && (appliesGlobally || profileIDs.contains(profileID))
    }
}

struct ConfigFragmentEditorRoute: Codable, Hashable {
    var fragmentID: UUID?
    var windowID: UUID

    static func editing(_ fragmentID: UUID) -> Self {
        Self(fragmentID: fragmentID, windowID: fragmentID)
    }

    static func creating() -> Self {
        Self(fragmentID: nil, windowID: UUID())
    }
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
    var usesAppDefault: Bool
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
    var hidden: Bool = false
    var icon: String? = nil
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
    var available: Bool? = nil
}

struct ProxyGroup: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var type: String
    var now: String
    var all: [ProxyNode]
    var icon: String?
    var hidden: Bool = false
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

struct PolicyTrafficSample: Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var policy: String
    var process: String = "未知进程"
    var host: String = "未知主机"
    var uploadBytes: Int64
    var downloadBytes: Int64
}

struct PolicyTrafficTotals: Identifiable, Hashable {
    var policy: String
    var uploadBytes: Int64
    var downloadBytes: Int64

    var id: String { policy }
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
