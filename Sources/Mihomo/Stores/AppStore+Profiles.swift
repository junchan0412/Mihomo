import AppKit
import Foundation

extension AppStore {
    func revealProfileStorageDirectory() {
        let directory = profileStorageDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func changeProfileStorageDirectory(to directory: URL) async {
        do {
            let oldSettings = settings
            try profileStore.migrateProfileStorage(profiles: profiles, from: oldSettings, to: directory)
            var updated = settings
            updated.profileStoragePath = directory.standardizedFileURL.path
            settings = updated
            try profileStore.saveSettings(updated)
            refreshConfigArtifacts()
            appendLog("info", "配置存储路径已切换：\(updated.profileStoragePath)")
        } catch {
            appendLog("error", "配置存储路径切换失败：\(error.localizedDescription)")
        }
    }

    func addRemoteProfile() async {
        let url = newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        do {
            let item = try await profileStore.importRemoteProfile(
                urlString: url,
                name: newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines),
                settings: settings
            )
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            newRemoteURL = ""
            newRemoteName = ""
            refreshConfigArtifacts()
            appendLog("info", "已导入远程订阅 \(item.name)")
        } catch {
            appendLog("error", "远程订阅导入失败：\(error.localizedDescription)")
        }
    }

    func importLocalProfile(url: URL) async {
        do {
            let item = try profileStore.importLocalProfile(fileURL: url, settings: settings)
            profiles.append(item)
            settings.activeProfileID = item.id
            try profileStore.saveProfiles(profiles)
            try profileStore.saveSettings(settings)
            refreshConfigArtifacts()
            appendLog("info", "已导入本地配置 \(item.name)")
        } catch {
            appendLog("error", "本地配置导入失败：\(error.localizedDescription)")
        }
    }

