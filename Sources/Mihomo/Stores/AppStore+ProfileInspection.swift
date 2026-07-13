import Foundation

extension AppStore {
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
                icon: group.icon,
                hidden: group.hidden
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
}
