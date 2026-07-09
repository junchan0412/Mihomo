import CryptoKit
import Foundation
import JavaScriptCore
import Security
import Yams

final class CertificatePinningSession: NSObject, URLSessionDelegate {
    private let expectedFingerprint: String?
    private var pinningError: Error?
    private(set) var observedFingerprint: String?

    init(expectedFingerprint: String?) {
        let cleaned = CertificatePinningSession.normalize(expectedFingerprint ?? "")
        self.expectedFingerprint = cleaned.isEmpty ? nil : cleaned
    }

    func fetch(_ url: URL) async throws -> (Data, URLResponse, String?) {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        if let pinningError {
            throw pinningError
        }
        return (data, response, observedFingerprint)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var trustError: CFError?
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        guard SecTrustEvaluateWithError(trust, &trustError),
              let certificate = chain?.first
        else {
            pinningError = trustError as Error?
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        observedFingerprint = digest

        if let expectedFingerprint, expectedFingerprint != digest {
            pinningError = NSError(domain: "CertificatePinning", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "证书指纹不匹配：期望 \(expectedFingerprint)，实际 \(digest)"
            ])
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    static func normalize(_ value: String) -> String {
        value.lowercased()
            .filter { $0.isHexDigit }
            .map(String.init)
            .joined()
    }
}

struct JSOverrideRunner {
    func apply(fragments: [ConfigFragment], to content: String) throws -> String {
        var result = content
        for fragment in fragments where fragment.enabled && fragment.kind == .javascript {
            let context = JSContext()
            var exceptionMessage: String?
            context?.exceptionHandler = { _, exception in
                exceptionMessage = exception?.toString()
            }
            context?.evaluateScript(fragment.content)
            if let exceptionMessage {
                throw NSError(domain: "JSOverride", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(fragment.name)：\(exceptionMessage)"
                ])
            }
            guard let transform = context?.objectForKeyedSubscript("transform"),
                  transform.isUndefined == false
            else {
                continue
            }
            guard let transformed = transform.call(withArguments: [result])?.toString() else {
                throw NSError(domain: "JSOverride", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "\(fragment.name)：transform(config) 必须返回字符串"
                ])
            }
            if let exceptionMessage {
                throw NSError(domain: "JSOverride", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "\(fragment.name)：\(exceptionMessage)"
                ])
            }
            result = transformed
        }
        return result
    }
}

