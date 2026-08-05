import Foundation

extension AppStore {
    func refreshProviderResources(_ providers: [ProviderItem]) async {
        guard beginResourceBatchOperation() else { return }
        defer { isResourceBatchOperationInProgress = false }

        let summary = await refreshProviderResources(
            providers,
            remoteAction: "下载更新",
            statusPrefix: "资源更新"
        )
        guard summary.total > 0 else { return }
        resourceUpdateStatus = summary.status(prefix: "资源更新")
        appendLog(summary.failed == 0 ? "info" : "warning", resourceUpdateStatus)
    }

    func rollbackProviderResources(_ providers: [ProviderItem]) async {
        guard beginResourceBatchOperation() else { return }
        defer { isResourceBatchOperationInProgress = false }

        let requests = providers.compactMap { provider -> ProviderResourceRollbackRequest? in
            guard let backupPath = latestProviderRollbackRecord(for: provider)?.backupPath else { return nil }
            return ProviderResourceRollbackRequest(provider: provider, backupPath: backupPath)
        }
        guard requests.isEmpty == false else {
            resourceUpdateStatus = "所选资源没有可用的 Provider 备份。"
            return
        }

        let maxConcurrent = resourceUpdateConcurrency
        resourceUpdateStatus = "正在回滚 \(requests.count) 个资源（并发 \(maxConcurrent)）..."
        let results = await BoundedConcurrentWork.map(requests, maxConcurrent: maxConcurrent) { request in
            Self.rollbackResult(for: request)
        }
        let summary = recordResourceBatchResults(results)
        refreshConfigArtifacts()
        resourceUpdateStatus = summary.status(prefix: "资源回滚")
        appendLog(summary.failed == 0 ? "info" : "warning", resourceUpdateStatus)
    }

    func updateAllExternalResources() async {
        guard beginResourceBatchOperation() else { return }
        defer { isResourceBatchOperationInProgress = false }

        refreshConfigArtifacts()
        let providerItems = providers + nodeProviders.map(\.providerItem)
        let summary = await refreshProviderResources(
            providerItems,
            remoteAction: "批量下载",
            statusPrefix: "正在更新",
            appendsGeoData: true,
            refreshesArtifactsAfterCompletion: false
        )

        if providerItems.isEmpty {
            resourceUpdateStatus = "当前配置没有 Provider，正在更新 Geo 数据..."
        }

        do {
            let geoStatus = try await updateGeoDataInternal()
            resourceUpdateStatus = "Provider 成功 \(summary.succeeded)，失败 \(summary.failed)；\(geoStatus)"
        } catch {
            resourceUpdateStatus = "Provider 成功 \(summary.succeeded)，失败 \(summary.failed)；Geo 更新失败：\(error.localizedDescription)"
            appendLog("error", resourceUpdateStatus)
        }
        refreshConfigArtifacts()
        appendLog(summary.failed == 0 ? "info" : "warning", resourceUpdateStatus)
    }

    private var resourceUpdateConcurrency: Int {
        max(1, min(settings.resourceUpdateMaxConcurrent, 12))
    }

    private func beginResourceBatchOperation() -> Bool {
        guard isResourceBatchOperationInProgress == false else {
            appendLog("warning", "资源批量操作正在进行，已忽略重复请求")
            return false
        }
        isResourceBatchOperationInProgress = true
        return true
    }

    private func refreshProviderResources(
        _ providers: [ProviderItem],
        remoteAction: String,
        statusPrefix: String,
        appendsGeoData: Bool = false,
        refreshesArtifactsAfterCompletion: Bool = true
    ) async -> ProviderResourceBatchSummary {
        let refreshableProviders = providers.filter(\.canRefreshResource)
        guard refreshableProviders.isEmpty == false else {
            if appendsGeoData == false {
                resourceUpdateStatus = "所选资源没有可更新的 Provider。"
            }
            return .empty
        }

        let maxConcurrent = resourceUpdateConcurrency
        let geoSuffix = appendsGeoData ? "及 Geo 数据" : ""
        resourceUpdateStatus = "\(statusPrefix) \(refreshableProviders.count) 个资源（并发 \(maxConcurrent)）\(geoSuffix)..."
        let results = await BoundedConcurrentWork.map(refreshableProviders, maxConcurrent: maxConcurrent) { provider in
            await Self.refreshResult(for: provider, remoteAction: remoteAction)
        }
        let summary = recordResourceBatchResults(results)
        if refreshesArtifactsAfterCompletion {
            refreshConfigArtifacts()
        }
        return summary
    }

