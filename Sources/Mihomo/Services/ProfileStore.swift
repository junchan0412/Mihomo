import Foundation

final class ProfileStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSettings() throws -> AppSettings {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.settingsFile.path) else {
            var settings = AppSettings.default
            settings.mihomoPath = locateMihomoBinary() ?? ""
            try saveSettings(settings)
            return settings
        }
        let data = try Data(contentsOf: AppPaths.settingsFile)
        return try decoder.decode(AppSettings.self, from: data)
    }

    func saveSettings(_ settings: AppSettings) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(settings)
        try data.write(to: AppPaths.settingsFile, options: .atomic)
    }

    func loadProfiles() throws -> [ProfileItem] {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.profilesFile.path) else {
            let item = try createDefaultProfile()
            try saveProfiles([item])
            return [item]
        }
        let data = try Data(contentsOf: AppPaths.profilesFile)
        let profiles = try decoder.decode([ProfileItem].self, from: data)
        if profiles.isEmpty {
            let item = try createDefaultProfile()
            try saveProfiles([item])
            return [item]
        }
        return profiles
    }

    func saveProfiles(_ profiles: [ProfileItem]) throws {
        try AppPaths.ensureBaseDirectories()
        let data = try encoder.encode(profiles)
        try data.write(to: AppPaths.profilesFile, options: .atomic)
    }

    func createDefaultProfile() throws -> ProfileItem {
        let id = UUID()
        let fileName = "\(id.uuidString).yaml"
        let url = AppPaths.profilesDirectory.appendingPathComponent(fileName)
        try defaultProfileYAML.write(to: url, atomically: true, encoding: .utf8)
        return ProfileItem(
            id: id,
            name: "Blank Profile",
            source: .local,
            location: url.path,
            fileName: fileName,
            updatedAt: Date()
        )
    }

    func importLocalProfile(fileURL: URL, name: String? = nil) throws -> ProfileItem {
        try AppPaths.ensureBaseDirectories()
        let id = UUID()
        let fileName = "\(id.uuidString).yaml"
        let target = AppPaths.profilesDirectory.appendingPathComponent(fileName)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        try content.write(to: target, atomically: true, encoding: .utf8)
        return ProfileItem(
            id: id,
            name: name?.isEmpty == false ? name! : fileURL.deletingPathExtension().lastPathComponent,
            source: .local,
            location: fileURL.path,
            fileName: fileName,
            updatedAt: Date()
        )
    }

    func importRemoteProfile(urlString: String, name: String? = nil) async throws -> ProfileItem {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Mihomo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid subscription URL"])
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Mihomo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Subscription request failed"])
        }

        let id = UUID()
        let fileName = "\(id.uuidString).yaml"
        let target = AppPaths.profilesDirectory.appendingPathComponent(fileName)
        try data.write(to: target, options: .atomic)

        var item = ProfileItem(
            id: id,
            name: name?.isEmpty == false ? name! : url.host ?? "Remote Profile",
            source: .remote,
            location: urlString,
            fileName: fileName,
            updatedAt: Date()
        )
        applySubscriptionInfo(response: http, to: &item)
        return item
    }

    func refreshRemoteProfile(_ profile: ProfileItem) async throws -> ProfileItem {
        guard profile.source == .remote, let url = URL(string: profile.location) else {
            return profile
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Mihomo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Subscription refresh failed"])
        }
        try data.write(to: profileFile(profile), options: .atomic)
        var updated = profile
        updated.updatedAt = Date()
        applySubscriptionInfo(response: http, to: &updated)
        return updated
    }

    func profileFile(_ profile: ProfileItem) -> URL {
        AppPaths.profilesDirectory.appendingPathComponent(profile.fileName)
    }

    func generateRuntimeConfig(profile: ProfileItem, settings: AppSettings) throws -> URL {
        try AppPaths.ensureBaseDirectories()
        let profileContent = try String(contentsOf: profileFile(profile), encoding: .utf8)
        let overlay = runtimeOverlay(settings: settings)
        let content = [
            "# Generated by Mihomo macOS MVP. Edit the source profile instead of this file.",
            profileContent,
            overlay
        ].joined(separator: "\n\n")
        try content.write(to: AppPaths.runtimeConfigFile, atomically: true, encoding: .utf8)
        return AppPaths.runtimeConfigFile
    }

    func locateMihomoBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo",
            "/usr/bin/mihomo",
            "/opt/homebrew/bin/clash",
            "/usr/local/bin/clash"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        if let result = try? Shell.run("/usr/bin/which", ["mihomo"]), result.status == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return nil
    }

    private func runtimeOverlay(settings: AppSettings) -> String {
        var lines: [String] = [
            "mixed-port: \(settings.mixedPort)",
            "socks-port: \(settings.socksPort)",
            "allow-lan: \(settings.allowLAN ? "true" : "false")",
            "mode: rule",
            "log-level: \(settings.logLevel)",
            "external-controller: \(settings.controllerHost):\(settings.controllerPort)"
        ]

        if settings.tunEnabled {
            lines.append(
                """
                tun:
                  enable: true
                  stack: system
                  auto-route: true
                  auto-detect-interface: true
                  dns-hijack:
                    - any:53
                """
            )
        }

        return lines.joined(separator: "\n")
    }

    private func applySubscriptionInfo(response: HTTPURLResponse, to item: inout ProfileItem) {
        guard let value = response.value(forHTTPHeaderField: "subscription-userinfo") else { return }
        let pairs = value.split(separator: ";").reduce(into: [String: Int64]()) { result, part in
            let components = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if components.count == 2 {
                result[components[0]] = Int64(components[1])
            }
        }
        item.uploadUsed = pairs["upload"]
        item.downloadUsed = pairs["download"]
        item.total = pairs["total"]
        if let expire = pairs["expire"] {
            item.expireAt = Date(timeIntervalSince1970: TimeInterval(expire))
        }
    }

    private var defaultProfileYAML: String {
        """
        proxies: []
        proxy-groups:
          - name: GLOBAL
            type: select
            proxies:
              - DIRECT
        rules:
          - MATCH,DIRECT
        """
    }
}
