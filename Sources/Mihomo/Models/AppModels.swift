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
        case .overview: return "Overview"
        case .activity: return "Activity"
        case .policies: return "Policies"
        case .profiles: return "Profiles"
        case .logs: return "Logs"
        case .diagnostics: return "Diagnostics"
        case .settings: return "Settings"
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

    static let `default` = AppSettings(
        mihomoPath: "",
        activeProfileID: nil,
        controllerHost: "127.0.0.1",
        controllerPort: 9090,
        mixedPort: 7890,
        socksPort: 0,
        allowLAN: false,
        tunEnabled: false,
        logLevel: "info",
        autoStartCore: false,
        closeConnectionsOnPolicyChange: true
    )
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
