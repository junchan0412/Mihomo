import Foundation

struct LogPersistencePolicy: Sendable {
    var maxFileSizeBytes: Int64
    var retentionDays: Int
}

actor LogPersistenceWriter {
    private struct PendingLine: Sendable {
        var line: String
        var isCore: Bool
        var policy: LogPersistencePolicy
    }

    private let logsDirectory: URL
    private let appLogFile: URL
    private let coreLogFile: URL
    private let flushDelayNanoseconds: UInt64
    private var pending: [PendingLine] = []
    private var flushTask: Task<Void, Never>?
    private var lastPruneAt: Date?

    init(
        logsDirectory: URL = AppPaths.logsDirectory,
        appLogFile: URL = AppPaths.appLogFile,
        coreLogFile: URL = AppPaths.coreLogFile,
        flushDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.logsDirectory = logsDirectory
        self.appLogFile = appLogFile
        self.coreLogFile = coreLogFile
        self.flushDelayNanoseconds = flushDelayNanoseconds
    }

    func enqueue(line: String, isCore: Bool, policy: LogPersistencePolicy) {
        pending.append(PendingLine(line: line, isCore: isCore, policy: policy))
        guard flushTask == nil else { return }

        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.flushDelayNanoseconds ?? 0)
            guard Task.isCancelled == false else { return }
            await self?.flushScheduledBatch()
        }
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        flushPendingLines()
    }

    private func flushScheduledBatch() {
        flushTask = nil
        flushPendingLines()
    }

    private func flushPendingLines() {
        guard pending.isEmpty == false else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: false)
        guard let policy = batch.last?.policy else { return }

        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let appData = Data(batch.map(\.line).joined().utf8)
        append(appData, to: appLogFile, prefix: "mihomo-app", maxFileSizeBytes: policy.maxFileSizeBytes)

        let coreData = Data(batch.filter(\.isCore).map(\.line).joined().utf8)
        if coreData.isEmpty == false {
            append(coreData, to: coreLogFile, prefix: "mihomo-core", maxFileSizeBytes: policy.maxFileSizeBytes)
        }
        pruneOldLogsIfNeeded(retentionDays: policy.retentionDays)
    }

    private func append(_ data: Data, to url: URL, prefix: String, maxFileSizeBytes: Int64) {
        guard data.isEmpty == false else { return }
        rotateIfNeeded(url: url, prefix: prefix, incomingBytes: Int64(data.count), maxFileSizeBytes: maxFileSizeBytes)

        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func rotateIfNeeded(url: URL, prefix: String, incomingBytes: Int64, maxFileSizeBytes: Int64) {
        guard maxFileSizeBytes > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value + incomingBytes >= maxFileSizeBytes
        else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let rotated = logsDirectory.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).log")
        try? FileManager.default.moveItem(at: url, to: rotated)
    }

    private func pruneOldLogsIfNeeded(retentionDays: Int) {
        let now = Date()
        if let lastPruneAt, now.timeIntervalSince(lastPruneAt) < 300 {
            return
        }
        lastPruneAt = now
        guard retentionDays > 0,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return }

        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        for url in urls where url.pathExtension == "log" && url.lastPathComponent.hasPrefix("mihomo-") {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
