import Foundation

struct AppUpdateManifest: Codable, Hashable {
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

struct AppUpdateSignature: Codable, Hashable {
    var algorithm: String
    var publicKey: String
    var value: String
}

struct AppUpdateCheckResult: Hashable {
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
