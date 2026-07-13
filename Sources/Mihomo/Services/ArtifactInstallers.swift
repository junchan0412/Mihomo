import Foundation

final class ManagedCoreManager {
    private let managedCoreFile: URL

    init(managedCoreFile: URL = AppPaths.managedCoreFile) {
        self.managedCoreFile = managedCoreFile
    }

    static var bundledCorePath: String? {
        Bundle.main.url(forResource: "mihomo", withExtension: nil, subdirectory: "Core")?.path
    }

    func installOrUpdate(from urlString: String, expectedSHA256: String = "") async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ManagedCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Core 下载 URL 无效"])
        }
        try AppPaths.ensureBaseDirectories()
        let (downloaded, _) = try await NetworkClient.download(from: url)
        return try installDownloadedArtifact(downloaded, sourceURL: url, expectedSHA256: expectedSHA256)
    }

    func installDownloadedArtifact(_ downloaded: URL, sourceURL: URL, expectedSHA256: String = "") throws -> String {
        try ArtifactChecksum.validate(fileURL: downloaded, expectedSHA256: expectedSHA256, artifactName: "mihomo core 下载包")
        try FileManager.default.createDirectory(at: managedCoreFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = managedCoreFile
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }

        if sourceURL.pathExtension.lowercased() == "gz" {
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

final class GeoUpdateManager {
    private let geoDirectory: URL

    init(geoDirectory: URL = AppPaths.geoDirectory) {
        self.geoDirectory = geoDirectory
    }

    func update(
        geoIPURL: String,
        geoSiteURL: String,
        countryMMDBURL: String,
        asnMMDBURL: String,
        geoIPSHA256: String,
        geoSiteSHA256: String,
        countryMMDBSHA256: String,
        asnMMDBSHA256: String
    ) async throws -> String {
        try AppPaths.ensureBaseDirectories()
        var updated: [String] = []
        let artifacts = [
            GeoArtifact(name: "GeoIP", fileName: "geoip.dat", url: geoIPURL, sha256: geoIPSHA256),
            GeoArtifact(name: "GeoSite", fileName: "geosite.dat", url: geoSiteURL, sha256: geoSiteSHA256),
            GeoArtifact(name: "Country MMDB", fileName: "Country.mmdb", url: countryMMDBURL, sha256: countryMMDBSHA256),
            GeoArtifact(name: "ASN MMDB", fileName: "ASN.mmdb", url: asnMMDBURL, sha256: asnMMDBSHA256)
        ]

        for artifact in artifacts where artifact.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            guard let url = URL(string: artifact.url) else {
                throw NSError(domain: "GeoUpdate", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(artifact.name) 下载 URL 无效。"
                ])
            }
            let checksum = try await resolvedChecksum(manual: artifact.sha256, for: url, artifactName: artifact.name)
            try await download(
                url: url,
                to: geoDirectory.appendingPathComponent(artifact.fileName),
                expectedSHA256: checksum,
                artifactName: "\(artifact.name) 数据"
            )
            updated.append(artifact.fileName)
        }
        return updated.isEmpty ? "没有可更新的 Geo URL" : "已更新 \(updated.joined(separator: "、"))"
    }

    func installDownloadedArtifact(
        _ downloaded: URL,
        to target: URL,
        expectedSHA256: String,
        artifactName: String
    ) throws {
        try ArtifactChecksum.validate(fileURL: downloaded, expectedSHA256: expectedSHA256, artifactName: artifactName)
        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryTarget = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent)-\(UUID().uuidString)")
        let backup = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent)-backup-\(UUID().uuidString)")
        try manager.copyItem(at: downloaded, to: temporaryTarget)
        var temporaryTargetNeedsCleanup = true
        defer {
            if temporaryTargetNeedsCleanup {
                try? manager.removeItem(at: temporaryTarget)
            }
        }
        let targetExists = manager.fileExists(atPath: target.path)
        if targetExists {
            try manager.moveItem(at: target, to: backup)
        }
        do {
            try manager.moveItem(at: temporaryTarget, to: target)
            temporaryTargetNeedsCleanup = false
            if targetExists {
                try? manager.removeItem(at: backup)
            }
        } catch {
            if targetExists, manager.fileExists(atPath: backup.path) {
                try? manager.moveItem(at: backup, to: target)
            }
            throw error
        }
    }

    private func download(url: URL, to target: URL, expectedSHA256: String, artifactName: String) async throws {
        let (temp, _) = try await NetworkClient.download(from: url)
        try installDownloadedArtifact(temp, to: target, expectedSHA256: expectedSHA256, artifactName: artifactName)
    }

    private func resolvedChecksum(manual: String, for url: URL, artifactName: String) async throws -> String {
        let trimmed = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }

        guard let checksumURL = URL(string: url.absoluteString + ".sha256sum") else {
            throw NSError(domain: "GeoUpdate", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "无法生成 \(artifactName) 校验文件 URL。"
            ])
        }
        let (data, response) = try await NetworkClient.data(from: checksumURL, kind: .download)
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) == false {
            throw NSError(domain: "GeoUpdate", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "\(artifactName) 校验文件下载失败：HTTP \(http.statusCode)。"
            ])
        }
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: #"[A-Fa-f0-9]{64}"#, options: .regularExpression) else {
            throw NSError(domain: "GeoUpdate", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "\(artifactName) 校验文件中没有有效 SHA-256。"
            ])
        }
        return String(text[range])
    }
}

private struct GeoArtifact {
    var name: String
    var fileName: String
    var url: String
    var sha256: String
}
