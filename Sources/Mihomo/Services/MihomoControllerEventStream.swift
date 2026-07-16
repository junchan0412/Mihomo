import Foundation

enum ControllerStreamEvent: Equatable {
    case traffic(uploadRate: Int64, downloadRate: Int64)
    case log(level: String, message: String)
    case connections(items: [ConnectionItem], uploadTotal: Int64, downloadTotal: Int64)
}

struct ControllerEventStreamFailureDecision: Equatable {
    var status: String
    var shouldLogWarning: Bool
    var backoffSeconds: UInt64
}

struct ControllerEventStreamRecoveryState: Equatable {
    private(set) var failureCount = 0

    mutating func recordEvent() {
        failureCount = 0
    }

    mutating func recordFailure(hasReceivedEvent: Bool) -> ControllerEventStreamFailureDecision {
        failureCount += 1
        return ControllerEventStreamFailureDecision(
            status: hasReceivedEvent ? "降级" : "轮询",
            shouldLogWarning: failureCount == 1,
            backoffSeconds: min(UInt64(max(failureCount, 1) * 2), 12)
        )
    }
}

struct MihomoControllerEventStream {
    var host: String
    var port: Int
    var secret: String = ""
    var session: URLSession = NetworkSessionFactory.session(for: .controller)

    func trafficEvents() -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        eventStream(path: "/traffic", transform: Self.parseTrafficEvent)
    }

    func logEvents(level: String = "info") -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        eventStream(path: "/logs", queryItems: [URLQueryItem(name: "level", value: level)], transform: Self.parseLogEvent)
    }

    func connectionEvents() -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        eventStream(
            path: "/connections",
            queryItems: [URLQueryItem(name: "interval", value: "500")],
            transform: Self.parseConnectionEvent
        )
    }

    static func parseTrafficEvent(data: Data) -> ControllerStreamEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let upload = number(object["up"] ?? object["upload"] ?? object["uploadRate"])
        let download = number(object["down"] ?? object["download"] ?? object["downloadRate"])
        return .traffic(uploadRate: upload, downloadRate: download)
    }

    static func parseLogEvent(data: Data) -> ControllerStreamEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let level = (object["type"] as? String)
            ?? (object["level"] as? String)
            ?? "info"
        let payload = (object["payload"] as? String)
            ?? (object["message"] as? String)
            ?? ""
        guard payload.isEmpty == false else { return nil }
        return .log(level: "core", message: "[\(level)] \(payload)")
    }

    static func parseConnectionEvent(data: Data) -> ControllerStreamEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let (items, uploadTotal, downloadTotal) = MihomoControllerClient.parseConnections(from: object)
        return .connections(items: items, uploadTotal: uploadTotal, downloadTotal: downloadTotal)
    }

    private func eventStream(
        path: String,
        queryItems: [URLQueryItem] = [],
        transform: @escaping (Data) -> ControllerStreamEvent?
    ) -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let webSocketRequest: URLRequest
            do {
                webSocketRequest = try request(path: path, queryItems: queryItems)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let task = session.webSocketTask(with: webSocketRequest)
            task.resume()

            func receiveNext() {
                task.receive { result in
                    switch result {
                    case .success(let message):
                        if let data = data(from: message),
                           let event = transform(data) {
                            continuation.yield(event)
                        }
                        receiveNext()
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                }
            }

            receiveNext()
            let heartbeatTask = Task {
                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard Task.isCancelled == false else { return }
                    task.sendPing { error in
                        guard let error else { return }
                        task.cancel(with: .goingAway, reason: nil)
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in
                heartbeatTask.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    func request(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        var request = URLRequest(url: try webSocketURL(path: path, queryItems: queryItems))
        request.timeoutInterval = NetworkRequestKind.controller.requestTimeout
        applyAuthorization(to: &request)
        return request
    }

    private func webSocketURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHost.isEmpty == false, (1...65_535).contains(port) else {
            throw controllerError("核心实时状态地址无效：\(host):\(port)")
        }
        var components = URLComponents()
        components.scheme = "ws"
        components.host = normalizedHost
        components.port = port
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw controllerError("核心实时状态地址无效：\(host):\(port)")
        }
        return url
    }

    private func applyAuthorization(to request: inout URLRequest) {
        let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func data(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .data(let data):
            return data
        case .string(let string):
            return Data(string.utf8)
        @unknown default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func controllerError(_ message: String) -> NSError {
        NSError(domain: "MihomoControllerWebSocket", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
