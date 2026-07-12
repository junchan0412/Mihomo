import Foundation

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
        let (data, response) = try await NetworkClient.data(for: request)
        try validateHTTP(response: response, data: data)
        return target.absoluteString
    }

    func downloadWebDAV(urlString: String, username: String, password: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Backup", code: 3, userInfo: [NSLocalizedDescriptionKey: "WebDAV URL 无效"])
        }
        var request = URLRequest(url: url)
        applyBasicAuth(username: username, password: password, to: &request)
        let (data, response) = try await NetworkClient.data(for: request)
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
        let (data, response) = try await NetworkClient.data(for: request)
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
        let (data, response) = try await NetworkClient.data(for: request)
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
