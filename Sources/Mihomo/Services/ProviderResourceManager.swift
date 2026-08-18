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
        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await NetworkClient.download(for: request)
        } catch {
            throw providerDownloadError(error, remoteURL: url)
        }
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

        let validated = try validatedResource(at: downloaded, provider: provider)
        if let normalizedData = validated.data {
            try normalizedData.write(to: downloaded, options: .atomic)
        }
        let backup = try backupExistingResource(at: target, provider: provider)
        try replaceTarget(at: target, with: downloaded, rollbackBackup: backup)
        return ProviderResourceDownloadResult(
            target: target,
            backup: backup,
            validationSummary: "\(validated.validation.summary)，大小 \(Formatters.bytes(size))"
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
        let validated = try validatedResource(at: target, provider: provider)
        if let normalizedData = validated.data {
            try normalizedData.write(to: target, options: .atomic)
        }
        return ProviderResourceRefreshResult(
            target: target,
            size: size,
            validationSummary: validated.validation.summary
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
            try atomicRename(staging, over: target)
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
        try atomicRename(staging, over: target)
    }

    private func atomicRename(_ source: URL, over target: URL) throws {
        let result = source.path.withCString { sourcePath in
            target.path.withCString { targetPath in
                Darwin.rename(sourcePath, targetPath)
            }
        }
        guard result == 0 else {
            let errorCode = errno
            throw providerResourceError(
                "无法替换 Provider 文件：\(String(cString: strerror(errorCode)))",
                code: Int(errorCode)
            )
        }
        try syncDirectory(at: target.deletingLastPathComponent())
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

    private func syncDirectory(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw providerResourceError("无法打开 Provider 目录进行落盘：\(url.path)")
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw providerResourceError("无法将 Provider 目录变更落盘。")
        }
    }

    private func validatedResource(at url: URL, provider: ProviderItem) throws -> (validation: ProviderResourceValidation, data: Data?) {
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
            let detail = preview.contains("404 not found") ? "（404 Not Found，请检查订阅 URL 是否已过期）" : ""
            throw providerResourceError("下载结果看起来是 HTML 错误页，不是 Provider 内容。\(detail)")
        }

        if let root = parseProviderMap(data: data) {
            guard root.isEmpty == false else {
                throw providerResourceError("Provider 顶层映射为空，已拒绝替换。")
            }

            let entryCount = providerEntryCount(root: root, provider: provider)
            guard entryCount > 0 else {
                throw providerResourceError("Provider 未发现可用条目，请检查类型、内容或订阅返回值。")
            }
            return (providerResourceValidation(for: data, entryCount: entryCount), nil)
        }

        guard isProxyProvider(provider),
              let converted = proxyProviderYAML(fromSubscriptionData: data)
        else {
            throw providerResourceError("Provider 不是可解析的 Clash YAML、Base64 YAML 或节点 URI 订阅内容。")
        }
        let root = try providerMap(from: converted)
        let entryCount = providerEntryCount(root: root, provider: provider)
        guard entryCount > 0 else { throw providerResourceError("订阅中没有可用节点。") }
        return (providerResourceValidation(for: converted, entryCount: entryCount), converted)
    }

    private func providerResourceValidation(for data: Data, entryCount: Int) -> ProviderResourceValidation {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return .init(entryCount: entryCount, sha256: digest)
    }

    private func parseProviderMap(data: Data) -> [String: Any]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if let root = try? providerMap(from: data) { return root }

        let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let decoded = looseBase64Data(from: compact),
              let decodedText = String(data: decoded, encoding: .utf8),
              let loaded = try? Yams.load(yaml: decodedText)
        else { return nil }
        return normalizeYAMLValue(loaded) as? [String: Any]
    }

    private func providerMap(from data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8),
              let loaded = try Yams.load(yaml: text),
              let root = normalizeYAMLValue(loaded) as? [String: Any]
        else { throw providerResourceError("Provider YAML 顶层必须是映射。") }
        return root
    }

    private func isProxyProvider(_ provider: ProviderItem) -> Bool {
        ["proxy", "node"].contains(provider.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Converts the most common share-link subscription formats into the Clash provider YAML
    /// expected by mihomo. YAML subscriptions continue through the normal validation path.
    private func proxyProviderYAML(fromSubscriptionData data: Data) -> Data? {
        guard let rawText = String(data: data, encoding: .utf8) else { return nil }
        let text = decodedSubscriptionText(from: rawText)
        let links = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("#") == false }
        let proxies = links.compactMap(proxy(fromSubscriptionLink:))
        guard proxies.isEmpty == false,
              let yaml = try? YAMLText.dump(["proxies": proxies])
        else { return nil }
        return Data(yaml.utf8)
    }

    private func decodedSubscriptionText(from rawText: String) -> String {
        let compact = rawText.components(separatedBy: .whitespacesAndNewlines).joined()
        guard compact.contains("://") == false,
              let decoded = looseBase64Data(from: compact),
              let text = String(data: decoded, encoding: .utf8)
        else { return rawText }
        return text
    }

    private func proxy(fromSubscriptionLink link: String) -> [String: Any]? {
        guard let scheme = link.split(separator: ":", maxSplits: 1).first?.lowercased() else { return nil }
        switch scheme {
        case "vmess": return vmessProxy(from: link)
        case "ss": return shadowsocksProxy(from: link)
        case "trojan", "vless", "hysteria2", "hy2", "tuic": return urlProxy(from: link, type: scheme)
        default: return nil
        }
    }

    private func vmessProxy(from link: String) -> [String: Any]? {
        let encoded = String(link.dropFirst("vmess://".count))
        guard let data = looseBase64Data(from: encoded),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              let host = subscriptionString(payload["add"]),
              let port = subscriptionPort(payload["port"]),
              let uuid = subscriptionString(payload["id"])
        else { return nil }

        var proxy: [String: Any] = [
            "name": subscriptionString(payload["ps"]) ?? host,
            "type": "vmess",
            "server": host,
            "port": port,
            "uuid": uuid,
            "alterId": Int(subscriptionString(payload["aid"]) ?? "0") ?? 0,
            "cipher": subscriptionString(payload["scy"]) ?? "auto"
        ]
        if subscriptionString(payload["tls"])?.lowercased() == "tls" { proxy["tls"] = true }
        if let serverName = subscriptionString(payload["sni"]), serverName.isEmpty == false { proxy["servername"] = serverName }
        if let network = subscriptionString(payload["net"]), network.isEmpty == false, network != "tcp" {
            proxy["network"] = network
        }
        if let path = subscriptionString(payload["path"]), path.isEmpty == false { proxy["ws-opts"] = ["path": path] }
        if let hostHeader = subscriptionString(payload["host"]), hostHeader.isEmpty == false {
            var options = proxy["ws-opts"] as? [String: Any] ?? [:]
            options["headers"] = ["Host": hostHeader]
            proxy["ws-opts"] = options
        }
        return proxy
    }

    private func shadowsocksProxy(from link: String) -> [String: Any]? {
        let withoutScheme = String(link.dropFirst("ss://".count))
        let components = withoutScheme.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = components.count > 1 ? String(components[1]).removingPercentEncoding : nil
        let endpoint = String(components[0].split(separator: "?", maxSplits: 1).first ?? "")
        let decodedEndpoint: String
        if endpoint.contains("@") {
            decodedEndpoint = endpoint
        } else if let data = looseBase64Data(from: endpoint), let text = String(data: data, encoding: .utf8) {
            decodedEndpoint = text
        } else {
            return nil
        }
        let parts = decodedEndpoint.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let rawCredentials = String(parts[0]).removingPercentEncoding,
              let credentials = decodedShadowsocksCredentials(rawCredentials),
              let separator = credentials.firstIndex(of: ":"),
              let endpointComponents = URLComponents(string: "ss://\(parts[1])"),
              let host = endpointComponents.host,
              let port = endpointComponents.port
        else { return nil }
        return [
            "name": name?.isEmpty == false ? name! : host,
            "type": "ss",
            "server": host,
            "port": port,
            "cipher": String(credentials[..<separator]),
            "password": String(credentials[credentials.index(after: separator)...])
        ]
    }

    private func urlProxy(from link: String, type: String) -> [String: Any]? {
        guard let components = URLComponents(string: link),
              let host = components.host,
              let port = components.port
        else { return nil }
        let user = components.user?.removingPercentEncoding
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name.lowercased(), $0) }
        })
        let displayName = components.fragment?.removingPercentEncoding
        var proxy: [String: Any] = [
            "name": displayName?.isEmpty == false ? displayName! : host,
            "type": type == "hy2" ? "hysteria2" : type,
            "server": host,
            "port": port
        ]

        switch type {
        case "trojan":
            guard let password = user, password.isEmpty == false else { return nil }
            proxy["password"] = password
        case "vless":
            guard let uuid = user, uuid.isEmpty == false else { return nil }
            proxy["uuid"] = uuid
            proxy["tls"] = query["security"] != "none"
            proxy["udp"] = true
            if let flow = query["flow"], flow.isEmpty == false { proxy["flow"] = flow }
        case "hysteria2", "hy2":
            guard let password = user, password.isEmpty == false else { return nil }
            proxy["password"] = password
        case "tuic":
            guard let uuid = user, uuid.isEmpty == false else { return nil }
            proxy["uuid"] = uuid
            if let password = components.password?.removingPercentEncoding, password.isEmpty == false { proxy["password"] = password }
        default: return nil
        }

        if query["security"] == "tls" || type == "trojan" || type == "hysteria2" || type == "hy2" || type == "tuic" { proxy["tls"] = true }
        if let serverName = query["sni"] ?? query["peer"], serverName.isEmpty == false { proxy["servername"] = serverName }
        if query["allowinsecure"] == "1" || query["insecure"] == "1" { proxy["skip-cert-verify"] = true }
        if let network = query["type"], ["ws", "grpc", "http"].contains(network) {
            proxy["network"] = network
            if network == "ws" {
                var options: [String: Any] = [:]
                if let path = query["path"], path.isEmpty == false { options["path"] = path }
                if let hostHeader = query["host"], hostHeader.isEmpty == false { options["headers"] = ["Host": hostHeader] }
                if options.isEmpty == false { proxy["ws-opts"] = options }
            }
        }
        return proxy
    }

    private func subscriptionString(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func subscriptionPort(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return subscriptionString(value).flatMap(Int.init)
    }

    private func decodedShadowsocksCredentials(_ value: String) -> String? {
        if value.contains(":") { return value }
        guard let data = looseBase64Data(from: value), let decoded = String(data: data, encoding: .utf8), decoded.contains(":") else {
            return nil
        }
        return decoded
    }

    private func looseBase64Data(from text: String) -> Data? {
        let compact = text
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard compact.isEmpty == false else { return nil }
        let padding = (4 - compact.count % 4) % 4
        return Data(base64Encoded: compact + String(repeating: "=", count: padding), options: [.ignoreUnknownCharacters])
    }

    private func providerDownloadError(_ error: Error, remoteURL: URL) -> NSError {
        let certificateCodes: Set<URLError.Code> = [
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired,
            .secureConnectionFailed
        ]
        if let error = error as? URLError, certificateCodes.contains(error.code) {
            return providerResourceError("无法验证订阅站点 \(remoteURL.host ?? "") 的 HTTPS 证书。请检查订阅地址、域名和证书，不会跳过证书校验。")
        }
        return providerResourceError("下载 Provider 失败：\(error.localizedDescription)")
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