final class ConfigFragmentStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadFragments() throws -> [ConfigFragment] {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.configFragmentsFile.path) else { return [] }
        let data = try Data(contentsOf: AppPaths.configFragmentsFile)
        return try decoder.decode([ConfigFragment].self, from: data)
    }

    func saveFragments(_ fragments: [ConfigFragment]) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(fragments)
        try data.write(to: AppPaths.configFragmentsFile, options: .atomic)
    }

    func loadDisabledRules() throws -> Set<String> {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.disabledRulesFile.path) else { return [] }
        let data = try Data(contentsOf: AppPaths.disabledRulesFile)
        return Set(try decoder.decode([String].self, from: data))
    }

    func saveDisabledRules(_ rules: Set<String>) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(rules.sorted())
        try data.write(to: AppPaths.disabledRulesFile, options: .atomic)
    }

    func parseRules(profileContent: String, disabledRules: Set<String>) -> [RuleItem] {
        guard let root = yamlRoot(profileContent),
              let rules = root["rules"] as? [Any]
        else { return parseRulesFromText(profileContent: profileContent, disabledRules: disabledRules) }

        return rules
            .compactMap { $0 as? String }
            .enumerated()
            .map { index, rule in
                RuleItem(index: index + 1, content: rule, disabled: disabledRules.contains(rule))
            }
    }

    func parseProviders(profileContent: String) -> [ProviderItem] {
        guard let root = yamlRoot(profileContent) else {
            return parseProviderBlock(kind: "Proxy", key: "proxy-providers", in: profileContent)
                + parseProviderBlock(kind: "Rule", key: "rule-providers", in: profileContent)
        }

        let rules = (root["rules"] as? [Any])?.compactMap { $0 as? String } ?? []
        let ruleUsage = ruleProviderUsage(from: rules)
        let proxyUsage = proxyProviderUsage(from: root["proxy-groups"])
        return providerItems(kind: "Proxy", key: "proxy-providers", root: root, usage: proxyUsage)
            + providerItems(kind: "Rule", key: "rule-providers", root: root, usage: ruleUsage)
    }

    func makeDiff(original: String, generated: String) -> String {
        let oldLines = original.components(separatedBy: .newlines)
        let newLines = generated.components(separatedBy: .newlines)
        let count = max(oldLines.count, newLines.count)
        var rows: [String] = []
        for index in 0..<count {
            let oldLine = index < oldLines.count ? oldLines[index] : nil
            let newLine = index < newLines.count ? newLines[index] : nil
            if oldLine == newLine, let oldLine {
                rows.append("  \(oldLine)")
            } else {
                if let oldLine { rows.append("- \(oldLine)") }
                if let newLine { rows.append("+ \(newLine)") }
            }
        }
        return rows.joined(separator: "\n")
    }

    private func parseProviderBlock(kind: String, key: String, in content: String) -> [ProviderItem] {
        guard let block = topLevelBlock(named: key, in: content) else { return [] }
        var providers: [ProviderItem] = []
        var currentName: String?
        var currentDetails: [String] = []

        func commit() {
            guard let currentName else { return }
            let detail = currentDetails
                .filter { $0.hasPrefix("type:") || $0.hasPrefix("url:") || $0.hasPrefix("path:") || $0.hasPrefix("behavior:") || $0.hasPrefix("interval:") }
                .prefix(5)
                .joined(separator: " · ")
            providers.append(ProviderItem(kind: kind, name: currentName, detail: detail.isEmpty ? "-" : detail))
        }

        for line in block.components(separatedBy: .newlines).dropFirst() {
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if indent == 2, trimmed.hasSuffix(":"), trimmed.hasPrefix("-") == false {
                commit()
                currentName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                currentDetails = []
            } else if currentName != nil, trimmed.isEmpty == false {
                currentDetails.append(trimmed)
            }
        }
        commit()
        return providers
    }

    private func parseRulesFromText(profileContent: String, disabledRules: Set<String>) -> [RuleItem] {
        guard let block = topLevelBlock(named: "rules", in: profileContent) else { return [] }
        return block.components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- ") else { return nil }
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .enumerated()
            .map { index, rule in
                RuleItem(index: index + 1, content: rule, disabled: disabledRules.contains(rule))
            }
    }

    private func providerItems(kind: String, key: String, root: [String: Any], usage: [String: Int]) -> [ProviderItem] {
        guard let providers = root[key] as? [String: Any] else { return [] }
        return providers.map { name, value in
            let map = value as? [String: Any] ?? [:]
            let providerType = map["type"].map { "\($0)" } ?? ""
            let remoteURL = map["url"].map { "\($0)" }
            let path = map["path"].map { "\($0)" }
            let interval = map["interval"].flatMap { value -> Int? in
                if let intValue = value as? Int { return intValue }
                if let stringValue = value as? String { return Int(stringValue) }
                return nil
            }
            var pieces = ["type", "url", "path", "behavior", "interval", "vehicleType", "updatedAt"]
                .compactMap { field in
                    map[field].map { "\(field): \($0)" }
                }
            let count = usage[name, default: 0]
            if count > 0 {
                pieces.append(kind == "Rule" ? "rules: \(count)" : "uses: \(count)")
            }
            return ProviderItem(
                kind: kind,
                name: name,
                detail: pieces.isEmpty ? "-" : pieces.prefix(6).joined(separator: " · "),
                providerType: providerType,
                remoteURL: remoteURL,
                path: path,
                interval: interval,
                ruleCount: count
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func ruleProviderUsage(from rules: [String]) -> [String: Int] {
        rules.reduce(into: [String: Int]()) { result, rule in
            let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2, parts[0].uppercased() == "RULE-SET" else { return }
            result[parts[1], default: 0] += 1
        }
    }

    private func proxyProviderUsage(from value: Any?) -> [String: Int] {
        guard let groups = value as? [Any] else { return [:] }
        var usage: [String: Int] = [:]
        for item in groups {
            guard let group = item as? [String: Any],
                  let providers = group["use"] as? [Any]
            else { continue }
            for provider in providers.compactMap({ $0 as? String }) {
                usage[provider, default: 0] += 1
            }
        }
        return usage
    }

    private func yamlRoot(_ content: String) -> [String: Any]? {
        guard let object = try? Yams.load(yaml: content) else { return nil }
        return normalizeYAMLValue(object) as? [String: Any]
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
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }

    private func topLevelBlock(named key: String, in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var capture = false
        var block: [String] = []

        for line in lines {
            if line.first?.isWhitespace == false,
               let colon = line.firstIndex(of: ":") {
                let candidate = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate == key {
                    capture = true
                    block = [line]
                    continue
                }
                if capture {
                    break
                }
            }
            if capture {
                block.append(line)
            }
        }
        return block.isEmpty ? nil : block.joined(separator: "\n")
    }
}

final class ManagedCoreManager {
    static var bundledCorePath: String? {
        Bundle.main.url(forResource: "mihomo", withExtension: nil, subdirectory: "Core")?.path
    }

    func installOrUpdate(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ManagedCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Core 下载 URL 无效"])
        }
        try AppPaths.ensureBaseDirectories()
        let (downloaded, _) = try await URLSession.shared.download(from: url)
        let target = AppPaths.managedCoreFile
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }

        if url.pathExtension.lowercased() == "gz" {
            let data = try gunzip(downloaded)
            try data.write(to: target, options: .atomic)
        } else {
            try FileManager.default.copyItem(at: downloaded, to: target)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        if let version = try? Shell.run(target.path, ["-v"]), version.status == 0 {
            return [version.stdout, version.stderr]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return target.path
    }

    private func gunzip(_ source: URL) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", source.path]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ManagedCore", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "gzip 解压失败"
            ])
        }
        return data
    }
}

