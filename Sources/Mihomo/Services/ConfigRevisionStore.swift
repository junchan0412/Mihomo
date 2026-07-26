import Foundation

final class ConfigRevisionStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let ageService = ProfileAgeService()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadIndex() throws -> [ConfigRevision] {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.configRevisionsIndexFile.path) else { return [] }
        return try decoder.decode([ConfigRevision].self, from: Data(contentsOf: AppPaths.configRevisionsIndexFile))
    }

    func saveIndex(_ revisions: [ConfigRevision]) throws {
        try AppPaths.ensureBaseDirectories()
        try encoder.encode(revisions).write(to: AppPaths.configRevisionsIndexFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.configRevisionsIndexFile.path)
    }

    func writeSnapshot(_ content: String, revision: ConfigRevision, settings: AppSettings) throws {
        try AppPaths.ensureBaseDirectories()
        let stored = try ageService.encryptedContent(content, settings: settings)
        let url = AppPaths.configRevisionsDirectory.appendingPathComponent(revision.fileName)
        try stored.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func readSnapshot(_ revision: ConfigRevision, settings: AppSettings) throws -> String {
        let url = AppPaths.configRevisionsDirectory.appendingPathComponent(revision.fileName)
        let stored = try String(contentsOf: url, encoding: .utf8)
        return try ageService.decryptedContent(stored, settings: settings)
    }

    func removeSnapshot(_ revision: ConfigRevision) {
        try? FileManager.default.removeItem(at: AppPaths.configRevisionsDirectory.appendingPathComponent(revision.fileName))
    }
}
