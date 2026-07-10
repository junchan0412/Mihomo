import Foundation

enum LogBufferPolicy {
    static let visibleEntryLimit = 1_200
    static let bufferedEntryLimit = 1_200

    static func pruneVisible(_ logs: inout [LogEntry]) {
        prune(&logs, limit: visibleEntryLimit)
    }

    static func pruneBuffered(_ logs: inout [LogEntry]) {
        prune(&logs, limit: bufferedEntryLimit)
    }

    private static func prune(_ logs: inout [LogEntry], limit: Int) {
        guard limit > 0, logs.count > limit else { return }
        logs.removeFirst(logs.count - limit)
    }
}

extension AppStore {
    func appendLog(_ level: String, _ message: String) {
        guard !message.isEmpty else { return }
        for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = LogEntry(level: level, message: String(line))
            persistLog(entry)
            if logsPaused {
                bufferedLogs.append(entry)
                LogBufferPolicy.pruneBuffered(&bufferedLogs)
                bufferedLogCount = bufferedLogs.count
            } else {
                pendingLogEntries.append(entry)
                scheduleLogFlush()
            }
        }
    }

    func setLogsPaused(_ paused: Bool) {
        flushPendingLogs()
        logsPaused = paused
        if paused == false, bufferedLogs.isEmpty == false {
            logs.append(contentsOf: bufferedLogs)
            pruneVisibleLogs()
            bufferedLogs.removeAll()
            bufferedLogCount = 0
        }
        appendLog("info", paused ? "日志流已暂停，仍会继续落盘。" : "日志流已继续。")
    }

    func toggleLogPause() {
        setLogsPaused(!logsPaused)
    }

    func clearVisibleLogs() {
        logs.removeAll()
        pendingLogEntries.removeAll()
        bufferedLogs.removeAll()
        bufferedLogCount = 0
    }

    private func scheduleLogFlush() {
        guard logFlushTask == nil else { return }
        logFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.flushPendingLogs()
        }
    }

    private func flushPendingLogs() {
        guard pendingLogEntries.isEmpty == false else {
            logFlushTask = nil
            return
        }
        logs.append(contentsOf: pendingLogEntries)
        pendingLogEntries.removeAll()
        pruneVisibleLogs()
        logFlushTask = nil
    }

    private func pruneVisibleLogs() {
        LogBufferPolicy.pruneVisible(&logs)
    }

    private func persistLog(_ entry: LogEntry) {
        let line = "\(Formatters.shortDate.string(from: entry.date)) [\(entry.level.uppercased())] \(entry.message)\n"
        let policy = LogPersistencePolicy(
            maxFileSizeBytes: Int64(settings.logMaxFileSizeMB) * 1_024 * 1_024,
            retentionDays: settings.logRetentionDays
        )
        let isCore = entry.level.lowercased() == "core"
        Task { [logPersistenceWriter] in
            await logPersistenceWriter.enqueue(line: line, isCore: isCore, policy: policy)
        }
    }
}
