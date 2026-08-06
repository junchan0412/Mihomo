import Foundation

/// A one-shot download task that exposes URLSession's byte-level progress safely to the update flow.
final class SoftwareUpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (SoftwareUpdateDownloadProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var destination: URL?
    private var startDate: Date?
    private var previousProgressSample: (bytesReceived: Int64, date: Date)?
    private var lastProgressEmissionDate = Date.distantPast
    private var wasCancelled = false

    init(progressHandler: @escaping @Sendable (SoftwareUpdateDownloadProgress) -> Void) {
        self.progressHandler = progressHandler
    }

    func download(for request: URLRequest, to destination: URL) async throws -> URLResponse {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard wasCancelled == false else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.destination = destination
                self.startDate = Date()
                self.previousProgressSample = nil
                self.lastProgressEmissionDate = .distantPast
                let session = URLSession(
                    configuration: NetworkSessionFactory.configuration(for: .download),
                    delegate: self,
                    delegateQueue: nil
                )
                let task = session.downloadTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { [weak self] in
            self?.cancel()
        })
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        lock.lock()
        let previous = previousProgressSample
        let startDate = self.startDate ?? now
        previousProgressSample = (totalBytesWritten, now)
        let timeSinceLastEmission = now.timeIntervalSince(lastProgressEmissionDate)
        let isComplete = totalBytes.map { totalBytesWritten >= $0 } ?? false
        let shouldEmit = timeSinceLastEmission >= 0.1 || isComplete
        if shouldEmit {
            lastProgressEmissionDate = now
        }
        lock.unlock()
        guard shouldEmit else { return }

        let elapsed = max(now.timeIntervalSince(previous?.date ?? startDate), 0.001)
        let bytesSincePrevious = totalBytesWritten - (previous?.bytesReceived ?? 0)
        progressHandler(
            SoftwareUpdateDownloadProgress(
                bytesReceived: totalBytesWritten,
                totalBytes: totalBytes,
                bytesPerSecond: max(Int64(Double(bytesSincePrevious) / elapsed), 0)
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let destination = lockedDestination() else {
                throw CocoaError(.fileNoSuchFile)
            }
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            finish(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(throwing: error)
            return
        }
        guard let response = task.response else {
            finish(throwing: CocoaError(.fileReadUnknown))
            return
        }
        finish(returning: response)
    }

    private func lockedDestination() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return destination
    }

    private func finish(returning response: URLResponse) {
        finish(with: .success(response))
    }

    private func finish(throwing error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<URLResponse, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
