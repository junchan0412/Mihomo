import Foundation

enum NetworkRequestKind: Hashable {
    case api
    case download
    case controller

    var requestTimeout: TimeInterval {
        switch self {
        case .api:
            return 20
        case .download:
            return 30
        case .controller:
            return 8
        }
    }

    var resourceTimeout: TimeInterval {
        switch self {
        case .api:
            return 60
        case .download:
            return 300
        case .controller:
            return 15
        }
    }
}

enum NetworkSessionFactory {
    static func configuration(for kind: NetworkRequestKind) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = kind.requestTimeout
        configuration.timeoutIntervalForResource = kind.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func session(for kind: NetworkRequestKind) -> URLSession {
        switch kind {
        case .api:
            return apiSession
        case .download:
            return downloadSession
        case .controller:
            return controllerSession
        }
    }

    private static let apiSession = URLSession(configuration: configuration(for: .api))
    private static let downloadSession = URLSession(configuration: configuration(for: .download))
    private static let controllerSession = URLSession(configuration: configuration(for: .controller))

    /// Long-lived WebSocket tasks need their own session. `timeoutIntervalForResource` bounds a
    /// task's *total* lifetime, so reusing the controller session would tear every event stream
    /// down after 15 seconds and permanently fall back to polling.
    static let eventStreamSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = NetworkRequestKind.controller.requestTimeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

enum NetworkClient {
    static func data(
        for request: URLRequest,
        kind: NetworkRequestKind = .api,
        maxBytes: Int? = nil
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = kind.requestTimeout
        guard let maxBytes else {
            return try await NetworkSessionFactory.session(for: kind).data(for: request)
        }

        let buffer = DataAccumulator()
        let reader = BoundedResponseReader(maxBytes: maxBytes) { chunk in
            buffer.append(chunk)
        }
        let response = try await reader.load(
            request: request,
            configuration: NetworkSessionFactory.configuration(for: kind)
        )
        return (buffer.data, response)
    }

    static func data(
        from url: URL,
        kind: NetworkRequestKind = .api,
        maxBytes: Int? = nil
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = kind.requestTimeout
        return try await data(for: request, kind: kind, maxBytes: maxBytes)
    }

    static func download(
        for request: URLRequest,
        kind: NetworkRequestKind = .download,
        maxBytes: Int? = nil
    ) async throws -> (URL, URLResponse) {
        var request = request
        request.timeoutInterval = kind.requestTimeout
        guard let maxBytes else {
            return try await NetworkSessionFactory.session(for: kind).download(for: request)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-download-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)

        let reader = BoundedResponseReader(maxBytes: maxBytes) { chunk in
            try handle.write(contentsOf: chunk)
        }
        do {
            let response = try await reader.load(
                request: request,
                configuration: NetworkSessionFactory.configuration(for: kind)
            )
            try handle.close()
            return (destination, response)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func download(
        from url: URL,
        kind: NetworkRequestKind = .download,
        maxBytes: Int? = nil
    ) async throws -> (URL, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = kind.requestTimeout
        return try await download(for: request, kind: kind, maxBytes: maxBytes)
    }

    static func sizeLimitError(maxBytes: Int) -> NSError {
        NSError(domain: "Mihomo.Network", code: 413, userInfo: [
            NSLocalizedDescriptionKey: "远程内容超过 \(maxBytes / 1024 / 1024) MiB，已拒绝读取。"
        ])
    }
}

/// Collects delegate chunks for the in-memory `data(for:maxBytes:)` path. The reader's callbacks
/// arrive on a serial delegate queue, but the lock keeps the handoff to the caller explicit.
final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(chunk)
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