    func refreshProfile(_ profile: ProfileItem) async {
        do {
            let updated = try await profileStore.refreshRemoteProfile(profile, settings: settings)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
                try profileStore.saveProfiles(profiles)
            }
            refreshConfigArtifacts()
            appendLog("info", "已刷新配置 \(profile.name)")
        } catch {
            appendLog("error", "配置刷新失败：\(error.localizedDescription)")
        }
    }

    func refreshAllRemoteProfiles() async {
        guard profileRefreshQueueRunning == false else {
            appendLog("warning", "订阅刷新队列已在运行")
            return
        }

        let remoteProfiles = profiles.filter(\.isRemote)
        guard remoteProfiles.isEmpty == false else {
            profileAutoRefreshStatus = "没有远程订阅"
            return
        }

        profileRefreshQueueRunning = true
        defer { profileRefreshQueueRunning = false }

        profileRefreshFailureCount = 0
        profileRefreshQueue = remoteProfiles.map { profile in
            ProfileRefreshJob(
                profileID: profile.id,
                profileName: profile.name,
                state: .pending,
                message: "等待队列执行",
                startedAt: nil,
                finishedAt: nil
            )
        }
        profileAutoRefreshStatus = "队列运行中：0/\(remoteProfiles.count)"

        var pendingProfiles = remoteProfiles
        var runningTasks: [Task<ProfileRefreshResult, Never>] = []
        let maxConcurrent = max(1, settings.profileRefreshMaxConcurrent)
        let refreshSettings = settings
        var completed = 0
        var succeeded = 0
        var failed = 0

        while pendingProfiles.isEmpty == false || runningTasks.isEmpty == false {
            while runningTasks.count < maxConcurrent, pendingProfiles.isEmpty == false {
                let profile = pendingProfiles.removeFirst()
                markRefreshJob(profileID: profile.id, state: .running, message: "正在刷新", startedAt: Date(), finishedAt: nil)
                runningTasks.append(Task {
                    let store = ProfileStore()
                    do {
                        let updated = try await store.refreshRemoteProfile(profile, settings: refreshSettings)
                        return ProfileRefreshResult(profileID: profile.id, updated: updated, errorMessage: nil)
                    } catch {
                        return ProfileRefreshResult(profileID: profile.id, updated: nil, errorMessage: error.localizedDescription)
                    }
                })
            }

            guard runningTasks.isEmpty == false else { break }
            let result = await runningTasks.removeFirst().value
            completed += 1

            if let updated = result.updated {
                if let index = profiles.firstIndex(where: { $0.id == result.profileID }) {
                    profiles[index] = updated
                    try? profileStore.saveProfiles(profiles)
                }
                refreshConfigArtifacts()
                succeeded += 1
                markRefreshJob(profileID: result.profileID, state: .succeeded, message: "刷新成功", finishedAt: Date())
            } else {
                failed += 1
                profileRefreshFailureCount = failed
                let profileName = profileRefreshQueue.first { $0.profileID == result.profileID }?.profileName ?? "订阅"
                let message = result.errorMessage ?? "未知错误"
                markRefreshJob(profileID: result.profileID, state: .failed, message: message, finishedAt: Date())
                notificationManager.notify(title: "订阅刷新失败", body: "\(profileName)：\(message)")
                appendLog("error", "订阅刷新失败 \(profileName)：\(message)")
            }
            profileAutoRefreshStatus = "队列运行中：\(completed)/\(remoteProfiles.count)，成功 \(succeeded)，失败 \(failed)"
        }

        profileAutoRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 \(succeeded)/\(remoteProfiles.count)，失败 \(failed)"
    }

    func setActiveProfile(_ profile: ProfileItem) async {
        settings.activeProfileID = profile.id
        do {
            try profileStore.saveSettings(settings)
            refreshConfigArtifacts()
            appendLog("info", "已启用配置 \(profile.name)")
            if isCoreRunning {
                await restartCore()
            }
        } catch {
            appendLog("error", "配置切换失败：\(error.localizedDescription)")
        }
    }

    func profileContent(for profile: ProfileItem) -> String {
        do {
            return try profileStore.loadProfileContent(profile, settings: settings)
        } catch {
            appendLog("error", "读取配置失败：\(error.localizedDescription)")
            return ""
        }
    }

    func saveProfileEditor(profileID: UUID, name: String, content: String) async {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        do {
            var profile = profiles[index]
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? profile.name : name
            let updated = try profileStore.saveProfileContent(profile, content: content, settings: settings)
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
            refreshConfigArtifacts()
            appendLog("info", "已保存配置 \(updated.name)")
        } catch {
            appendLog("error", "保存配置失败：\(error.localizedDescription)")
        }
    }

    func deleteProfile(_ profile: ProfileItem) async {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        do {
            let file = profileStore.profileFile(profile, settings: settings)
            profiles.remove(at: index)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            if settings.activeProfileID == profile.id {
                settings.activeProfileID = profiles.first?.id
                try profileStore.saveSettings(settings)
            }
            try profileStore.saveProfiles(profiles)
            if profileEditorProfileID == profile.id {
                profileEditorProfileID = settings.activeProfileID
            }
            refreshConfigArtifacts()
            appendLog("info", "已删除配置 \(profile.name)")
        } catch {
            appendLog("error", "删除配置失败：\(error.localizedDescription)")
        }
    }

    func profileStats(for profile: ProfileItem) -> ProfileStats {
        let fingerprint = profileStatsFingerprint(for: profile)
        if let cached = profileStatsCache[profile.id], cached.fingerprint == fingerprint {
            return cached.stats
        }

        do {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            let snapshot = try ProfileYAMLStructureEditor().snapshot(content: content)
            let providers = configFragmentStore.parseProviders(profileContent: content)
            let stats = ProfileStats(
                lineCount: content.split(separator: "\n", omittingEmptySubsequences: false).count,
                fileSize: content.data(using: .utf8)?.count ?? 0,
                policyGroupCount: snapshot.groups.count,
                proxyCount: snapshot.proxyNames.count,
                ruleCount: snapshot.rules.count,
                proxyProviderCount: providers.filter { $0.kind == "Proxy" }.count,
                ruleProviderCount: providers.filter { $0.kind == "Rule" }.count,
                errorMessage: nil
            )
            profileStatsCache[profile.id] = ProfileStatsCacheEntry(fingerprint: fingerprint, stats: stats)
            return stats
        } catch {
            let stats = ProfileStats(errorMessage: error.localizedDescription)
            profileStatsCache[profile.id] = ProfileStatsCacheEntry(fingerprint: fingerprint, stats: stats)
            return stats
        }
    }

    func profileQualityReport(for profile: ProfileItem?) -> ProfileQualityReport {
        guard let profile else { return .empty }
        let fingerprint = profileQualityFingerprint(for: profile)
        if let cached = profileQualityCache[profile.id], cached.fingerprint == fingerprint {
            return cached.report
        }

        do {
            let content = try profileStore.loadProfileContent(profile, settings: settings)
            let report = profileQualityAnalyzer.analyze(
                profile: profile,
                profileContent: content,
                settings: settings,
                fragments: configFragments,
                disabledRules: disabledRules,
                migrationLog: settingsMigrationLog
            )
            profileQualityCache[profile.id] = ProfileQualityCacheEntry(fingerprint: fingerprint, report: report)
            return report
        } catch {
            let report = ProfileQualityReport(
                score: 0,
                headline: "配置无法读取",
                issues: [
                    .init(
                        severity: .error,
                        title: "Profile 读取失败",
                        detail: error.localizedDescription
                    )
                ],
                runtimeItems: [],
                sourceItems: [],
                diffLayers: [],
                migrationLog: settingsMigrationLog,
                generatedConfig: ""
            )
            profileQualityCache[profile.id] = ProfileQualityCacheEntry(fingerprint: fingerprint, report: report)
            return report
        }
    }

    func makeOfflineProxyGroups(from snapshot: ProfileStructureSnapshot) -> [ProxyGroup] {
        snapshot.groups.map { group in
            let proxyNodes = group.proxies.map { proxy in
                ProxyNode(name: proxy, type: snapshot.proxyNames.contains(proxy) ? "proxy" : "built-in", delay: nil)
            }
            let providerNodes = group.uses.map { provider in
                ProxyNode(name: provider, type: "provider", delay: nil)
            }
            return ProxyGroup(
                name: group.name,
                type: group.type,
                now: "",
                all: proxyNodes + providerNodes,
                icon: nil
            )
        }
    }

    private func profileStatsFingerprint(for profile: ProfileItem) -> ProfileStatsFingerprint {
        ProfileStatsFingerprint(
            fileName: profile.fileName,
            location: profile.location,
            updatedAt: profile.updatedAt,
            profileStoragePath: settings.profileStoragePath
        )
    }

    private func profileQualityFingerprint(for profile: ProfileItem) -> ProfileQualityFingerprint {
        ProfileQualityFingerprint(
            profile: profileStatsFingerprint(for: profile),
            settings: settings,
            fragments: configFragments,
            disabledRules: disabledRules,
            migrationLog: settingsMigrationLog
        )
    }

    private func markRefreshJob(
        profileID: UUID,
        state: ProfileRefreshJobState,
        message: String,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        guard let index = profileRefreshQueue.firstIndex(where: { $0.profileID == profileID }) else { return }
        profileRefreshQueue[index].state = state
        profileRefreshQueue[index].message = message
        if let startedAt {
            profileRefreshQueue[index].startedAt = startedAt
        }
        if let finishedAt {
            profileRefreshQueue[index].finishedAt = finishedAt
        }
    }
}

private struct ProfileRefreshResult {
    var profileID: UUID
    var updated: ProfileItem?
    var errorMessage: String?
}

struct ProfileStatsFingerprint: Hashable {
    var fileName: String
    var location: String
    var updatedAt: Date
    var profileStoragePath: String
}

struct ProfileQualityFingerprint: Hashable {
    var profile: ProfileStatsFingerprint
    var settings: AppSettings
    var fragments: [ConfigFragment]
    var disabledRules: Set<String>
    var migrationLog: [String]
}

struct ProfileStatsCacheEntry {
    var fingerprint: ProfileStatsFingerprint
    var stats: ProfileStats
}

struct ProfileQualityCacheEntry {
    var fingerprint: ProfileQualityFingerprint
    var report: ProfileQualityReport
}
