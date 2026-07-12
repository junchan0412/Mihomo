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
    static func data(for request: URLRequest, kind: NetworkRequestKind = .api) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = kind.requestTimeout
        return try await NetworkSessionFactory.session(for: kind).data(for: request)
    }

    static func data(from url: URL, kind: NetworkRequestKind = .api) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = kind.requestTimeout
        return try await data(for: request, kind: kind)
    }

    static func download(for request: URLRequest, kind: NetworkRequestKind = .download) async throws -> (URL, URLResponse) {
        var request = request
        request.timeoutInterval = kind.requestTimeout
        return try await NetworkSessionFactory.session(for: kind).download(for: request)
    }

    static func download(from url: URL, kind: NetworkRequestKind = .download) async throws -> (URL, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = kind.requestTimeout
        return try await download(for: request, kind: kind)
    }
}
