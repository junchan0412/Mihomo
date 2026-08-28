import Foundation

/// Streams a response in `Data` chunks and aborts as soon as it exceeds a byte budget.
///
/// `URLSession.bytes(for:)` yields one `UInt8` at a time, so enforcing a limit that way costs one
/// async iteration per byte — over a hundred million of them for a 100 MiB provider download.
/// The delegate callbacks hand us whole chunks instead.
final class BoundedResponseReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let sink: (Data) throws -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionTask?
    private var response: URLResponse?
    private var receivedBytes = 0
    private var isFinished = false
    private var wasCancelled = false

    init(maxBytes: Int, sink: @escaping (Data) throws -> Void) {
        self.maxBytes = maxBytes
        self.sink = sink
    }

    func load(request: URLRequest, configuration: URLSessionConfiguration) async throws -> URLResponse {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                // `onCancel` can fire before we get here; resuming from there would find no
                // continuation and the caller would hang forever.
                guard wasCancelled == false else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { [weak self] in
            self?.cancel()
        })
    }

    private func cancel() {
        lock.lock()
        wasCancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(with: .failure(CancellationError()))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response
        lock.unlock()

        if response.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel)
            finish(with: .failure(NetworkClient.sizeLimitError(maxBytes: maxBytes)))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        // Never touch the sink once we have handed a result back: the caller may already have
        // closed the file handle it writes into. `sink` therefore runs while the lock is held, so a
        // concurrent `cancel()` cannot complete `finish` — and let the caller close that handle —
        // part-way through a write. Delegate callbacks are serialised on the session queue, so the
        // only contention here is that cancellation.
        guard isFinished == false else {
            lock.unlock()
            return
        }
        receivedBytes += data.count
        if receivedBytes > maxBytes {
            lock.unlock()
            dataTask.cancel()
            finish(with: .failure(NetworkClient.sizeLimitError(maxBytes: maxBytes)))
            return
        }
        let outcome = Result { try sink(data) }
        lock.unlock()

        if case .failure(let error) = outcome {
            dataTask.cancel()
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }
        lock.lock()
        let response = self.response ?? task.response
        lock.unlock()
        guard let response else {
            finish(with: .failure(URLError(.badServerResponse)))
            return
        }
        finish(with: .success(response))
    }

    private func finish(with result: Result<URLResponse, Error>) {
        lock.lock()
        guard let continuation else {
            isFinished = true
            lock.unlock()
            return
        }
        self.continuation = nil
        isFinished = true
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
