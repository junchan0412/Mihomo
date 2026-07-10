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

    func trafficEvents() -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        eventStream(path: "/traffic", transform: Self.parseTrafficEvent)
    }

    func logEvents(level: String = "info") -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        eventStream(path: "/logs", queryItems: [URLQueryItem(name: "level", value: level)], transform: Self.parseLogEvent)
    }

    func connectionEvents() -> AsyncThrowingStream<ControllerStreamEvent, Error> {
        eventStream(path: "/connections", transform: Self.parseConnectionEvent)
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
            var request = URLRequest(url: webSocketURL(path: path, queryItems: queryItems))
            applyAuthorization(to: &request)
            let task = URLSession.shared.webSocketTask(with: request)
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
            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func webSocketURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
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
}
