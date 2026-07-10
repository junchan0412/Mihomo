import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case networkSecurity
    case activity
    case policies
    case profiles
    case rules
    case resources
    case advanced
    case logs
    case diagnostics
    case settings

    var id: String { rawValue }

    static var sidebarSections: [AppSection] {
        allCases.filter { section in
            section != .settings && section != .logs
        }
    }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .networkSecurity: return "网络安全"
        case .activity: return "活动"
        case .policies: return "策略"
        case .profiles: return "配置"
        case .rules: return "规则"
        case .resources: return "资源"
        case .advanced: return "高级"
        case .logs: return "日志"
        case .diagnostics: return "诊断"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .networkSecurity: return "shield.lefthalf.filled"
        case .activity: return "waveform.path.ecg"
        case .policies: return "switch.2"
        case .profiles: return "doc.text"
        case .rules: return "list.bullet.rectangle"
        case .resources: return "shippingbox"
        case .advanced: return "wrench.and.screwdriver"
        case .logs: return "terminal"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}

enum ProfileSource: String, Codable, CaseIterable {
    case local
    case remote
}

enum CoreSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case managed
    case bundled
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .managed: return "托管远程"
        case .bundled: return "随包内置"
        case .local: return "本地外部"
        }
    }

    var detail: String {
        switch self {
        case .managed: return "由应用下载并维护 mihomo core"
        case .bundled: return "使用 App 包内附带的 mihomo core"
        case .local: return "使用用户指定的本地可执行文件"
        }
    }
}

enum NetworkTakeoverKind: String, CaseIterable, Identifiable, Hashable {
    case systemProxy
    case systemDNS
    case tun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemProxy: return "系统代理"
        case .systemDNS: return "系统 DNS"
        case .tun: return "TUN / 路由"
        }
    }

    var systemImage: String {
        switch self {
        case .systemProxy: return "network"
        case .systemDNS: return "globe"
        case .tun: return "lock.shield"
        }
    }
}

enum NetworkTakeoverHealth: String, Hashable {
    case ok
    case warning
    case inactive
    case failed
}

struct NetworkTakeoverState: Identifiable, Hashable {
    var id: NetworkTakeoverKind { kind }
    var kind: NetworkTakeoverKind
    var desiredState: String
    var actualState: String
    var lastOperation: String
    var recoveryAction: String
    var health: NetworkTakeoverHealth
}

enum NetworkSecuritySnapshotKind: String, Hashable {
    case systemProxy
    case systemDNS
    case tunRecovery

    var title: String {
        switch self {
        case .systemProxy: return "系统代理快照"
        case .systemDNS: return "系统 DNS 快照"
        case .tunRecovery: return "TUN 回滚快照"
        }
    }

    var systemImage: String {
        switch self {
        case .systemProxy: return "network"
        case .systemDNS: return "globe"
        case .tunRecovery: return "lock.shield"
        }
    }
}

struct NetworkSecuritySnapshotItem: Identifiable, Hashable {
    var id: NetworkSecuritySnapshotKind { kind }
    var kind: NetworkSecuritySnapshotKind
    var path: String
    var createdAt: Date?
    var status: String
    var detail: String
    var health: NetworkTakeoverHealth
}

struct NetworkSecuritySnapshotPaths: Hashable {
    var systemProxy: String
    var systemDNS: String
    var tunRecovery: String
}

struct ProfileItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var source: ProfileSource
    var location: String
    var fileName: String
    var updatedAt: Date
    var uploadUsed: Int64?
    var downloadUsed: Int64?
    var total: Int64?
    var expireAt: Date?
    var certificateFingerprint: String?

    var isRemote: Bool { source == .remote }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case location
        case fileName
        case updatedAt
        case uploadUsed
        case downloadUsed
        case total
        case expireAt
        case certificateFingerprint
    }

    init(
        id: UUID,
        name: String,
        source: ProfileSource,
        location: String,
        fileName: String,
        updatedAt: Date,
        uploadUsed: Int64? = nil,
        downloadUsed: Int64? = nil,
        total: Int64? = nil,
        expireAt: Date? = nil,
        certificateFingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.location = location
        self.fileName = fileName
        self.updatedAt = updatedAt
        self.uploadUsed = uploadUsed
        self.downloadUsed = downloadUsed
        self.total = total
        self.expireAt = expireAt
        self.certificateFingerprint = certificateFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(ProfileSource.self, forKey: .source)
        location = try container.decode(String.self, forKey: .location)
        fileName = try container.decode(String.self, forKey: .fileName)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        uploadUsed = try container.decodeIfPresent(Int64.self, forKey: .uploadUsed)
        downloadUsed = try container.decodeIfPresent(Int64.self, forKey: .downloadUsed)
        total = try container.decodeIfPresent(Int64.self, forKey: .total)
        expireAt = try container.decodeIfPresent(Date.self, forKey: .expireAt)
        certificateFingerprint = try container.decodeIfPresent(String.self, forKey: .certificateFingerprint)
    }
}