    private func recordResourceBatchResults(
        _ results: [ProviderResourceUpdateResult]
    ) -> ProviderResourceBatchSummary {
        var succeeded = 0
        var failed = 0
        var records: [ProviderUpdateRecord] = []
        records.reserveCapacity(results.count)

        for result in results {
            if let errorMessage = result.errorMessage {
                failed += 1
                appendLog("error", "\(result.provider.name) \(result.action)失败：\(errorMessage)")
                records.append(.init(
                    providerName: result.provider.name,
                    providerKind: result.provider.kind,
                    action: result.action,
                    succeeded: false,
                    targetPath: result.targetPath,
                    message: errorMessage,
                    restoredFromPath: result.restoredFromPath
                ))
            } else {
                succeeded += 1
                let message = result.action == "回滚"
                    ? "资源回滚成功"
                    : result.backupPath == nil ? "资源刷新成功" : "资源更新成功；已备份上一版：\(result.backupPath ?? "")"
                records.append(.init(
                    providerName: result.provider.name,
                    providerKind: result.provider.kind,
                    action: result.action,
                    succeeded: true,
                    targetPath: result.targetPath,
                    message: message,
                    backupPath: result.backupPath,
                    restoredFromPath: result.restoredFromPath
                ))
            }
        }
        recordProviderUpdates(records)

        return ProviderResourceBatchSummary(total: results.count, succeeded: succeeded, failed: failed)
    }

    nonisolated private static func refreshResult(
        for provider: ProviderItem,
        remoteAction: String
    ) async -> ProviderResourceUpdateResult {
        let hasRemoteURL = provider.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let action = hasRemoteURL ? remoteAction : "本地刷新"
        do {
            if hasRemoteURL {
                let result = try await ProviderResourceManager().download(provider)
                return ProviderResourceUpdateResult(
                    provider: provider,
                    action: action,
                    targetPath: result.target.path,
                    backupPath: result.backup?.path
                )
            }
            let result = try ProviderResourceManager().refreshLocal(provider)
            return ProviderResourceUpdateResult(provider: provider, action: action, targetPath: result.target.path)
        } catch {
            return ProviderResourceUpdateResult(
                provider: provider,
                action: action,
                targetPath: provider.path ?? "-",
                errorMessage: error.localizedDescription
            )
        }
    }

    nonisolated private static func rollbackResult(
        for request: ProviderResourceRollbackRequest
    ) -> ProviderResourceUpdateResult {
        do {
            let result = try ProviderResourceManager().rollback(
                request.provider,
                from: URL(fileURLWithPath: request.backupPath)
            )
            return ProviderResourceUpdateResult(
                provider: request.provider,
                action: "回滚",
                targetPath: result.target.path,
                backupPath: result.replacedBackup?.path,
                restoredFromPath: result.restoredFrom.path
            )
        } catch {
            return ProviderResourceUpdateResult(
                provider: request.provider,
                action: "回滚",
                targetPath: request.provider.path ?? "-",
                errorMessage: error.localizedDescription,
                restoredFromPath: request.backupPath
            )
        }
    }
}

private struct ProviderResourceUpdateResult: Sendable {
    var provider: ProviderItem
    var action: String
    var targetPath: String
    var backupPath: String? = nil
    var errorMessage: String? = nil
    var restoredFromPath: String? = nil
}

private struct ProviderResourceRollbackRequest: Sendable {
    var provider: ProviderItem
    var backupPath: String
}

private struct ProviderResourceBatchSummary {
    static let empty = Self(total: 0, succeeded: 0, failed: 0)

    var total: Int
    var succeeded: Int
    var failed: Int

    func status(prefix: String) -> String {
        "\(prefix)完成：\(total)/\(total)，成功 \(succeeded)，失败 \(failed)。"
    }
}
