import Foundation

enum SoftwareUpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case downloading(SoftwareUpdateDownloadProgress)
    case verifying
    case preparingNetwork
    case preparingHelper
    case installing
    case readyToRestart
    case failed
    case cancelled

    var isInProgress: Bool {
        switch self {
        case .checking, .downloading, .verifying, .preparingNetwork, .preparingHelper, .installing:
            return true
        case .idle, .readyToRestart, .failed, .cancelled:
            return false
        }
    }

    var isCancellable: Bool {
        switch self {
        case .checking, .downloading, .verifying:
            return true
        case .idle, .preparingNetwork, .preparingHelper, .installing, .readyToRestart, .failed, .cancelled:
            return false
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "软件更新"
        case .checking:
            return "正在检查更新"
        case .downloading:
            return "正在下载更新"
        case .verifying:
            return "正在验证更新"
        case .preparingNetwork:
            return "正在恢复网络设置"
        case .preparingHelper:
            return "正在准备安装"
        case .installing:
            return "正在重新启动"
        case .readyToRestart:
            return "更新已准备就绪"
        case .failed:
            return "更新未完成"
        case .cancelled:
            return "更新已取消"
        }
    }

    var cancellationTitle: String? {
        switch self {
        case .checking:
            return "取消检查"
        case .downloading:
            return "取消下载"
        case .verifying:
            return "取消验证"
        case .idle, .preparingNetwork, .preparingHelper, .installing, .readyToRestart, .failed, .cancelled:
            return nil
        }
    }
}

struct SoftwareUpdateDownloadProgress: Equatable, Sendable {
    var bytesReceived: Int64
    var totalBytes: Int64?
    var bytesPerSecond: Int64

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
    }

    var isIndeterminate: Bool {
        fractionCompleted == nil
    }

    var transferDescription: String {
        let received = Formatters.bytes(bytesReceived)
        if let totalBytes {
            return "\(received) / \(Formatters.bytes(totalBytes))"
        }
        return received
    }
}

struct AppUpdateManifest: Codable, Hashable, Sendable {
    var version: String
    var build: String?
    var url: String
    var sha256: String
    var notes: String?
    var minimumSystemVersion: String?
    var bundleIdentifier: String?
    var signingIdentifier: String?
    var helperSigningIdentifier: String?
    var signingMode: String?
    var teamIdentifier: String?
    var appCDHash: String?
    var helperCDHash: String?
    var publishedAt: Date?
    var signature: AppUpdateSignature?
}

struct AppUpdateSignature: Codable, Hashable, Sendable {
    var algorithm: String
    var publicKey: String
    var value: String
}

struct AppUpdateCheckResult: Hashable, Sendable {
    var manifest: AppUpdateManifest
    var manifestURL: URL
    var isNewer: Bool
    var currentVersion: String
    var currentBuild: String
}

struct PreparedUpdatePackage {
    var candidate: URL
    var installScript: URL
    var tempRoot: URL
}
