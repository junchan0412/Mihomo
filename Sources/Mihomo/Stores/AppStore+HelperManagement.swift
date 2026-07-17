import Foundation

private struct PendingHelperReregistration: Codable {
    var targetVersion: String
    var requestedAt: Date
}

extension AppStore {
    func refreshHelperStatus() async {
        do {
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperInstallationDescription)"
        } catch {
            helperStatus = "\(helperInstallationDescription)：\(error.localizedDescription)"
        }
    }

    func auditHelper() async {
        var results = helperAuditService.localAuditResults(helperStatus: helperInstallationDescription)
        do {
            let version = try await helperClient.version()
            helperStatus = "\(version.message)，\(helperInstallationDescription)"
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .ok))
            results.append(helperAuditService.runtimeBindingResult(helperVersion: version))
            let privilege = try await helperClient.verifyPrivileges()
            results.append(.init(title: "Helper 授权", detail: privilege.message, state: .ok))
        } catch {
            helperStatus = helperTroubleshootingDetail(error.localizedDescription)
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
        }
        diagnostics = results
        selectedSection = .diagnostics
    }

    func registerHelper() async {
        do {
            if shouldUseLegacyHelper {
                try await installLegacyHelperReplacingSMAppService()
                let result = try await helperClient.version()
                helperStatus = "\(result.message)，传统 Helper 已安装"
                appendLog("info", helperStatus)
                return
            }
            try helperService.register()
            helperStatus = helperInstallationDescription
            appendLog("info", "XPC Helper 注册请求已提交：\(helperStatus)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshHelperStatus()
            if helperService.requiresApproval == false, (try? await helperClient.version()) == nil {
                try await installLegacyHelperReplacingSMAppService()
                let result = try await helperClient.version()
                helperStatus = "\(result.message)，传统 Helper 已安装"
                appendLog("info", helperStatus)
            }
        } catch {
            let serviceError = error.localizedDescription
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                helperStatus = "Helper 等待系统批准。请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo。"
                appendLog("warning", helperStatus)
                return
            }
            do {
                try await installLegacyHelperReplacingSMAppService()
                let result = try await helperClient.version()
                helperStatus = "\(result.message)，传统 Helper 已安装"
                appendLog("warning", "SMAppService 注册失败（\(serviceError)），已切换传统 Helper。")
            } catch {
                helperStatus = "Helper 注册失败：SMAppService：\(serviceError)；传统 Helper：\(error.localizedDescription)"
                appendLog("error", helperStatus)
            }
        }
    }

    func unregisterHelper() async {
        do {
            if helperService.isRegistered {
                try await helperService.unregisterAndWait()
            }
            if legacyHelperInstaller.isInstalled {
                try await legacyHelperInstaller.uninstall()
            }
            helperStatus = helperInstallationDescription
            appendLog("info", "XPC Helper 已取消注册：\(helperStatus)")
        } catch {
            helperStatus = "XPC Helper 卸载失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
        }
    }

    func repairHelperRegistration() async {
        helperStatus = "正在重建 Helper 注册"
        appendLog("info", helperStatus)

        do {
            if shouldUseLegacyHelper {
                try await installLegacyHelperReplacingSMAppService()
                let result = try await helperClient.version()
                helperStatus = "\(result.message)，传统 Helper 已安装"
                appendLog("info", helperStatus)
                await auditHelper()
                return
            }
            do {
                try await helperService.unregisterAndWait()
                appendLog("info", "XPC Helper 旧注册已移除")
            } catch {
                appendLog("warning", "XPC Helper 取消注册跳过：\(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            try helperService.register()
            helperStatus = helperInstallationDescription
            appendLog("info", "XPC Helper 注册已重建：\(helperStatus)")
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                helperStatus = "\(helperStatus)。请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo 后重新运行诊断。"
                appendLog("warning", helperStatus)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await auditHelper()
            if helperService.requiresApproval == false, (try? await helperClient.version()) == nil {
                try await installLegacyHelperReplacingSMAppService()
                let result = try await helperClient.version()
                helperStatus = "\(result.message)，传统 Helper 已安装"
                appendLog("info", helperStatus)
            }
        } catch {
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                helperStatus = "Helper 等待系统批准。请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo。"
                appendLog("warning", helperStatus)
                upsertDiagnostic(.init(title: "XPC Helper", detail: helperStatus, state: .warning))
                selectedSection = .diagnostics
                return
            }
            do {
                try await installLegacyHelperReplacingSMAppService()
                let result = try await helperClient.version()
                helperStatus = "\(result.message)，传统 Helper 已安装"
                appendLog("warning", "SMAppService 不可用，已切换传统 Helper：\(helperStatus)")
                upsertDiagnostic(.init(title: "XPC Helper", detail: helperStatus, state: .warning))
            } catch {
                helperService.openLoginItemsSettings()
                helperStatus = helperTroubleshootingDetail(error.localizedDescription)
                appendLog("error", helperStatus)
                upsertDiagnostic(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
            }
            selectedSection = .diagnostics
        }
    }

    func prepareHelperForSoftwareUpdate(targetVersion: String) async throws -> Bool {
        let usesLegacyHelper = legacyHelperInstaller.isInstalled
        guard helperService.isRegistered || usesLegacyHelper else {
            try? FileManager.default.removeItem(at: AppPaths.pendingHelperReregistrationFile)
            return false
        }

        helperStatus = "正在停用旧版 Helper"
        if helperService.isRegistered {
            try await helperService.unregisterAndWait()
        }
        let marker = PendingHelperReregistration(targetVersion: targetVersion, requestedAt: Date())
        let data = try JSONEncoder().encode(marker)
        try data.write(to: AppPaths.pendingHelperReregistrationFile, options: .atomic)
        helperStatus = "旧版 Helper 已停用，更新后将自动重新注册"
        appendLog("info", helperStatus)
        return true
    }

    func restoreHelperAfterFailedSoftwareUpdate() async {
        guard FileManager.default.fileExists(atPath: AppPaths.pendingHelperReregistrationFile.path) else { return }
        if legacyHelperInstaller.isInstalled {
            try? FileManager.default.removeItem(at: AppPaths.pendingHelperReregistrationFile)
            helperStatus = "更新未完成，传统 Helper 继续使用当前 App 授权"
            appendLog("info", helperStatus)
            return
        }
        do {
            try helperService.register()
            try? FileManager.default.removeItem(at: AppPaths.pendingHelperReregistrationFile)
            helperStatus = helperInstallationDescription
            appendLog("info", "更新未完成，已恢复当前版本 Helper：\(helperStatus)")
        } catch {
            helperStatus = "更新未完成，Helper 恢复失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
        }
    }

    func resumeHelperRegistrationAfterUpdateIfNeeded() async {
        let markerURL = AppPaths.pendingHelperReregistrationFile
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(PendingHelperReregistration.self, from: data)
        else { return }

        do {
            if legacyHelperInstaller.isInstalled || shouldUseLegacyHelper {
                try await installLegacyHelperReplacingSMAppService()
                helperStatus = "传统 Helper 已更新并重新绑定当前 App"
            } else if helperService.isRegistered == false {
                try helperService.register()
                helperStatus = helperInstallationDescription
            }
            try? FileManager.default.removeItem(at: markerURL)
            appendLog("info", "更新至 \(marker.targetVersion) 后已重新注册 Helper：\(helperStatus)")
            if helperService.requiresApproval {
                helperStatus += "。请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo。"
                appendLog("warning", helperStatus)
            }
        } catch {
            helperStatus = "更新后 Helper 重新注册失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
        }
    }

    func installLegacyHelperReplacingSMAppService() async throws {
        if helperService.isRegistered {
            try await helperService.unregisterAndWait()
        }
        try await legacyHelperInstaller.install()
    }
}
