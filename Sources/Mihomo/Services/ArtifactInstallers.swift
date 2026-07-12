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

final class ExternalUIManager {
    private let externalUIDirectory: URL
    private let runtimeDirectory: URL

    init(
        externalUIDirectory: URL = AppPaths.externalUIDirectory,
        runtimeDirectory: URL = AppPaths.runtimeDirectory
    ) {
        self.externalUIDirectory = externalUIDirectory
        self.runtimeDirectory = runtimeDirectory
    }

    func install(name: String, from urlString: String, expectedSHA256: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ExternalUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "外部 UI 下载 URL 无效"])
        }
        try AppPaths.ensureBaseDirectories()
        let (downloaded, _) = try await NetworkClient.download(from: url)
        return try installDownloadedArchive(
            downloaded,
            name: name,
            sourceURL: url,
            expectedSHA256: expectedSHA256
        )
    }

    func installDownloadedArchive(
        _ downloaded: URL,
        name: String,
        sourceURL: URL,
        expectedSHA256: String
    ) throws -> String {
        try ArtifactChecksum.validate(fileURL: downloaded, expectedSHA256: expectedSHA256, artifactName: "外部 UI 下载包")
        let cleanedName = try validatedName(name)
        let target = externalUIDirectory.appendingPathComponent(cleanedName, isDirectory: true)
        let tempRoot = runtimeDirectory.appendingPathComponent("external-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        if sourceURL.pathExtension.lowercased() == "zip" {
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
        try validateWebRoot(root)
        let stagedTarget = externalUIDirectory.appendingPathComponent(".\(cleanedName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagedTarget, withIntermediateDirectories: true)
        var stagedTargetNeedsCleanup = true
        defer {
            if stagedTargetNeedsCleanup {
                try? FileManager.default.removeItem(at: stagedTarget)
            }
        }
        for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: item, to: stagedTarget.appendingPathComponent(item.lastPathComponent))
        }
        try replaceInstallation(at: target, with: stagedTarget)
        stagedTargetNeedsCleanup = false
        return target.path
    }

    func status(name: String) -> String {
        let path = externalUIDirectory
            .appendingPathComponent((try? validatedName(name)) ?? "external-ui", isDirectory: true)
            .appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: path.path) ? path.deletingLastPathComponent().path : "未安装"
    }

    private func validatedName(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "external-ui" : name
        guard cleaned != ".", cleaned != "..", cleaned.contains("/") == false, cleaned.contains("\\") == false else {
            throw NSError(domain: "ExternalUI", code: 4, userInfo: [NSLocalizedDescriptionKey: "外部 UI 名称不能包含路径分隔符"])
        }
        return cleaned
    }

    private func validateWebRoot(_ root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "ExternalUI", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法读取外部 UI 内容"])
        }
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw NSError(domain: "ExternalUI", code: 6, userInfo: [NSLocalizedDescriptionKey: "外部 UI 压缩包包含符号链接，已拒绝安装"])
            }
        }
    }

    private func replaceInstallation(at target: URL, with stagedTarget: URL) throws {
        let manager = FileManager.default
        let backup = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent)-backup-\(UUID().uuidString)", isDirectory: true)
        let targetExists = manager.fileExists(atPath: target.path)
        if targetExists {
            try manager.moveItem(at: target, to: backup)
        }
        do {
            try manager.moveItem(at: stagedTarget, to: target)
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
    private let geoDirectory: URL

    init(geoDirectory: URL = AppPaths.geoDirectory) {
        self.geoDirectory = geoDirectory
    }

    func update(
        geoIPURL: String,
        geoSiteURL: String,
        geoIPSHA256: String,
        geoSiteSHA256: String
    ) async throws -> String {
        try AppPaths.ensureBaseDirectories()
        var updated: [String] = []
        if let url = URL(string: geoIPURL), geoIPURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try await download(
                url: url,
                to: geoDirectory.appendingPathComponent("geoip.dat"),
                expectedSHA256: geoIPSHA256,
                artifactName: "GeoIP 数据"
            )
            updated.append("geoip.dat")
        }
        if let url = URL(string: geoSiteURL), geoSiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            try await download(
                url: url,
                to: geoDirectory.appendingPathComponent("geosite.dat"),
                expectedSHA256: geoSiteSHA256,
                artifactName: "GeoSite 数据"
            )
            updated.append("geosite.dat")
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
}


