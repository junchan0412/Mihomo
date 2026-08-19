import Foundation
import Yams

struct ConfigFragmentRemoteResponse {
    var data: Data
    var response: URLResponse
    var certificateFingerprint: String?
}

protocol ConfigFragmentRemoteLoading {
    func fetch(_ url: URL, expectedFingerprint: String?) async throws -> ConfigFragmentRemoteResponse
}

struct CertificatePinnedConfigFragmentRemoteLoader: ConfigFragmentRemoteLoading {
    static let maximumRemoteFragmentBytes = 2 * 1024 * 1024

    func fetch(_ url: URL, expectedFingerprint: String?) async throws -> ConfigFragmentRemoteResponse {
        let session = CertificatePinningSession(expectedFingerprint: expectedFingerprint)
        let (data, response, fingerprint) = try await session.fetch(
            url,
            maxBytes: Self.maximumRemoteFragmentBytes
        )
        return ConfigFragmentRemoteResponse(
            data: data,
            response: response,
            certificateFingerprint: fingerprint
        )
    }
}

final class ConfigFragmentStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let remoteLoader: any ConfigFragmentRemoteLoading

    init(remoteLoader: any ConfigFragmentRemoteLoading = CertificatePinnedConfigFragmentRemoteLoader()) {
        self.remoteLoader = remoteLoader
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

    func importLocalFragment(
        fileURL: URL,
        name: String? = nil,
        kind explicitKind: ConfigFragmentKind? = nil
    ) throws -> ConfigFragment {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let kind = explicitKind ?? inferredKind(for: fileURL)
        try validateFragmentContent(content, kind: kind)
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ConfigFragment(
            name: normalizedName.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : normalizedName,
            kind: kind,
            enabled: true,
            content: content,
            source: .local,
            location: fileURL.path
        )
    }

    func importRemoteFragment(
        urlString: String,
        name: String? = nil,
        kind: ConfigFragmentKind
    ) async throws -> ConfigFragment {
        let url = try validatedRemoteURL(urlString)
        let payload = try await remoteLoader.fetch(url, expectedFingerprint: nil)
        let content = try validatedRemoteContent(payload, kind: kind)
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackName = url.deletingPathExtension().lastPathComponent
        return ConfigFragment(
            name: normalizedName.isEmpty ? (fallbackName.isEmpty ? url.host ?? "远程覆写" : fallbackName) : normalizedName,
            kind: kind,
            enabled: true,
            content: content,
            source: .remote,
            location: url.absoluteString,
            certificateFingerprint: payload.certificateFingerprint
        )
    }

    func refreshRemoteFragment(_ fragment: ConfigFragment) async throws -> ConfigFragment {
        guard fragment.isRemote else { return fragment }
        let url = try validatedRemoteURL(fragment.location)
        let payload = try await remoteLoader.fetch(url, expectedFingerprint: fragment.certificateFingerprint)
        let content = try validatedRemoteContent(payload, kind: fragment.kind)
        var updated = fragment
        updated.content = content
        updated.updatedAt = Date()
        updated.certificateFingerprint = payload.certificateFingerprint ?? fragment.certificateFingerprint
        return updated
    }

    func validateFragmentContent(_ content: String, kind: ConfigFragmentKind) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw fragmentError("覆写内容不能为空")
        }

        switch kind {
        case .yaml:
            guard content.lengthOfBytes(using: .utf8) <= 2 * 1024 * 1024 else {
                throw fragmentError("YAML 覆写不能超过 2 MiB")
            }
            do {
                guard let loaded = try Yams.load(yaml: content),
                      normalizeYAMLValue(loaded) is [String: Any]
                else {
                    throw fragmentError("YAML 覆写必须是顶层映射")
                }
            } catch let error as NSError where error.domain == "Mihomo.ConfigFragment" {
                throw error
            } catch {
                throw fragmentError("YAML 解析失败：\(error.localizedDescription)")
            }
        case .javascript:
            guard content.lengthOfBytes(using: .utf8) <= JSOverrideRunner.maximumFragmentBytes else {
                throw fragmentError("JavaScript 覆写不能超过 \(JSOverrideRunner.maximumFragmentBytes / 1024) KiB")
            }
        }
    }

    func inferredKind(for fileURL: URL) -> ConfigFragmentKind {
        switch fileURL.pathExtension.lowercased() {
        case "js", "mjs", "cjs": return .javascript
        default: return .yaml
        }
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

    func normalizeYAMLValue(_ value: Any) -> Any {
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

    private func validatedRemoteURL(_ value: String) throws -> URL {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw fragmentError("请输入有效的 HTTP 或 HTTPS URL")
        }
        return url
    }

    private func validatedRemoteContent(
        _ payload: ConfigFragmentRemoteResponse,
        kind: ConfigFragmentKind
    ) throws -> String {
        guard let response = payload.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else {
            let status = (payload.response as? HTTPURLResponse)?.statusCode
            throw fragmentError(status.map { "远程覆写请求失败（HTTP \($0)）" } ?? "远程覆写请求失败")
        }
        guard let content = String(data: payload.data, encoding: .utf8) else {
            throw fragmentError("远程覆写不是有效的 UTF-8 文本")
        }
        let normalized = content.first == "\u{feff}" ? String(content.dropFirst()) : content
        try validateFragmentContent(normalized, kind: kind)
        return normalized
    }

    private func fragmentError(_ message: String) -> NSError {
        NSError(
            domain: "Mihomo.ConfigFragment",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

}
