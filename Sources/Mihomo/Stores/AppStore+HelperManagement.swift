import Foundation

extension AppStore {
    func refreshHelperStatus() async {
        do {
            let result = try await helperClient.version()
            helperStatus = "\(result.message)，\(helperService.statusDescription)"
        } catch {
            helperStatus = "\(helperService.statusDescription)：\(error.localizedDescription)"
        }
    }

    func auditHelper() async {
        var results = helperAuditService.localAuditResults(helperStatus: helperService.statusDescription)
        do {
            let version = try await helperClient.version()
            helperStatus = "\(version.message)，\(helperService.statusDescription)"
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
            try helperService.register()
            helperStatus = helperService.statusDescription
            appendLog("info", "XPC Helper 注册请求已提交：\(helperStatus)")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshHelperStatus()
        } catch {
            helperStatus = "XPC Helper 注册失败：\(error.localizedDescription)"
            appendLog("error", helperStatus)
        }
    }

    func unregisterHelper() async {
        do {
            try helperService.unregister()
            helperStatus = helperService.statusDescription
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
            do {
                try helperService.unregister()
                appendLog("info", "XPC Helper 旧注册已移除")
            } catch {
                appendLog("warning", "XPC Helper 取消注册跳过：\(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            try helperService.register()
            helperStatus = helperService.statusDescription
            appendLog("info", "XPC Helper 注册已重建：\(helperStatus)")
            if helperService.requiresApproval {
                helperService.openLoginItemsSettings()
                helperStatus = "\(helperStatus)。请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo 后重新运行诊断。"
                appendLog("warning", helperStatus)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await auditHelper()
        } catch {
            helperService.openLoginItemsSettings()
            helperStatus = helperTroubleshootingDetail(error.localizedDescription)
            appendLog("error", helperStatus)
            upsertDiagnostic(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
            selectedSection = .diagnostics
        }
    }
}
