import CryptoKit
import Darwin
import Foundation
import Yams

struct ProviderResourceDownloadResult: Hashable {
    var target: URL
    var backup: URL?
    var validationSummary: String = ""
}

struct ProviderResourceRollbackResult: Hashable {
    var target: URL
    var restoredFrom: URL
    var replacedBackup: URL?
}

struct ProviderResourceRefreshResult: Hashable {
    var target: URL
    var size: Int64
    var validationSummary: String = ""
}

private struct ProviderResourceValidation {
    var entryCount: Int
    var sha256: String

    var summary: String {
        "校验通过：\(entryCount) 项，SHA-256 \(sha256.prefix(12))…"
    }
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
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        if size == 0 {
            throw providerResourceError("下载结果为空，已保留当前 Provider 文件。")
        }

        let validation = try validateResource(at: downloaded, provider: provider)
        let backup = try backupExistingResource(at: target, provider: provider)
        try replaceTarget(at: target, with: downloaded, rollbackBackup: backup)
        return ProviderResourceDownloadResult(
            target: target,
            backup: backup,
            validationSummary: "\(validation.summary)，大小 \(Formatters.bytes(size))"
        )
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
        let validation = try validateResource(at: target, provider: provider)
        return ProviderResourceRefreshResult(
            target: target,
            size: size,
            validationSummary: validation.summary
        )
    }

    func targetURL(for provider: ProviderItem) throws -> URL {
        let rawPath = provider.path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDirectory = ["Proxy", "Node"].contains(provider.kind) ? "proxy_providers" : "rule_providers"
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
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).staging")
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            try FileManager.default.copyItem(at: source, to: staging)
            try syncFile(at: staging)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(
                    target,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try FileManager.default.moveItem(at: staging, to: target)
            }
        } catch {
            if let rollbackBackup, FileManager.default.fileExists(atPath: rollbackBackup.path) {
                try? restoreBackup(rollbackBackup, to: target)
            }
            throw error
        }
    }

    private func restoreBackup(_ backup: URL, to target: URL) throws {
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString).rollback")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: backup, to: staging)
        try syncFile(at: staging)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(
                target,
                withItemAt: staging,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: staging, to: target)
        }
    }

    private func syncFile(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw providerResourceError("无法打开临时 Provider 文件进行落盘：\(url.path)")
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw providerResourceError("无法将临时 Provider 文件落盘。")
        }
    }

    private func validateResource(at url: URL, provider: ProviderItem) throws -> ProviderResourceValidation {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.isEmpty == false else {
            throw providerResourceError("Provider 内容为空，已保留当前文件。")
        }
        guard data.count <= 100 * 1024 * 1024 else {
            throw providerResourceError("Provider 文件超过 100 MiB，已拒绝替换。")
        }

        let preview = String(data: data.prefix(512), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if preview.hasPrefix("<!doctype") || preview.hasPrefix("<html") || preview.contains("<body") {
            throw providerResourceError("下载结果看起来是 HTML 错误页，不是 Provider 内容。")
        }

        guard let root = parseProviderMap(data: data) else {
            throw providerResourceError("Provider 不是可解析的 YAML 或 Base64 内容。")
        }
        guard root.isEmpty == false else {
            throw providerResourceError("Provider 顶层映射为空，已拒绝替换。")
        }

        let entryCount = providerEntryCount(root: root, provider: provider)
        guard entryCount > 0 else {
            throw providerResourceError("Provider 未发现可用条目，请检查类型、内容或订阅返回值。")
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return ProviderResourceValidation(entryCount: entryCount, sha256: digest)
    }

    private func parseProviderMap(data: Data) -> [String: Any]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if let loaded = try? Yams.load(yaml: text),
           let root = normalizeYAMLValue(loaded) as? [String: Any] {
            return root
        }

        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let decoded = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]),
              let decodedText = String(data: decoded, encoding: .utf8),
              let loaded = try? Yams.load(yaml: decodedText)
        else { return nil }
        return normalizeYAMLValue(loaded) as? [String: Any]
    }

    private func normalizeYAMLValue(_ value: Any) -> Any {
        if let map = value as? [String: Any] {
            return map.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = normalizeYAMLValue(pair.value)
            }
        }
        if let map = value as? [AnyHashable: Any] {
            return map.reduce(into: [String: Any]()) { result, pair in
                result[String(describing: pair.key)] = normalizeYAMLValue(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map(normalizeYAMLValue)
        }
        return value
    }

    private func providerEntryCount(root: [String: Any], provider: ProviderItem) -> Int {
        let kind = provider.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let keys: [String]
        if kind == "rule" {
            keys = ["payload", "rules"]
        } else if kind == "proxy" || kind == "node" {
            keys = ["proxies", "payload", "nodes"]
        } else {
            keys = ["proxies", "payload", "rules", "nodes"]
        }

        for key in keys {
            if let values = root[key] as? [Any] {
                return values.count
            }
            if let text = root[key] as? String, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return 1
            }
        }
        return 0
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
