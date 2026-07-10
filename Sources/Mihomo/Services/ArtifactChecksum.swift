import CryptoKit
import Foundation

enum ArtifactChecksum {
    static func validate(fileURL: URL, expectedSHA256: String, artifactName: String) throws {
        let expected = normalizedSHA256(expectedSHA256)
        guard expected.isEmpty == false else {
            throw checksumError("\(artifactName) 缺少 SHA-256，拒绝安装未校验的下载内容。")
        }
        guard expected.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw checksumError("\(artifactName) SHA-256 必须是 64 位十六进制。")
        }

        let actual = try sha256(fileURL: fileURL)
        guard actual == expected else {
            throw checksumError("\(artifactName) SHA-256 不匹配：期望 \(expected)，实际 \(actual)。已保留当前文件。")
        }
    }

    static func sha256(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func normalizedSHA256(_ value: String) -> String {
        value.lowercased()
            .filter { $0.isHexDigit }
            .map(String.init)
            .joined()
    }

    private static func checksumError(_ message: String) -> NSError {
        NSError(domain: "ArtifactChecksum", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}
