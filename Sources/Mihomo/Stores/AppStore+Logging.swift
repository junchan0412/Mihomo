import Foundation

extension AppStore {
    func appendLog(_ level: String, _ message: String) {
        guard !message.isEmpty else { return }
        for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
            let entry = LogEntry(level: level, message: String(line))
            persistLog(entry)
            if logsPaused {
                bufferedLogs.append(entry)
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
        if logs.count > 1_200 {
            logs.removeFirst(logs.count - 1_200)
        }
    }

    private func persistLog(_ entry: LogEntry) {
        try? AppPaths.ensureBaseDirectories()
        let line = "\(Formatters.shortDate.string(from: entry.date)) [\(entry.level.uppercased())] \(entry.message)\n"
        writeLogLine(line, to: AppPaths.appLogFile, prefix: "mihomo-app")
        if entry.level.lowercased() == "core" {
            writeLogLine(line, to: AppPaths.coreLogFile, prefix: "mihomo-core")
        }
        pruneOldLogsIfNeeded()
    }

    private func writeLogLine(_ line: String, to url: URL, prefix: String) {
        rotateLogIfNeeded(url: url, prefix: prefix)
        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(Data(line.utf8))
    }

    private func rotateLogIfNeeded(url: URL, prefix: String) {
        guard settings.logMaxFileSizeMB > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return }

        let maxBytes = Int64(settings.logMaxFileSizeMB) * 1_024 * 1_024
        guard size.int64Value >= maxBytes else { return }
        let rotated = AppPaths.rotatedLogFile(prefix: prefix)
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }

    private func pruneOldLogsIfNeeded() {
        let now = Date()
        if let lastLogPruneAt, now.timeIntervalSince(lastLogPruneAt) < 300 {
            return
        }
        lastLogPruneAt = now
        guard settings.logRetentionDays > 0,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: AppPaths.logsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return }

        let cutoff = now.addingTimeInterval(-Double(settings.logRetentionDays) * 24 * 60 * 60)
        for url in urls where url.pathExtension == "log" && url.lastPathComponent.hasPrefix("mihomo-") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
