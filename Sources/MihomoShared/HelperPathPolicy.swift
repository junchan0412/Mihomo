import Foundation

public struct HelperCorePathSet: Hashable {
    public var mihomoPath: String
    public var configPath: String
    public var workDirectory: String
    public var logPath: String?
}

public struct HelperPathPolicyError: LocalizedError, Hashable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum HelperPathPolicy {
    public static let supportDirectoryName = "Mihomo"
    public static let runtimeDirectoryName = "Runtime"
    public static let coreDirectoryName = "Core"
    public static let logsDirectoryName = "Mihomo"
    public static let proxySnapshotFileName = "system-proxy-snapshot.json"
    public static let dnsSnapshotFileName = "system-dns-snapshot.json"
    public static let tunSnapshotFileName = "tun-recovery-snapshot.json"

    public static func validateCorePaths(
        mihomoPath: String,
        configPath: String,
        workDirectory: String,
        logPath: String?,
        appBundleURL: URL?,
        userHomeDirectory: URL
    ) throws -> HelperCorePathSet {
        let workURL = try absoluteURL(workDirectory, label: "workDirectory")
        let supportURL = try supportDirectory(fromRuntimeDirectory: workURL)
        try validateSupportDirectoryShape(supportURL, userHomeDirectory: userHomeDirectory)
        try validateContained(workURL, in: supportURL, label: "workDirectory")

        let configURL = try absoluteURL(configPath, label: "configPath")
        guard allowedConfigFileNames.contains(configURL.lastPathComponent) else {
            throw HelperPathPolicyError("configPath 文件名不在允许清单内：\(configURL.lastPathComponent)")
        }
        try validateContained(configURL, in: workURL, label: "configPath")

        let mihomoURL = try absoluteURL(mihomoPath, label: "mihomoPath")
        guard mihomoURL.lastPathComponent == "mihomo" else {
            throw HelperPathPolicyError("mihomoPath 文件名必须是 mihomo：\(mihomoURL.lastPathComponent)")
        }
        let allowedCoreRoots = coreRoots(supportDirectory: supportURL, appBundleURL: appBundleURL)
        guard try allowedCoreRoots.contains(where: { root in
            try isContained(mihomoURL, in: root)
        }) else {
            throw HelperPathPolicyError("mihomoPath 必须位于 App Support/Core 或 App bundle Resources/Core 内：\(mihomoPath)")
        }

        var checkedLogPath: String?
        if let logPath, logPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let logURL = try absoluteURL(logPath, label: "logPath")
            guard logURL.lastPathComponent == "mihomo-core.log" else {
                throw HelperPathPolicyError("logPath 文件名必须是 mihomo-core.log：\(logURL.lastPathComponent)")
            }
            let logsURL = logsDirectory(userHomeDirectory: userHomeDirectory)
            try validateContained(logURL, in: logsURL, label: "logPath")
            checkedLogPath = logURL.standardizedFileURL.path
        }

        return HelperCorePathSet(
            mihomoPath: mihomoURL.standardizedFileURL.path,
            configPath: configURL.standardizedFileURL.path,
            workDirectory: workURL.standardizedFileURL.path,
            logPath: checkedLogPath
        )
    }

    public static func validateProxySnapshotPath(_ path: String, userHomeDirectory: URL) throws -> String {
        try validateSnapshotPath(path, expectedFileName: proxySnapshotFileName, userHomeDirectory: userHomeDirectory)
    }

    public static func validateDNSSnapshotPath(_ path: String, userHomeDirectory: URL) throws -> String {
        try validateSnapshotPath(path, expectedFileName: dnsSnapshotFileName, userHomeDirectory: userHomeDirectory)
    }

    public static func validateTunSnapshotPath(_ path: String, userHomeDirectory: URL) throws -> String {
        try validateSnapshotPath(path, expectedFileName: tunSnapshotFileName, userHomeDirectory: userHomeDirectory)
    }

    private static func validateSnapshotPath(
        _ path: String,
        expectedFileName: String,
        userHomeDirectory: URL
    ) throws -> String {
        let url = try absoluteURL(path, label: expectedFileName)
        guard url.lastPathComponent == expectedFileName else {
            throw HelperPathPolicyError("snapshot 文件名必须是 \(expectedFileName)：\(url.lastPathComponent)")
        }
        let supportURL = url.deletingLastPathComponent().standardizedFileURL
        try validateSupportDirectoryShape(supportURL, userHomeDirectory: userHomeDirectory)
        try validateContained(url, in: supportURL, label: expectedFileName)
        return url.standardizedFileURL.path
    }

    private static func supportDirectory(fromRuntimeDirectory workURL: URL) throws -> URL {
        let runtimeURL = workURL.standardizedFileURL
        guard runtimeURL.lastPathComponent == runtimeDirectoryName else {
            throw HelperPathPolicyError("workDirectory 必须指向 Mihomo/Runtime：\(workURL.path)")
        }
        return runtimeURL.deletingLastPathComponent()
    }

    private static func logsDirectory(userHomeDirectory: URL) -> URL {
        userHomeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(logsDirectoryName, isDirectory: true)
            .standardizedFileURL
    }

    private static func validateSupportDirectoryShape(_ supportURL: URL, userHomeDirectory: URL) throws {
        let expectedSupportURL = userHomeDirectory
            .standardizedFileURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .standardizedFileURL
        guard supportURL.standardizedFileURL.path == expectedSupportURL.path else {
            throw HelperPathPolicyError("路径必须位于授权用户的 Library/Application Support/Mihomo：\(supportURL.path)")
        }
        guard try isContained(supportURL, in: userHomeDirectory) else {
            throw HelperPathPolicyError("App Support 目录不能通过符号链接离开授权用户目录：\(supportURL.path)")
        }
    }

    private static func coreRoots(supportDirectory: URL, appBundleURL: URL?) -> [URL] {
        var roots = [
            supportDirectory.appendingPathComponent(coreDirectoryName, isDirectory: true).standardizedFileURL
        ]
        if let appBundleURL {
            roots.append(
                appBundleURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(coreDirectoryName, isDirectory: true)
                    .standardizedFileURL
            )
        }
        return roots
    }

    private static func absoluteURL(_ path: String, label: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            throw HelperPathPolicyError("\(label) 必须是绝对路径：\(path)")
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    private static func validateContained(_ url: URL, in directory: URL, label: String) throws {
        guard try isContained(url, in: directory) else {
            throw HelperPathPolicyError("\(label) 必须位于允许目录内：\(url.path)")
        }
    }

    private static func isContained(_ url: URL, in directory: URL) throws -> Bool {
        let root = directory.standardizedFileURL
        let target = url.standardizedFileURL
        let rootPath = root.path
        let targetPath = target.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            return false
        }

        let relative = targetPath == rootPath ? "" : String(targetPath.dropFirst(rootPath.count + 1))
        var current = root.resolvingSymlinksInPath()
        let resolvedRoot = current.path
        for component in relative.split(separator: "/").map(String.init) {
            current.appendPathComponent(component)
            let resolved = current.standardizedFileURL.resolvingSymlinksInPath().path
            guard resolved == resolvedRoot || resolved.hasPrefix(resolvedRoot + "/") else {
                return false
            }
        }
        return true
    }

    private static let allowedConfigFileNames: Set<String> = [
        "config.yaml",
        "config.candidate.yaml",
        "config.previous.yaml"
    ]
}