final class ExternalUIManager {
    func install(name: String, from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ExternalUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "外部 UI 下载 URL 无效"])
        }
        try AppPaths.ensureBaseDirectories()
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "external-ui" : name
        let target = AppPaths.externalUIDirectory.appendingPathComponent(cleanedName, isDirectory: true)
        let (downloaded, _) = try await URLSession.shared.download(from: url)
        let tempRoot = AppPaths.runtimeDirectory.appendingPathComponent("external-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        if url.pathExtension.lowercased() == "zip" {
            let result = try Shell.run("/usr/bin/unzip", ["-q", downloaded.path, "-d", tempRoot.path])
            guard result.status == 0 else {
                throw NSError(domain: "ExternalUI", code: Int(result.status), userInfo: [
                    NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
                ])
            }
        } else {
            try FileManager.default.copyItem(at: downloaded, to: tempRoot.appendingPathComponent("index.html"))
        }

        let root = try locateWebRoot(in: tempRoot)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
        }
        return target.path
    }

    func status(name: String) -> String {
        let path = AppPaths.externalUIDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: path.path) ? path.deletingLastPathComponent().path : "未安装"
    }

    private func locateWebRoot(in directory: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) {
            return directory
        }
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw NSError(domain: "ExternalUI", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取外部 UI 压缩包"])
        }
        for case let url as URL in enumerator where url.lastPathComponent == "index.html" {
            return url.deletingLastPathComponent()
        }
        throw NSError(domain: "ExternalUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "压缩包中没有 index.html"])
    }
}

final class GeoUpdateManager {
    func update(geoIPURL: String, geoSiteURL: String) async throws -> String {
        try AppPaths.ensureBaseDirectories()
        var updated: [String] = []
        if let url = URL(string: geoIPURL), geoIPURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try await download(url: url, to: AppPaths.geoDirectory.appendingPathComponent("geoip.dat"))
            updated.append("geoip.dat")
        }
        if let url = URL(string: geoSiteURL), geoSiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try await download(url: url, to: AppPaths.geoDirectory.appendingPathComponent("geosite.dat"))
            updated.append("geosite.dat")
        }
        return updated.isEmpty ? "没有可更新的 Geo URL" : "已更新 \(updated.joined(separator: "、"))"
    }

    private func download(url: URL, to target: URL) async throws {
        let (temp, _) = try await URLSession.shared.download(from: url)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: temp, to: target)
    }
}

struct BackupPayload: Codable {
    var createdAt: Date
    var settings: AppSettings
    var profiles: [ProfileItem]
    var fragments: [ConfigFragment]
    var disabledRules: [String]
    var profileContents: [String: String]
}

final class BackupManager {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let supportDirectory: URL
    private let backupsDirectory: URL

