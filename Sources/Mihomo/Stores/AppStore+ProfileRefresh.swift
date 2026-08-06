import Foundation

extension AppStore {
    func refreshProfile(_ profile: ProfileItem) async {
        guard profileRefreshQueueRunning == false,
              isResourceBatchOperationInProgress == false,
              profileRefreshIDsInFlight.insert(profile.id).inserted
        else {
            appendLog("warning", "配置刷新已在运行，已忽略重复请求：\(profile.name)")
            return
        }
        defer { profileRefreshIDsInFlight.remove(profile.id) }
        do {
            let preview = try await profileStore.prepareRemoteProfileRefresh(profile, settings: settings)
            if preview.requiresProviderConfirmation {
                pendingProfileRefreshPreviews.append(preview)
                appendLog("warning", "配置 \(profile.name) 刷新将保留 \(preview.preservedProviderNames.count) 个 Provider，等待确认")
            } else {
                try applyRemoteProfileRefreshPreview(preview)
            }
        } catch {
            appendLog("error", "配置刷新失败：\(error.localizedDescription)")
        }
    }

    func applyPendingProfileRefreshPreview() -> Bool {
        guard let preview = pendingProfileRefreshPreview else { return false }
        do {
            try applyRemoteProfileRefreshPreview(preview)
            pendingProfileRefreshPreviews.removeFirst()
            return true
        } catch {
            appendLog("error", "应用配置刷新失败：\(error.localizedDescription)")
            return false
        }
    }

    func discardPendingProfileRefreshPreview() {
        guard let preview = pendingProfileRefreshPreview else { return }
        pendingProfileRefreshPreviews.removeFirst()
        appendLog("info", "已取消配置 \(preview.originalProfile.name) 的 Provider 合并刷新")
    }

    func refreshAllRemoteProfiles() async {
        guard profileRefreshQueueRunning == false,
              isResourceBatchOperationInProgress == false else {
            appendLog("warning", "订阅刷新队列已在运行")
            return
        }

        let remoteProfiles = profiles.filter(\.isRemote)
        guard remoteProfiles.isEmpty == false else {
            profileAutoRefreshStatus = "没有远程订阅"
            return
        }

        profileRefreshQueueRunning = true
        profileRefreshCancellationRequested = false
        profileRefreshCancellationToken = WorkCancellationToken()
        defer {
            profileRefreshQueueRunning = false
            profileRefreshCancellationToken = nil
        }

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
        var cancelled = 0
        let cancellationToken = profileRefreshCancellationToken

        while pendingProfiles.isEmpty == false || runningTasks.isEmpty == false {
            while runningTasks.count < maxConcurrent,
                  pendingProfiles.isEmpty == false,
                  cancellationToken?.isCancelled != true {
                let profile = pendingProfiles.removeFirst()
                markRefreshJob(profileID: profile.id, state: .running, message: "正在刷新", startedAt: Date(), finishedAt: nil)
                runningTasks.append(Task {
                    guard cancellationToken?.isCancelled != true else {
                        return ProfileRefreshResult(profileID: profile.id, preview: nil, errorMessage: "已取消")
                    }
                    let store = ProfileStore()
                    do {
                        let preview = try await store.prepareRemoteProfileRefresh(profile, settings: refreshSettings)
                        return ProfileRefreshResult(profileID: profile.id, preview: preview, errorMessage: nil)
                    } catch {
                        return ProfileRefreshResult(profileID: profile.id, preview: nil, errorMessage: error.localizedDescription)
                    }
                })
            }

            guard runningTasks.isEmpty == false else { break }
            let result = await runningTasks.removeFirst().value
            completed += 1

            if result.errorMessage == "已取消" {
                cancelled += 1
                markRefreshJob(profileID: result.profileID, state: .cancelled, message: "已取消", finishedAt: Date())
                continue
            }

            if let preview = result.preview {
                if preview.requiresProviderConfirmation {
                    pendingProfileRefreshPreviews.append(preview)
                    succeeded += 1
                    markRefreshJob(profileID: result.profileID, state: .succeeded, message: "等待确认 Provider 合并", finishedAt: Date())
                } else {
                    do {
                        try applyRemoteProfileRefreshPreview(preview)
                        succeeded += 1
                        markRefreshJob(profileID: result.profileID, state: .succeeded, message: "刷新成功", finishedAt: Date())
                    } catch {
                        failed += 1
                        profileRefreshFailureCount = failed
                        markRefreshJob(profileID: result.profileID, state: .failed, message: error.localizedDescription, finishedAt: Date())
                        appendLog("error", "订阅刷新应用失败：\(error.localizedDescription)")
                    }
                }
            } else {
                failed += 1
                profileRefreshFailureCount = failed
                let profileName = profileRefreshQueue.first { $0.profileID == result.profileID }?.profileName ?? "订阅"
                let message = result.errorMessage ?? "未知错误"
                markRefreshJob(profileID: result.profileID, state: .failed, message: message, finishedAt: Date())
                if settings.notifyProfileRefreshFailures {
                    notificationManager.notify(title: "订阅刷新失败", body: "\(profileName)：\(message)")
                }
                appendLog("error", "订阅刷新失败 \(profileName)：\(message)")
            }
            profileAutoRefreshStatus = "队列运行中：\(completed)/\(remoteProfiles.count)，成功 \(succeeded)，失败 \(failed)，取消 \(cancelled)"
        }

        if cancellationToken?.isCancelled == true {
            for profile in pendingProfiles {
                cancelled += 1
                markRefreshJob(profileID: profile.id, state: .cancelled, message: "已取消", finishedAt: Date())
            }
        }
        profileRefreshCancellationRequested = cancellationToken?.isCancelled == true
        profileAutoRefreshStatus = "上次刷新：\(Formatters.shortDate.string(from: Date()))，成功 \(succeeded)/\(remoteProfiles.count)，失败 \(failed)，取消 \(cancelled)"
    }

    func cancelAllRemoteProfilesRefresh() {
        guard profileRefreshQueueRunning else { return }
        profileRefreshCancellationRequested = true
        profileRefreshCancellationToken?.cancel()
        profileAutoRefreshStatus = "正在取消订阅刷新，等待已开始的请求结束…"
        appendLog("warning", profileAutoRefreshStatus)
    }

    private func applyRemoteProfileRefreshPreview(_ preview: RemoteProfileRefreshPreview) throws {
        captureProfileRevision(preview.originalProfile, content: preview.originalContent, actionName: "刷新订阅")
        let updated = try profileStore.applyRemoteProfileRefresh(preview, settings: settings)
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
            try profileStore.saveProfiles(profiles)
        }
        try importNodeProviders(from: [updated])
        if settings.activeProfileID == updated.id {
            try synchronizeAppSettings(from: updated)
        }
        refreshConfigArtifacts()
        appendLog("info", "已刷新配置 \(updated.name)")
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
    var preview: RemoteProfileRefreshPreview?
    var errorMessage: String?
}
