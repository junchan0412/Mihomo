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
}

enum NetworkClient {
    static func data(
        for request: URLRequest,
        kind: NetworkRequestKind = .api,
        maxBytes: Int? = nil
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = kind.requestTimeout
        let session = NetworkSessionFactory.session(for: kind)
        guard let maxBytes else {
            return try await session.data(for: request)
        }
        let (bytes, response) = try await session.bytes(for: request)
        let expected = response.expectedContentLength
        if expected > Int64(maxBytes) {
            throw networkSizeError(maxBytes: maxBytes)
        }
        var data = Data()
        if expected > 0 {
            data.reserveCapacity(min(Int(expected), maxBytes))
        }
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes {
                throw networkSizeError(maxBytes: maxBytes)
            }
        }
        return (data, response)
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
        let session = NetworkSessionFactory.session(for: kind)
        guard let maxBytes else {
            return try await session.download(for: request)
        }
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maxBytes) {
            throw networkSizeError(maxBytes: maxBytes)
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("mihomo-download-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var total = 0
        do {
            for try await byte in bytes {
                total += 1
                if total > maxBytes {
                    throw networkSizeError(maxBytes: maxBytes)
                }
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if buffer.isEmpty == false {
                try handle.write(contentsOf: buffer)
            }
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

    private static func networkSizeError(maxBytes: Int) -> NSError {
        NSError(domain: "Mihomo.Network", code: 413, userInfo: [
            NSLocalizedDescriptionKey: "远程内容超过 \(maxBytes / 1024 / 1024) MiB，已拒绝读取。"
        ])
    }
}
