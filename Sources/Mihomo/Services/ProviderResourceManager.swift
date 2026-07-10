import Foundation

struct ProviderResourceDownloadResult: Hashable {
    var target: URL
    var backup: URL?
}

struct ProviderResourceRollbackResult: Hashable {
    var target: URL
    var restoredFrom: URL
    var replacedBackup: URL?
}

struct ProviderResourceRefreshResult: Hashable {
    var target: URL
    var size: Int64
}

struct ProviderResourceManager {
    var runtimeDirectory: URL = AppPaths.runtimeDirectory
    var backupsDirectory: URL = AppPaths.providerBackupsDirectory

    func download(_ provider: ProviderItem) async throws -> ProviderResourceDownloadResult {
        guard let remote = provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              remote.isEmpty == false,
              let url = URL(string: remote)
        else {
            throw providerResourceError("Provider 没有可下载的 URL。")
        }

        let target = try targetURL(for: provider)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mihomo", forHTTPHeaderField: "User-Agent")
        let (downloaded, response) = try await NetworkClient.download(for: request)
        defer { try? FileManager.default.removeItem(at: downloaded) }

        if let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) == false {
            throw providerResourceError(HTTPURLResponse.localizedString(forStatusCode: http.statusCode), code: http.statusCode)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: downloaded.path)
        if (attributes[.size] as? NSNumber)?.int64Value == 0 {
            throw providerResourceError("下载结果为空，已保留当前 Provider 文件。")
        }

        let backup = try backupExistingResource(at: target, provider: provider)
        try replaceTarget(at: target, with: downloaded, rollbackBackup: backup)
        return ProviderResourceDownloadResult(target: target, backup: backup)
    }

    func rollback(_ provider: ProviderItem, from backup: URL) throws -> ProviderResourceRollbackResult {
        guard FileManager.default.fileExists(atPath: backup.path) else {
            throw providerResourceError("回滚文件不存在：\(backup.path)")
        }

        let target = try targetURL(for: provider)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let replacedBackup = try backupExistingResource(at: target, provider: provider)
        try replaceTarget(at: target, with: backup, rollbackBackup: replacedBackup)
        return ProviderResourceRollbackResult(target: target, restoredFrom: backup, replacedBackup: replacedBackup)
    }

    func refreshLocal(_ provider: ProviderItem) throws -> ProviderResourceRefreshResult {
        let target = try targetURL(for: provider)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw providerResourceError("本地 Provider 文件不存在：\(target.path)")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            throw providerResourceError("本地 Provider 文件为空：\(target.path)")
        }
        _ = try Data(contentsOf: target, options: [.mappedIfSafe])
        return ProviderResourceRefreshResult(target: target, size: size)
    }

    func targetURL(for provider: ProviderItem) throws -> URL {
        let rawPath = provider.path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDirectory = provider.kind == "Proxy" ? "proxy_providers" : "rule_providers"
        let fallbackName = Self.safeResourceFileName(provider.name, pathExtension: "yaml")
        let value = rawPath?.isEmpty == false ? rawPath! : "\(fallbackDirectory)/\(fallbackName)"
        if value.hasPrefix("/") {
            throw providerResourceError("Provider path 不能使用绝对路径：\(value)")
        }

        let components = value
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { $0.isEmpty == false && $0 != "." }
        guard components.contains("..") == false else {
            throw providerResourceError("Provider path 不能包含 ..：\(value)")
        }

        let runtimeRoot = runtimeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var target = runtimeRoot
        for component in components {
            target.appendPathComponent(component)
            let resolvedComponent = target.standardizedFileURL.resolvingSymlinksInPath()
            guard Self.isContained(resolvedComponent, in: runtimeRoot) else {
                throw providerResourceError("Provider path 必须位于 Runtime 目录内：\(value)")
            }
        }
        let resolvedTarget = target.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isContained(resolvedTarget, in: runtimeRoot) else {
            throw providerResourceError("Provider path 必须位于 Runtime 目录内：\(value)")
        }
        return target.standardizedFileURL
    }

    func backupExistingResource(at target: URL, provider: ProviderItem, date: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }

        let backup = backupURL(for: target, provider: provider, date: date)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
        try FileManager.default.copyItem(at: target, to: backup)
        return backup
    }

    private func replaceTarget(at target: URL, with source: URL, rollbackBackup: URL?) throws {
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            if let rollbackBackup, FileManager.default.fileExists(atPath: rollbackBackup.path) {
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: rollbackBackup, to: target)
            }
            throw error
        }
    }

    private func backupURL(for target: URL, provider: ProviderItem, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)
        let targetBase = target.deletingPathExtension().lastPathComponent
        let pathExtension = target.pathExtension.isEmpty ? "yaml" : target.pathExtension
        let name = [
            stamp,
            Self.safePathComponent(provider.kind),
            Self.safePathComponent(provider.name),
            Self.safePathComponent(targetBase),
            UUID().uuidString.prefix(8).description
        ].joined(separator: "-")

        return backupsDirectory
            .appendingPathComponent(Self.safePathComponent(provider.kind), isDirectory: true)
            .appendingPathComponent(Self.safePathComponent(provider.name), isDirectory: true)
            .appendingPathComponent("\(name).\(pathExtension)")
    }

    static func safeResourceFileName(_ value: String, pathExtension: String) -> String {
        let base = safePathComponent(value)
        return base.hasSuffix(".\(pathExtension)") ? base : "\(base).\(pathExtension)"
    }

    static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let base = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "_"
        }.joined()
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return trimmed.isEmpty ? "provider" : trimmed
    }

    private static func isContained(_ url: URL, in directory: URL) -> Bool {
        let root = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func providerResourceError(_ message: String, code: Int = 1) -> NSError {
        NSError(domain: "ProviderResource", code: code, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
