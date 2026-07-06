import Foundation

public enum MihomoHelperConstants {
    public static let appBundleIdentifier = "dev.codex.Mihomo"
    public static let machServiceName = "dev.codex.Mihomo.Helper"
    public static let daemonPlistName = "dev.codex.Mihomo.Helper.plist"
    public static let helperExecutableName = "MihomoHelper"
    public static let coreLaunchDaemonLabel = "dev.codex.Mihomo.core"

    public static var coreLaunchDaemonPlistPath: String {
        "/Library/LaunchDaemons/\(coreLaunchDaemonLabel).plist"
    }
}

@objc(MihomoHelperXPCProtocol)
public protocol MihomoHelperXPCProtocol {
    func helperVersion(withReply reply: @escaping (NSDictionary) -> Void)

    func validateConfig(
        mihomoPath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func prepareAndStartCore(
        mihomoPath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        logPath: NSString,
        proxySnapshotPath: NSString,
        dnsSnapshotPath: NSString,
        tunSnapshotPath: NSString,
        autoSetDNS: Bool,
        dnsServers: NSArray,
        captureTun: Bool,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func stopCore(
        restoreDNS: Bool,
        restoreTun: Bool,
        proxySnapshotPath: NSString,
        dnsSnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func installCoreLaunchDaemon(
        corePath: NSString,
        configPath: NSString,
        workDirectory: NSString,
        logPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func uninstallCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void)
    func startCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void)
    func stopCoreLaunchDaemon(withReply reply: @escaping (NSDictionary) -> Void)

    func setSystemProxy(
        host: NSString,
        mixedPort: Int32,
        socksPort: Int32,
        proxySnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func restoreSystemProxy(
        proxySnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func setSystemDNS(
        servers: NSArray,
        dnsSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func restoreSystemDNS(
        dnsSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func captureTunSnapshot(
        proxySnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func restoreTunSnapshot(
        proxySnapshotPath: NSString,
        tunSnapshotPath: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )

    func verifyPrivileges(withReply reply: @escaping (NSDictionary) -> Void)
}
