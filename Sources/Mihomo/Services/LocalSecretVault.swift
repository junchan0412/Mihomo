import CryptoKit
import Foundation
import Security

struct AppSecretValues: Codable, Equatable {
    var controllerSecret: String
    var backupWebDAVPassword: String
    var gistToken: String

    static let empty = AppSecretValues(
        controllerSecret: "",
        backupWebDAVPassword: "",
        gistToken: ""
    )

    var isEmpty: Bool {
        controllerSecret.isEmpty && backupWebDAVPassword.isEmpty && gistToken.isEmpty
    }

    init(controllerSecret: String, backupWebDAVPassword: String, gistToken: String) {
        self.controllerSecret = controllerSecret
        self.backupWebDAVPassword = backupWebDAVPassword
        self.gistToken = gistToken
    }

    init(settings: AppSettings) {
        self.init(
            controllerSecret: settings.controllerSecret,
            backupWebDAVPassword: settings.backupWebDAVPassword,
            gistToken: settings.gistToken
        )
    }
}

final class LocalSecretVault {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = AppPaths.secretVaultFile) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSecrets() throws -> AppSecretValues {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let envelope = try decoder.decode(SecretVaultEnvelope.self, from: Data(contentsOf: fileURL))
        let salt = try Data(base64EncodedStrict: envelope.salt, field: "salt")
        let nonceData = try Data(base64EncodedStrict: envelope.nonce, field: "nonce")
        let ciphertext = try Data(base64EncodedStrict: envelope.ciphertext, field: "ciphertext")
        let tag = try Data(base64EncodedStrict: envelope.tag, field: "tag")
        let key = try makeKey(salt: salt)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let payloadData = try AES.GCM.open(sealedBox, using: key)
        return try decoder.decode(AppSecretValues.self, from: payloadData)
    }

    func saveSecrets(_ secrets: AppSecretValues) throws {
        try AppPaths.ensureBaseDirectories()
        let salt = randomData(byteCount: 32)
        let key = try makeKey(salt: salt)
        let payloadData = try encoder.encode(secrets)
        let sealedBox = try AES.GCM.seal(payloadData, using: key)
        let envelope = SecretVaultEnvelope(
            salt: salt.base64EncodedString(),
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString(),
            updatedAt: Date()
        )
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func exportPortableSecrets(passphrase: String, iterations: Int = 120_000) throws -> String {
        let secrets = try loadSecrets()
        let salt = randomData(byteCount: 32)
        let key = try makePassphraseKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let payloadData = try encoder.encode(secrets)
        let sealedBox = try AES.GCM.seal(payloadData, using: key)
        let bundle = PortableSecretBundle(
            iterations: iterations,
            salt: salt.base64EncodedString(),
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            ciphertext: sealedBox.ciphertext.base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString(),
            createdAt: Date()
        )
        let data = try encoder.encode(bundle)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @discardableResult
    func importPortableSecrets(_ bundleJSON: String, passphrase: String) throws -> AppSecretValues {
        let bundle = try decoder.decode(PortableSecretBundle.self, from: Data(bundleJSON.utf8))
        guard bundle.version == 1 else {
            throw vaultError("Portable secret bundle version \(bundle.version) is not supported.")
        }
        let salt = try Data(base64EncodedStrict: bundle.salt, field: "salt")
        let nonceData = try Data(base64EncodedStrict: bundle.nonce, field: "nonce")
        let ciphertext = try Data(base64EncodedStrict: bundle.ciphertext, field: "ciphertext")
        let tag = try Data(base64EncodedStrict: bundle.tag, field: "tag")
        let key = try makePassphraseKey(passphrase: passphrase, salt: salt, iterations: bundle.iterations)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let payloadData = try AES.GCM.open(sealedBox, using: key)
        let secrets = try decoder.decode(AppSecretValues.self, from: payloadData)
        try saveSecrets(secrets)
        return secrets
    }

    private func makeKey(salt: Data) throws -> SymmetricKey {
        let seed = [
            Bundle.main.bundleIdentifier ?? "dev.codex.Mihomo",
            NSUserName(),
            NSHomeDirectory(),
            hostUUIDString()
        ].joined(separator: "\n")
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(seed.utf8)),
            salt: salt,
            info: Data("Mihomo LocalSecretVault v1".utf8),
            outputByteCount: 32
        )
    }

    private func makePassphraseKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw vaultError("Portable secret passphrase is empty.")
        }
        guard iterations >= 10_000 else {
            throw vaultError("Portable secret KDF iterations must be at least 10000.")
        }

        let passwordKey = SymmetricKey(data: Data(passphrase.utf8))
        var derived = Data()
        let blockSize = SHA256.Digest.byteCount
        let blockCount = Int(ceil(Double(32) / Double(blockSize)))

        for blockIndex in 1...blockCount {
            var block = salt
            var counter = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &counter) { block.append(contentsOf: $0) }

            var round = Data(HMAC<SHA256>.authenticationCode(for: block, using: passwordKey))
            var accumulated = round
            for _ in 1..<iterations {
                round = Data(HMAC<SHA256>.authenticationCode(for: round, using: passwordKey))
                accumulated.xor(with: round)
            }
            derived.append(accumulated)
        }

        return SymmetricKey(data: Data(derived.prefix(32)))
    }

    private func hostUUIDString() -> String {
        if let result = try? Shell.run("/usr/sbin/ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"]),
           result.status == 0 {
            for line in result.stdout.components(separatedBy: .newlines) where line.contains("IOPlatformUUID") {
                let parts = line.components(separatedBy: "\"")
                if parts.count >= 4 {
                    return parts[3]
                }
            }
        }
        return Host.current().localizedName ?? "unknown-host"
    }

    private func randomData(byteCount: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        }

        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return Data(bytes)
    }

    private func vaultError(_ message: String) -> NSError {
        NSError(domain: "LocalSecretVault", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct SecretVaultEnvelope: Codable {
    var version = 1
    var kdf = "HKDF-SHA256 host-user"
    var cipher = "AES-256-GCM"
    var salt: String
    var nonce: String
    var ciphertext: String
    var tag: String
    var updatedAt: Date
}

private struct PortableSecretBundle: Codable {
    var version = 1
    var kdf = "PBKDF2-HMAC-SHA256"
    var cipher = "AES-256-GCM"
    var iterations: Int
    var salt: String
    var nonce: String
    var ciphertext: String
    var tag: String
    var createdAt: Date
}

private extension Data {
    init(base64EncodedStrict value: String, field: String) throws {
        guard let data = Data(base64Encoded: value) else {
            throw NSError(domain: "LocalSecretVault", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Secret vault \(field) is not valid Base64."
            ])
        }
        self = data
    }

    mutating func xor(with other: Data) {
        for index in indices {
            self[index] ^= other[index]
        }
    }
}

extension AppSettings {
    var redactedSecretsForDisk: AppSettings {
        var copy = self
        copy.controllerSecret = ""
        copy.backupWebDAVPassword = ""
        copy.gistToken = ""
        return copy
    }

    var containsInlineSecrets: Bool {
        AppSecretValues(settings: self).isEmpty == false
    }

    mutating func applySecrets(_ secrets: AppSecretValues) {
        controllerSecret = secrets.controllerSecret
        backupWebDAVPassword = secrets.backupWebDAVPassword
        gistToken = secrets.gistToken
    }
}
