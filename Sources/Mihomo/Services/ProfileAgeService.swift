import Foundation

struct AgeIdentity: Hashable {
    var identityPath: String
    var recipient: String
}

final class ProfileAgeService {
    static func isAgeArmored(_ content: String) -> Bool {
        content.hasPrefix("-----BEGIN AGE ENCRYPTED FILE-----")
            || content.hasPrefix("age-encryption.org/v1")
    }

    func installTools(from urlString: String) async throws -> (agePath: String, keygenPath: String) {
        guard let url = URL(string: urlString) else {
            throw ageError("Age 下载 URL 无效。")
        }
        try AppPaths.ensureBaseDirectories()
        let tempRoot = AppPaths.runtimeDirectory.appendingPathComponent("age-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let (downloaded, _) = try await URLSession.shared.download(from: url)
        let unpack = tempRoot.appendingPathComponent("unpack", isDirectory: true)
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        let result = try Shell.run("/usr/bin/tar", ["-xzf", downloaded.path, "-C", unpack.path])
        guard result.status == 0 else {
            throw ageError(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        let age = try locateExecutable(named: "age", in: unpack)
        let keygen = try locateExecutable(named: "age-keygen", in: unpack)
        let targetAge = AppPaths.toolsDirectory.appendingPathComponent("age")
        let targetKeygen = AppPaths.toolsDirectory.appendingPathComponent("age-keygen")
        for pair in [(age, targetAge), (keygen, targetKeygen)] {
            if FileManager.default.fileExists(atPath: pair.1.path) {
                try FileManager.default.removeItem(at: pair.1)
            }
            try FileManager.default.copyItem(at: pair.0, to: pair.1)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pair.1.path)
        }
        return (targetAge.path, targetKeygen.path)
    }

    func ensureIdentity(settings: AppSettings) throws -> AgeIdentity {
        let identityURL = identityURL(settings)
        if FileManager.default.fileExists(atPath: identityURL.path),
           let recipient = parseRecipient(identityURL: identityURL) {
            return AgeIdentity(identityPath: identityURL.path, recipient: recipient)
        }

        let keygen = try keygenPath(settings)
        try FileManager.default.createDirectory(at: identityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = try Shell.run(keygen, ["-o", identityURL.path])
        guard result.status == 0 else {
            throw ageError(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identityURL.path)

        if let recipient = parseRecipient(text: result.stdout + "\n" + result.stderr)
            ?? parseRecipient(identityURL: identityURL) {
            return AgeIdentity(identityPath: identityURL.path, recipient: recipient)
        }
        throw ageError("Age identity 已生成，但无法解析 public recipient。")
    }

    func encryptedContent(_ content: String, settings: AppSettings) throws -> String {
        guard settings.profileEncryptionEnabled else { return content }
        if Self.isAgeArmored(content) { return content }
        let recipient = try recipient(settings)
        return try runAgeTransform(input: content) { input, output in
            [try agePath(settings), "--armor", "-r", recipient, "-o", output.path, input.path]
        }
    }

    func decryptedContent(_ content: String, settings: AppSettings) throws -> String {
        guard Self.isAgeArmored(content) else { return content }
        let identity = identityURL(settings).path
        guard FileManager.default.fileExists(atPath: identity) else {
            throw ageError("Profile 已加密，但 Age identity 不存在：\(identity)")
        }
        return try runAgeTransform(input: content) { input, output in
            [try agePath(settings), "-d", "-i", identity, "-o", output.path, input.path]
        }
    }

    func agePath(_ settings: AppSettings) throws -> String {
        let candidates = [
            settings.ageBinaryPath,
            AppPaths.toolsDirectory.appendingPathComponent("age").path,
            "/opt/homebrew/bin/age",
            "/usr/local/bin/age"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw ageError("未找到 age 可执行文件，请先安装 Age 工具。")
    }

    private func keygenPath(_ settings: AppSettings) throws -> String {
        let candidates = [
            settings.ageKeygenPath,
            AppPaths.toolsDirectory.appendingPathComponent("age-keygen").path,
            "/opt/homebrew/bin/age-keygen",
            "/usr/local/bin/age-keygen"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw ageError("未找到 age-keygen 可执行文件，请先安装 Age 工具。")
    }

    private func recipient(_ settings: AppSettings) throws -> String {
        if settings.ageRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return settings.ageRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let recipient = parseRecipient(identityURL: identityURL(settings)) {
            return recipient
        }
        throw ageError("缺少 Age recipient，请先生成身份。")
    }

    private func identityURL(_ settings: AppSettings) -> URL {
        let path = settings.ageIdentityPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? AppPaths.ageIdentityFile : URL(fileURLWithPath: path)
    }

    private func runAgeTransform(input: String, arguments: (URL, URL) throws -> [String]) throws -> String {
        try AppPaths.ensureBaseDirectories()
        let tempRoot = AppPaths.runtimeDirectory.appendingPathComponent("age-transform-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let inputURL = tempRoot.appendingPathComponent("input")
        let outputURL = tempRoot.appendingPathComponent("output")
        try input.write(to: inputURL, atomically: true, encoding: .utf8)
        var args = try arguments(inputURL, outputURL)
        let executable = args.removeFirst()
        let result = try Shell.run(executable, args)
        guard result.status == 0 else {
            throw ageError(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return try String(contentsOf: outputURL, encoding: .utf8)
    }

    private func locateExecutable(named name: String, in directory: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw ageError("无法读取 Age 工具压缩包。")
        }
        for case let url as URL in enumerator where url.lastPathComponent == name && FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        throw ageError("Age 工具压缩包中没有 \(name)。")
    }

    private func parseRecipient(identityURL: URL) -> String? {
        guard let text = try? String(contentsOf: identityURL, encoding: .utf8) else { return nil }
        return parseRecipient(text: text)
    }

    private func parseRecipient(text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = trimmed.range(of: #"age1[023456789acdefghjklmnpqrstuvwxyz]+"#, options: .regularExpression) {
                return String(trimmed[range])
            }
        }
        return nil
    }

    private func ageError(_ message: String) -> NSError {
        NSError(domain: "ProfileAge", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
