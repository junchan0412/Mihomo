import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case activity
    case policies
    case profiles
    case logs
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .activity: return "活动"
        case .policies: return "策略"
        case .profiles: return "配置"
        case .logs: return "日志"
        case .diagnostics: return "诊断"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .activity: return "waveform.path.ecg"
        case .policies: return "switch.2"
        case .profiles: return "doc.text"
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

    var isRemote: Bool { source == .remote }
}

struct AppSettings: Codable, Hashable {
    var mihomoPath: String
    var activeProfileID: UUID?
    var controllerHost: String
    var controllerPort: Int
    var mixedPort: Int
    var socksPort: Int
    var allowLAN: Bool
    var tunEnabled: Bool
    var logLevel: String
    var autoStartCore: Bool
    var closeConnectionsOnPolicyChange: Bool
    var restartCoreOnCrash: Bool
    var maxCrashRestarts: Int
    var autoRefreshProfiles: Bool
    var profileRefreshIntervalHours: Int
    var lightweightMode: Bool
    var restoreSystemProxyOnQuit: Bool
    var delayTestURL: String
    var launchAtLogin: Bool
    var restoreTunOnStop: Bool

    static let `default` = AppSettings()

    init(
        mihomoPath: String = "",
        activeProfileID: UUID? = nil,
        controllerHost: String = "127.0.0.1",
        controllerPort: Int = 9090,
        mixedPort: Int = 7890,
        socksPort: Int = 0,
        allowLAN: Bool = false,
        tunEnabled: Bool = false,
        logLevel: String = "info",
        autoStartCore: Bool = false,
        closeConnectionsOnPolicyChange: Bool = true,
        restartCoreOnCrash: Bool = true,
        maxCrashRestarts: Int = 3,
        autoRefreshProfiles: Bool = false,
        profileRefreshIntervalHours: Int = 24,
        lightweightMode: Bool = false,
        restoreSystemProxyOnQuit: Bool = true,
        delayTestURL: String = "https://www.gstatic.com/generate_204",
        launchAtLogin: Bool = false,
        restoreTunOnStop: Bool = true
    ) {
        self.mihomoPath = mihomoPath
        self.activeProfileID = activeProfileID
        self.controllerHost = controllerHost
        self.controllerPort = controllerPort
        self.mixedPort = mixedPort
        self.socksPort = socksPort
        self.allowLAN = allowLAN
        self.tunEnabled = tunEnabled
        self.logLevel = logLevel
        self.autoStartCore = autoStartCore
        self.closeConnectionsOnPolicyChange = closeConnectionsOnPolicyChange
        self.restartCoreOnCrash = restartCoreOnCrash
        self.maxCrashRestarts = maxCrashRestarts
        self.autoRefreshProfiles = autoRefreshProfiles
        self.profileRefreshIntervalHours = profileRefreshIntervalHours
        self.lightweightMode = lightweightMode
        self.restoreSystemProxyOnQuit = restoreSystemProxyOnQuit
        self.delayTestURL = delayTestURL
        self.launchAtLogin = launchAtLogin
        self.restoreTunOnStop = restoreTunOnStop
    }

    private enum CodingKeys: String, CodingKey {
        case mihomoPath
        case activeProfileID
        case controllerHost
        case controllerPort
        case mixedPort
        case socksPort
        case allowLAN
        case tunEnabled
        case logLevel
        case autoStartCore
        case closeConnectionsOnPolicyChange
        case restartCoreOnCrash
        case maxCrashRestarts
        case autoRefreshProfiles
        case profileRefreshIntervalHours
        case lightweightMode
        case restoreSystemProxyOnQuit
        case delayTestURL
        case launchAtLogin
        case restoreTunOnStop
    }

    init(from decoder: Decoder) throws {
        let fallback = AppSettings.default
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mihomoPath = try container.decodeIfPresent(String.self, forKey: .mihomoPath) ?? fallback.mihomoPath
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID) ?? fallback.activeProfileID
        controllerHost = try container.decodeIfPresent(String.self, forKey: .controllerHost) ?? fallback.controllerHost
        controllerPort = try container.decodeIfPresent(Int.self, forKey: .controllerPort) ?? fallback.controllerPort
        mixedPort = try container.decodeIfPresent(Int.self, forKey: .mixedPort) ?? fallback.mixedPort
        socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? fallback.socksPort
        allowLAN = try container.decodeIfPresent(Bool.self, forKey: .allowLAN) ?? fallback.allowLAN
        tunEnabled = try container.decodeIfPresent(Bool.self, forKey: .tunEnabled) ?? fallback.tunEnabled
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? fallback.logLevel
        autoStartCore = try container.decodeIfPresent(Bool.self, forKey: .autoStartCore) ?? fallback.autoStartCore
        closeConnectionsOnPolicyChange = try container.decodeIfPresent(Bool.self, forKey: .closeConnectionsOnPolicyChange) ?? fallback.closeConnectionsOnPolicyChange
        restartCoreOnCrash = try container.decodeIfPresent(Bool.self, forKey: .restartCoreOnCrash) ?? fallback.restartCoreOnCrash
        maxCrashRestarts = try container.decodeIfPresent(Int.self, forKey: .maxCrashRestarts) ?? fallback.maxCrashRestarts
        autoRefreshProfiles = try container.decodeIfPresent(Bool.self, forKey: .autoRefreshProfiles) ?? fallback.autoRefreshProfiles
        profileRefreshIntervalHours = try container.decodeIfPresent(Int.self, forKey: .profileRefreshIntervalHours) ?? fallback.profileRefreshIntervalHours
        lightweightMode = try container.decodeIfPresent(Bool.self, forKey: .lightweightMode) ?? fallback.lightweightMode
        restoreSystemProxyOnQuit = try container.decodeIfPresent(Bool.self, forKey: .restoreSystemProxyOnQuit) ?? fallback.restoreSystemProxyOnQuit
        delayTestURL = try container.decodeIfPresent(String.self, forKey: .delayTestURL) ?? fallback.delayTestURL
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        restoreTunOnStop = try container.decodeIfPresent(Bool.self, forKey: .restoreTunOnStop) ?? fallback.restoreTunOnStop
    }
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
    var network: String
    var rule: String
    var chain: String
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
