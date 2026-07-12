import AppKit
import Foundation

extension AppStore {
    func runDiagnostics() async {
        var results: [DiagnosticResult] = []
        let mihomoPath = effectiveMihomoPath

        if FileManager.default.isExecutableFile(atPath: mihomoPath) {
            results.append(.init(title: "mihomo 可执行文件", detail: mihomoPath, state: .ok))
            if let version = try? Shell.run(mihomoPath, ["-v"]) {
                let detail = [version.stdout, version.stderr]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(.init(title: "mihomo 版本", detail: detail.isEmpty ? "可执行但未返回版本" : detail, state: .ok))
            }
        } else {
            results.append(.init(title: "mihomo 可执行文件", detail: "请在设置中选择可执行文件。", state: .failed))
        }

        if let activeProfile {
            let file = profileStore.profileFile(activeProfile, settings: settings)
            let exists = FileManager.default.fileExists(atPath: file.path)
            results.append(.init(title: "当前配置", detail: exists ? activeProfile.name : "配置文件丢失", state: exists ? .ok : .failed))
            do {
                let candidate = try profileStore.generateRuntimeConfigCandidate(
                    profile: activeProfile,
                    settings: settings,
                    fragments: configFragments,
                    disabledRules: disabledRules
                )
                try syncGeoDataToRuntimeDirectory()
                let result = try await helperClient.validateConfig(mihomoPath: mihomoPath, configPath: candidate, workDirectory: AppPaths.runtimeDirectory)
                results.append(.init(title: "运行配置 dry-run", detail: "\(result.message)：\(candidate.path)", state: .ok))
            } catch {
                results.append(.init(title: "运行配置 dry-run", detail: "Helper 校验失败：\(error.localizedDescription)", state: .failed))
            }
        } else {
            results.append(.init(title: "当前配置", detail: "没有启用的配置。", state: .failed))
        }

        let services = systemProxy.networkServices()
        results.append(.init(
            title: "网络服务",
            detail: services.isEmpty ? "未找到网络服务。" : services.joined(separator: "、"),
            state: services.isEmpty ? .warning : .ok
        ))

        refreshNetworkTakeoverStates(force: true)
        results.append(contentsOf: networkTakeoverStates.map { state in
            DiagnosticResult(
                title: "网络接管：\(state.kind.title)",
                detail: "用户期望：\(state.desiredState)\n系统实际：\(state.actualState)\n最近 Helper 操作：\(state.lastOperation)\n恢复动作：\(state.recoveryAction)",
                state: diagnosticState(for: state.health)
            )
        })

        if let snapshot = systemProxy.loadSnapshot() {
            results.append(.init(
                title: "系统代理快照",
                detail: "已保存 \(snapshot.services.count) 个网络服务在开启系统代理前的代理状态。若系统代理异常、端口残留或被错误关闭，可恢复到保存前的状态；TUN/DNS 回滚不再使用此代理快照。",
                state: .warning
            ))
        } else {
            results.append(.init(title: "系统代理快照", detail: "当前没有待恢复的系统代理快照。", state: .ok))
        }

        results.append(.init(
            title: "登录项",
            detail: "\(loginItem.statusDescription)。\(settings.launchAtLogin ? "设置要求登录后自动打开 Mihomo。" : "设置未要求登录后自动打开。")",
            state: settings.launchAtLogin && loginItem.isEnabled == false ? .warning : .ok
        ))

        if settings.tunEnabled {
            if let snapshot = tunRecovery.loadSnapshot() {
                results.append(.init(
                    title: "TUN 回滚快照",
                    detail: "已保存 \(snapshot.ipv4Routes.count) 条 IPv4 路由、\(snapshot.ipv6Routes.count) 条 IPv6 路由和 \(snapshot.proxySnapshot.services.count) 个网络服务的 DNS 状态。回滚 TUN 不会改动系统代理开关。",
                    state: .ok
                ))
            } else {
                results.append(.init(
                    title: "TUN 回滚快照",
                    detail: "尚未捕获快照。启动 TUN 核心前会自动捕获 DNS 与路由状态。",
                    state: .warning
                ))
            }
            results.append(.init(
                title: "TUN 模式",
                detail: "已写入 mihomo runtime overlay。可通过诊断页验证管理员授权，并在停止/退出或手动操作时回滚 DNS/路由；不会再恢复系统代理快照。",
                state: .ok
            ))
        } else {
            results.append(.init(title: "TUN 模式", detail: "未启用。", state: .ok))
        }

        do {
            let client = controllerClient()
            let version = try await client.version()
            let mode = try await client.configMode()
            results.append(.init(title: "Controller", detail: "已连接，版本 \(version)，模式 \(mode)", state: .ok))
        } catch {
            results.append(.init(title: "Controller", detail: error.localizedDescription, state: isCoreRunning ? .failed : .warning))
        }

        results.append(.init(
            title: "日志文件",
            detail: "App：\(AppPaths.appLogFile.path)\nCore：\(AppPaths.coreLogFile.path)\n保留 \(settings.logRetentionDays) 天，单文件 \(settings.logMaxFileSizeMB) MB。",
            state: .ok
        ))

        results.append(.init(
            title: "订阅自动刷新",
            detail: settings.autoRefreshProfiles ? "\(profileAutoRefreshStatus)，并发 \(settings.profileRefreshMaxConcurrent)，失败通知 \(profileRefreshFailureCount) 条。" : "未启用。",
            state: profileRefreshFailureCount > 0 ? .warning : (settings.autoRefreshProfiles ? .ok : .warning)
        ))

        results.append(.init(
            title: "核心来源",
            detail: "当前来源：\(settings.coreSource.title)\n当前有效路径：\(mihomoPath)\n托管路径：\(AppPaths.managedCoreFile.path)\n内置路径：\(ManagedCoreManager.bundledCorePath ?? "未随包提供")\n本地路径：\(settings.mihomoPath.isEmpty ? "未设置" : settings.mihomoPath)",
            state: FileManager.default.isExecutableFile(atPath: mihomoPath) ? .ok : .failed
        ))

        results.append(contentsOf: helperAuditService.localAuditResults(helperStatus: helperService.statusDescription))
        do {
            let helper = try await helperClient.version()
            helperStatus = "\(helper.message)，\(helperService.statusDescription)"
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .ok))
            results.append(helperAuditService.runtimeBindingResult(helperVersion: helper))
            let privilege = try await helperClient.verifyPrivileges()
            results.append(.init(title: "Helper 授权", detail: privilege.message, state: .ok))
        } catch {
            helperStatus = helperTroubleshootingDetail(error.localizedDescription)
            results.append(.init(title: "XPC Helper", detail: helperStatus, state: .failed))
        }

        results.append(.init(
            title: "远程 HTTP API",
            detail: settings.remoteAPIEnabled ? "已显式启用，绑定 \(settings.remoteAPIBindAddress):\(settings.controllerPort)，密钥\(settings.controllerSecret.isEmpty ? "未设置" : "已设置")。" : "默认关闭远程访问，仅绑定 127.0.0.1。",
            state: settings.remoteAPIEnabled && settings.controllerSecret.isEmpty ? .warning : .ok
        ))

        results.append(.init(
            title: "外部 UI",
            detail: externalUIStatus,
            state: settings.externalUIEnabled && externalUIStatus == "未安装" ? .warning : .ok
        ))

        let geoFiles = ["geoip.dat", "geosite.dat"].filter {
            FileManager.default.fileExists(atPath: AppPaths.geoDirectory.appendingPathComponent($0).path)
        }
        results.append(.init(
            title: "Geo 数据",
            detail: geoFiles.isEmpty ? "尚未下载 Geo 数据。" : "已存在：\(geoFiles.joined(separator: "、"))",
            state: geoFiles.isEmpty ? .warning : .ok
        ))

        results.append(.init(
            title: "覆写片段与禁用规则",
            detail: "\(configFragments.count) 个片段，\(disabledRules.count) 条禁用规则。JS 覆写\(settings.jsOverrideEnabled ? "已启用" : "未启用")，YAML 覆写\(settings.yamlOverrideEnabled ? "已启用" : "未启用")。",
            state: .ok
        ))

        diagnostics = results
        selectedSection = .diagnostics
    }

    func exportDiagnosticBundle() {
        do {
            let archive = try makeDiagnosticBundle()
            diagnosticExportStatus = "诊断包已导出：\(archive.path)"
            NSWorkspace.shared.activateFileViewerSelecting([archive])
            appendLog("info", diagnosticExportStatus)
        } catch {
            diagnosticExportStatus = "诊断包导出失败：\(error.localizedDescription)"
            appendLog("error", diagnosticExportStatus)
        }
    }

    func helperTroubleshootingDetail(_ errorMessage: String) -> String {
        let status = helperService.statusDescription
        let guidance: String
        if helperService.requiresApproval {
            guidance = "请在系统设置 > 通用 > 登录项与扩展中允许 Mihomo 的后台项目，然后重新运行诊断。"
        } else {
            guidance = "请点击“修复 Helper”重建注册；若系统弹出授权或后台项目提示，请批准后重新运行诊断。"
        }
        return "\(status)：\(errorMessage)\n\(guidance)"
    }

    func upsertDiagnostic(_ result: DiagnosticResult) {
        if let index = diagnostics.firstIndex(where: { $0.title == result.title }) {
            diagnostics[index] = result
        } else {
            diagnostics.append(result)
        }
    }

    private func diagnosticState(for health: NetworkTakeoverHealth) -> DiagnosticState {
        switch health {
        case .ok, .inactive:
            return .ok
        case .warning:
            return .warning
        case .failed:
            return .failed
        }
    }

    private func makeDiagnosticBundle() throws -> URL {
        try AppPaths.ensureBaseDirectories()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let root = AppPaths.backupsDirectory.appendingPathComponent("Diagnostics-\(stamp)", isDirectory: true)
        let archive = AppPaths.backupsDirectory.appendingPathComponent("Mihomo-Diagnostics-\(stamp).zip")
        let manager = FileManager.default
        if manager.fileExists(atPath: root.path) {
            try manager.removeItem(at: root)
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)

        let redactor = DiagnosticRedactor(settings: settings)
        let summary = redactor.redact(diagnosticSummaryText())
        try summary.write(to: root.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        try redactor.manifest.write(to: root.appendingPathComponent("redaction-manifest.txt"), atomically: true, encoding: .utf8)

        if manager.fileExists(atPath: AppPaths.runtimeConfigFile.path) {
            let content = try String(contentsOf: AppPaths.runtimeConfigFile, encoding: .utf8)
            try redactor.redact(content).write(to: root.appendingPathComponent("runtime-config.yaml"), atomically: true, encoding: .utf8)
        } else if configPreview.isEmpty == false {
            try redactor.redact(configPreview).write(to: root.appendingPathComponent("runtime-config-preview.yaml"), atomically: true, encoding: .utf8)
        }

        let recentLogs = logs.suffix(300)
            .map { "[\(Formatters.shortDate.string(from: $0.date))] \($0.level.uppercased()) \($0.message)" }
            .joined(separator: "\n")
        try redactor.redact(recentLogs).write(to: root.appendingPathComponent("app-log-tail.txt"), atomically: true, encoding: .utf8)

        if manager.fileExists(atPath: AppPaths.coreLogFile.path) {
            let content = String(decoding: try Data(contentsOf: AppPaths.coreLogFile), as: UTF8.self)
            try? redactor.redact(content).write(to: root.appendingPathComponent("core.log"), atomically: true, encoding: .utf8)
        }

        if manager.fileExists(atPath: archive.path) {
            try manager.removeItem(at: archive)
        }
        let result = try Shell.run("/usr/bin/zip", ["-r", "-X", archive.path, root.lastPathComponent], workDirectory: root.deletingLastPathComponent())
        guard result.status == 0 else {
            throw NSError(domain: "DiagnosticExport", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
        try? manager.removeItem(at: root)
        return archive
    }

    private func diagnosticSummaryText() -> String {
        let redactedSettings = settings.redactedSecretsForDisk
        let settingsSummary = """
        coreSource: \(redactedSettings.coreSource.rawValue)
        mixedPort: \(redactedSettings.mixedPort)
        socksPort: \(redactedSettings.socksPort)
        tunEnabled: \(redactedSettings.tunEnabled)
        systemProxyEnabled: \(systemProxyEnabled)
        autoSetSystemDNS: \(redactedSettings.autoSetSystemDNS)
        dnsEnhancedMode: \(redactedSettings.dnsEnhancedMode)
        profileStoragePath: \(profileStorageDirectory.path)
        """
        let networkSummary = networkTakeoverStates.map {
            "- \($0.kind.title): desired=\($0.desiredState); actual=\($0.actualState); health=\($0.health.rawValue); recovery=\($0.recoveryAction)"
        }.joined(separator: "\n")
        let diagnosticSummary = diagnostics.map {
            "- \($0.state.rawValue.uppercased()) \($0.title): \($0.detail)"
        }.joined(separator: "\n")
        let providerSummary = providerUpdateHistory.prefix(30).map {
            let backup = $0.backupPath.map { " backup=\($0)" } ?? ""
            let restored = $0.restoredFromPath.map { " restoredFrom=\($0)" } ?? ""
            return "- \(Formatters.shortDate.string(from: $0.date)) \($0.providerKind) \($0.providerName) \($0.action) \($0.succeeded ? "OK" : "FAIL") path=\($0.targetPath)\(backup)\(restored) message=\($0.message)"
        }.joined(separator: "\n")

        return """
        Mihomo Diagnostic Bundle
        Generated: \(Formatters.shortDate.string(from: Date()))
        App: \(currentAppVersion) (\(currentAppBuild))
        Core: \(coreVersion)
        Core status: \(coreStatus)
        Advisory: \(networkModeAdvisory ?? "None")

        Settings
        \(settingsSummary)

        Network Takeover
        \(networkSummary.isEmpty ? "No network takeover states." : networkSummary)

        Diagnostics
        \(diagnosticSummary.isEmpty ? "No diagnostics have been run." : diagnosticSummary)

        Provider Update History
        \(providerSummary.isEmpty ? "No provider update history." : providerSummary)
        """
    }
}
