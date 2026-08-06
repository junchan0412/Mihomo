import Foundation

extension AppStore {
    func refreshGeoDataStatus() {
        let expected = ["geoip.dat", "geosite.dat", "Country.mmdb", "ASN.mmdb"]
        let existing = expected.filter {
            FileManager.default.fileExists(atPath: AppPaths.geoDirectory.appendingPathComponent($0).path)
        }
        geoUpdateStatus = existing.count == expected.count
            ? "四项 Geo 数据完整"
            : "Geo 数据 \(existing.count)/\(expected.count) 项"
    }

    @discardableResult
    func updateProviderResource(_ provider: ProviderItem) async -> Bool {
        do {
            let result = try await ProviderResourceManager().download(provider)
            let backupSuffix = result.backup.map { "；已备份上一版：\($0.path)" } ?? ""
            resourceUpdateStatus = "\(provider.name) 已更新：\(result.target.path)\(backupSuffix)；\(result.validationSummary)"
            appendLog("info", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "下载",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus,
                backupPath: result.backup?.path
            )
            refreshConfigArtifacts()
            return true
        } catch {
            resourceUpdateStatus = "\(provider.name) 更新失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "下载",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    func refreshProviderResource(_ provider: ProviderItem) async -> Bool {
        if provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return await updateProviderResource(provider)
        }

        do {
            let result = try ProviderResourceManager().refreshLocal(provider)
            resourceUpdateStatus = "\(provider.name) 已重新载入：\(Formatters.bytes(result.size))；\(result.validationSummary)"
            recordProviderUpdate(
                provider,
                action: "本地刷新",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus
            )
            refreshConfigArtifacts()
            return true
        } catch {
            resourceUpdateStatus = "\(provider.name) 重新载入失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "本地刷新",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription
            )
            return false
        }
    }

    func providerUpdateHistory(for provider: ProviderItem) -> [ProviderUpdateRecord] {
        providerUpdateHistory.filter {
            providerHistoryKey(kind: $0.providerKind, name: $0.providerName) == providerHistoryKey(for: provider)
        }
    }

    func providerHistoryKey(for provider: ProviderItem) -> String {
        providerHistoryKey(kind: provider.kind, name: provider.name)
    }

    func providerHistoryKey(kind: String, name: String) -> String {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedKind)\u{1F}\(normalizedName)"
    }

    func latestProviderRollbackRecord(for provider: ProviderItem) -> ProviderUpdateRecord? {
        let key = providerHistoryKey(for: provider)
        return providerUpdateHistory.first { record in
            guard providerHistoryKey(kind: record.providerKind, name: record.providerName) == key else {
                return false
            }
            guard let path = record.backupPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  path.isEmpty == false
            else {
                return false
            }
            return FileManager.default.fileExists(atPath: path)
        }
    }

    func rollbackProviderResource(_ provider: ProviderItem) async {
        guard let record = latestProviderRollbackRecord(for: provider),
              let backupPath = record.backupPath
        else {
            resourceUpdateStatus = "\(provider.name) 没有可用的 Provider 备份。"
            appendLog("warning", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: resourceUpdateStatus
            )
            return
        }

        do {
            let result = try ProviderResourceManager().rollback(provider, from: URL(fileURLWithPath: backupPath))
            resourceUpdateStatus = "\(provider.name) 已回滚：\(result.restoredFrom.path)"
            appendLog("info", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: true,
                targetPath: result.target.path,
                message: resourceUpdateStatus,
                backupPath: result.replacedBackup?.path,
                restoredFromPath: result.restoredFrom.path
            )
            refreshConfigArtifacts()
        } catch {
            resourceUpdateStatus = "\(provider.name) 回滚失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
            recordProviderUpdate(
                provider,
                action: "回滚",
                succeeded: false,
                targetPath: provider.path ?? "-",
                message: error.localizedDescription,
                restoredFromPath: backupPath
            )
        }
    }

    func updateGeoDataInternal() async throws -> String {
        let status = try await geoUpdateManager.update(
            geoIPURL: settings.geoIPURL,
            geoSiteURL: settings.geoSiteURL,
            countryMMDBURL: settings.countryMMDBURL,
            asnMMDBURL: settings.asnMMDBURL,
            geoIPSHA256: settings.geoIPSHA256,
            geoSiteSHA256: settings.geoSiteSHA256,
            countryMMDBSHA256: settings.countryMMDBSHA256,
            asnMMDBSHA256: settings.asnMMDBSHA256
        )
        try syncGeoDataToRuntimeDirectory()
        geoUpdateStatus = status
        return status
    }

    func syncGeoDataToRuntimeDirectory() throws {
        try AppPaths.ensureBaseDirectories()
        let pairs: [(source: String, targets: [String])] = [
            ("geoip.dat", ["geoip.dat", "GeoIP.dat"]),
            ("geosite.dat", ["geosite.dat", "GeoSite.dat"]),
            ("Country.mmdb", ["Country.mmdb"]),
            ("ASN.mmdb", ["ASN.mmdb"])
        ]
        for pair in pairs {
            let source = AppPaths.geoDirectory.appendingPathComponent(pair.source)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            for targetName in pair.targets {
                let target = AppPaths.runtimeDirectory.appendingPathComponent(targetName)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: source, to: target)
            }
        }
    }

    func loadProviderUpdateHistory() -> [ProviderUpdateRecord] {
        guard FileManager.default.fileExists(atPath: AppPaths.providerUpdateHistoryFile.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: AppPaths.providerUpdateHistoryFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ProviderUpdateRecord].self, from: data)
        } catch {
            appendLog("warning", "Provider 更新历史读取失败：\(error.localizedDescription)")
            return []
        }
    }

    private func recordProviderUpdate(
        _ provider: ProviderItem,
        action: String,
        succeeded: Bool,
        targetPath: String,
        message: String,
        backupPath: String? = nil,
        restoredFromPath: String? = nil
    ) {
        recordProviderUpdates([.init(
            providerName: provider.name,
            providerKind: provider.kind,
            action: action,
            succeeded: succeeded,
            targetPath: targetPath,
            message: message,
            backupPath: backupPath,
            restoredFromPath: restoredFromPath
        )])
    }

    func recordProviderUpdates(_ records: [ProviderUpdateRecord]) {
        guard records.isEmpty == false else { return }
        providerUpdateHistory.insert(contentsOf: records.reversed(), at: 0)
        if providerUpdateHistory.count > 500 {
            providerUpdateHistory.removeLast(providerUpdateHistory.count - 500)
        }
        saveProviderUpdateHistory()
    }

    private func saveProviderUpdateHistory() {
        do {
            try AppPaths.ensureBaseDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(providerUpdateHistory)
            try data.write(to: AppPaths.providerUpdateHistoryFile, options: .atomic)
        } catch {
            appendLog("warning", "Provider 更新历史保存失败：\(error.localizedDescription)")
        }
    }

}