    init(
        supportDirectory: URL = AppPaths.supportDirectory,
        backupsDirectory: URL = AppPaths.backupsDirectory
    ) {
        self.supportDirectory = supportDirectory
        self.backupsDirectory = backupsDirectory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func createLocalArchive() throws -> URL {
        try ensureBaseDirectories()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let archive = backupsDirectory.appendingPathComponent("Mihomo-\(formatter.string(from: Date())).zip")
        let candidates = [
            "settings.json",
            "profiles.json",
            "config-fragments.json",
            "disabled-rules.json",
            "Profiles"
        ].filter {
            FileManager.default.fileExists(atPath: supportDirectory.appendingPathComponent($0).path)
        }
        guard candidates.isEmpty == false else {
            throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可备份的数据"])
        }
        let result = try Shell.run("/usr/bin/zip", ["-r", "-X", archive.path] + candidates, workDirectory: supportDirectory)
        guard result.status == 0 else {
            throw NSError(domain: "Backup", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
        return archive
    }

    func restoreLocalArchive(_ archive: URL) throws {
        try ensureBaseDirectories()
        let entries = try zipEntries(in: archive)
        try validateRestoreEntries(entries)
        try rejectSymbolicLinks(in: archive)

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mihomo-Restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        let result = try Shell.run("/usr/bin/unzip", ["-oq", archive.path, "-d", stagingDirectory.path])
        guard result.status == 0 else {
            throw NSError(domain: "Backup", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
        try restoreValidatedContents(from: stagingDirectory)
    }

    func uploadWebDAV(archive: URL, urlString: String, username: String, password: String) async throws -> String {
        guard let target = webDAVTarget(urlString: urlString, archive: archive) else {
            throw NSError(domain: "Backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "WebDAV URL 无效"])
        }
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.httpBody = try Data(contentsOf: archive)
        applyBasicAuth(username: username, password: password, to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return target.absoluteString
    }

    func downloadWebDAV(urlString: String, username: String, password: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Backup", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebDAV URL 无效"])
        }
        var request = URLRequest(url: url)
        applyBasicAuth(username: username, password: password, to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        try ensureBaseDirectories()
        let target = backupsDirectory.appendingPathComponent(url.lastPathComponent.isEmpty ? "webdav-restore.zip" : url.lastPathComponent)
        try data.write(to: target, options: .atomic)
        return target
    }

    func encodePayload(_ payload: BackupPayload) throws -> String {
        String(data: try encoder.encode(payload), encoding: .utf8) ?? "{}"
    }

    func decodePayload(_ content: String) throws -> BackupPayload {
        try decoder.decode(BackupPayload.self, from: Data(content.utf8))
    }

    func uploadGist(payload: String, token: String, gistID: String) async throws -> String {
        guard token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NSError(domain: "Backup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Gist Token 为空"])
        }
        let isUpdate = gistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let url = URL(string: isUpdate ? "https://api.github.com/gists/\(gistID)" : "https://api.github.com/gists")!
        var request = URLRequest(url: url)
        request.httpMethod = isUpdate ? "PATCH" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "description": "Mihomo macOS backup",
            "public": false,
            "files": ["mihomo-backup.json": ["content": payload]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["id"] as? String) ?? gistID
    }

    func downloadGist(token: String, gistID: String) async throws -> String {
        guard gistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NSError(domain: "Backup", code: 5, userInfo: [NSLocalizedDescriptionKey: "Gist ID 为空"])
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/gists/\(gistID)")!)
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [String: [String: Any]]
        guard let content = files?["mihomo-backup.json"]?["content"] as? String else {
            throw NSError(domain: "Backup", code: 6, userInfo: [NSLocalizedDescriptionKey: "Gist 中没有 mihomo-backup.json"])
        }
        return content
    }

    private func webDAVTarget(urlString: String, archive: URL) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        if components.path.hasSuffix("/") {
            components.path += archive.lastPathComponent
        }
        return components.url
    }

    private func applyBasicAuth(username: String, password: String, to request: inout URLRequest) {
        guard username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(domain: "Backup", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }

    private func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    private func zipEntries(in archive: URL) throws -> [String] {
        let result = try Shell.run("/usr/bin/zipinfo", ["-1", archive.path])
        guard result.status == 0 else {
            throw backupError(result.stderr.isEmpty ? result.stdout : result.stderr, code: Int(result.status))
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func validateRestoreEntries(_ entries: [String]) throws {
        guard entries.isEmpty == false else {
            throw backupError("备份压缩包为空。")
        }
        for entry in entries {
            _ = try normalizedRestorePath(entry)
        }
    }

    private func rejectSymbolicLinks(in archive: URL) throws {
        let result = try Shell.run("/usr/bin/zipinfo", ["-l", archive.path])
        guard result.status == 0 else {
            throw backupError(result.stderr.isEmpty ? result.stdout : result.stderr, code: Int(result.status))
        }
        for line in result.stdout.components(separatedBy: .newlines) where line.first == "l" {
            throw backupError("备份压缩包不能包含符号链接。")
        }
    }

    private func restoreValidatedContents(from stagingDirectory: URL) throws {
        let manager = FileManager.default
        let rootPath = stagingDirectory.standardizedFileURL.path
        guard let enumerator = manager.enumerator(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw backupError("无法读取备份解压目录。")
        }

        for case let source as URL in enumerator {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw backupError("备份压缩包不能包含符号链接。")
            }

            let sourcePath = source.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard sourcePath.hasPrefix(prefix) else {
                throw backupError("备份条目路径无效：\(sourcePath)")
            }
            let relativePath = String(sourcePath.dropFirst(prefix.count))
            let normalizedPath = try normalizedRestorePath(relativePath)
            let destination = try restoreDestination(for: normalizedPath)

            if values.isDirectory == true {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                try manager.copyItem(at: source, to: destination)
            }
        }
    }

    private func normalizedRestorePath(_ path: String) throws -> String {
        let replaced = path.replacingOccurrences(of: "\\", with: "/")
        if replaced.hasPrefix("/") {
            throw backupError("备份条目不能使用绝对路径：\(path)")
        }
        let components = replaced
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        guard components.isEmpty == false else {
            throw backupError("备份条目路径为空。")
        }
        guard components.contains("..") == false else {
            throw backupError("备份条目不能包含 ..：\(path)")
        }
        let normalized = components.joined(separator: "/")
        guard Self.allowedRestoreRoots.contains(normalized) || normalized.hasPrefix("Profiles/") else {
            throw backupError("备份条目不在允许恢复清单内：\(normalized)")
        }
        return normalized
    }

    private func restoreDestination(for normalizedPath: String) throws -> URL {
        let root = supportDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var destination = root
        for component in normalizedPath.split(separator: "/").map(String.init) {
            destination.appendPathComponent(component)
            let resolvedComponent = destination.standardizedFileURL.resolvingSymlinksInPath()
            guard Self.isContained(resolvedComponent, in: root) else {
                throw backupError("恢复目标必须位于 App Support 目录内：\(normalizedPath)")
            }
        }
        return destination.standardizedFileURL
    }

    private func backupError(_ message: String, code: Int = 1) -> NSError {
        NSError(domain: "Backup", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func isContained(_ url: URL, in directory: URL) -> Bool {
        let root = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private static let allowedRestoreRoots: Set<String> = [
        "settings.json",
        "profiles.json",
        "config-fragments.json",
        "disabled-rules.json",
        "Profiles"
    ]
}

struct DiagnosticRedactor {
    private static let placeholder = "<redacted>"

    private let sensitiveValues: [String]

    init(settings: AppSettings) {
        sensitiveValues = [
            settings.controllerSecret,
            settings.backupWebDAVPassword,
            settings.gistToken
        ]
    }

    func redact(_ content: String) -> String {
        var result = content
        result = replace(
            #"(?im)^([ \t-]*(?:secret|password|passwd|token|authorization|proxy-authorization|controllerSecret|backupWebDAVPassword|gistToken)[ \t:=]+).*$"#,
            in: result,
            with: "$1\(Self.placeholder)"
        )
        result = replace(
            #"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#,
            in: result,
            with: "$1 \(Self.placeholder)"
        )
        result = replace(
            #"(?i)([?&](?:token|secret|password|passwd|key|auth|access_token)=)[^&\s]+"#,
            in: result,
            with: "$1\(Self.placeholder)"
        )
        result = replace(
            #"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#,
            in: result,
            with: "$1\(Self.placeholder)@"
        )

        for value in Set(sensitiveValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where value.count >= 4 {
            result = result.replacingOccurrences(of: value, with: Self.placeholder)
        }
        return result
    }

    var manifest: String {
        """
        Diagnostic Redaction
        Applied: controller secret values, Authorization/Bearer/Basic credentials, password/token/secret lines, URL user-info, and sensitive query parameters are replaced with \(Self.placeholder).
        """
    }

    private func replace(_ pattern: String, in content: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return expression.stringByReplacingMatches(in: content, range: range, withTemplate: template)
    }
}
