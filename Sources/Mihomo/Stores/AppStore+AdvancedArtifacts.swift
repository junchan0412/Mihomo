import Foundation

extension AppStore {
    func installManagedCore() async {
        do {
            managedCoreStatus = "正在下载 mihomo core..."
            let version = try await managedCoreManager.installOrUpdate(
                from: settings.managedCoreDownloadURL,
                expectedSHA256: settings.managedCoreSHA256
            )
            managedCoreStatus = version.isEmpty ? AppPaths.managedCoreFile.path : version
            var updated = settings
            updated.coreSource = .managed
            updated.managedCoreEnabled = true
            await saveSettings(updated)
            appendLog("info", "托管 mihomo core 已更新")
        } catch {
            managedCoreStatus = "核心更新失败：\(error.localizedDescription)"
            appendLog("error", managedCoreStatus)
        }
    }

    func updateGeoData() async {
        do {
            geoUpdateStatus = "正在更新 Geo 数据..."
            geoUpdateStatus = try await updateGeoDataInternal()
            appendLog("info", geoUpdateStatus)
        } catch {
            geoUpdateStatus = "Geo 更新失败：\(error.localizedDescription)"
            appendLog("error", geoUpdateStatus)
        }
    }

    func installAgeTools(downloadURL: String? = nil, expectedSHA256: String? = nil) async {
        do {
            ageStatus = "正在下载 Age 工具"
            let source = downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? downloadURL! : settings.ageDownloadURL
            let checksum = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? settings.ageDownloadSHA256
            let tools = try await profileAgeService.installTools(from: source, expectedSHA256: checksum)
            var updated = settings
            updated.ageDownloadURL = source
            updated.ageDownloadSHA256 = checksum
            updated.ageBinaryPath = tools.agePath
            updated.ageKeygenPath = tools.keygenPath
            try profileStore.saveSettings(updated)
            settings = updated
            ageStatus = "Age 工具已安装：\(tools.agePath)"
            appendLog("info", ageStatus)
        } catch {
            ageStatus = "Age 工具安装失败：\(error.localizedDescription)"
            appendLog("error", ageStatus)
        }
    }

    func generateAgeIdentity(draftSettings: AppSettings? = nil) async {
        do {
            var draft = draftSettings ?? settings
            if draft.ageIdentityPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.ageIdentityPath = AppPaths.ageIdentityFile.path
            }
            let identity = try profileAgeService.ensureIdentity(settings: draft)
            var updated = settings
            updated.ageDownloadURL = draft.ageDownloadURL
            updated.ageBinaryPath = draft.ageBinaryPath
            updated.ageKeygenPath = draft.ageKeygenPath
            updated.ageIdentityPath = identity.identityPath
            updated.ageRecipient = identity.recipient
            try profileStore.saveSettings(updated)
            settings = updated
            ageStatus = "Age 身份已就绪：\(identity.recipient)"
            appendLog("info", ageStatus)
        } catch {
            ageStatus = "Age 身份生成失败：\(error.localizedDescription)"
            appendLog("error", ageStatus)
        }
    }

    func migrateProfileEncryptionNow() async {
        do {
            try profileStore.migrateProfileEncryption(profiles, settings: settings)
            ageStatus = settings.profileEncryptionEnabled ? "现有 Profile 已加密" : "现有 Profile 已解密"
            refreshConfigArtifacts()
            appendLog("info", ageStatus)
        } catch {
            ageStatus = "Profile 加密迁移失败：\(error.localizedDescription)"
            appendLog("error", ageStatus)
        }
    }
}
