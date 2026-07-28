import Foundation

struct MihomoControllerClient {
    var host: String
    var port: Int
    var secret: String = ""

    func version() async throws -> String {
        let json = try await getJSON("/version")
        return (json["version"] as? String) ?? "unknown"
    }

    func configMode() async throws -> String {
        let json = try await getJSON("/configs")
        return (json["mode"] as? String) ?? "rule"
    }

    func setMode(_ mode: String) async throws {
        try await sendJSON("/configs", method: "PATCH", body: ["mode": mode])
    }

    func proxyGroups() async throws -> [ProxyGroup] {
        let json = try await getJSON("/proxies")
        return Self.parseProxyGroups(from: json)
    }

    func selectProxy(group: String, proxy: String) async throws {
        try await sendJSON("/proxies/\(group.urlPathEscaped)", method: "PUT", body: ["name": proxy])
    }

    func proxyDelay(proxy: String, url: String = "https://cp.cloudflare.com/generate_204", timeout: Int = 8000) async throws -> Int {
        let path = "/proxies/\(proxy.urlPathEscaped)/delay"
        let query = "?url=\(url.urlQueryEscaped)&timeout=\(timeout)"
        let json = try await getJSON(path + query)
        if let delay = json["delay"] {
            return Int(Self.number(delay))
        }
        if let message = json["message"] as? String, message.isEmpty == false {
            throw controllerError(message)
        }
        throw controllerError("mihomo 未返回延迟结果。")
    }

    func closeConnections() async throws {
        try await sendJSON("/connections", method: "DELETE", body: nil)
    }

    func closeConnection(id: String) async throws {
        try await sendJSON("/connections/\(id.urlPathEscaped)", method: "DELETE", body: nil)
    }

    func connections() async throws -> ([ConnectionItem], Int64, Int64) {
        let json = try await getJSON("/connections")
        return Self.parseConnections(from: json)
    }

    func providers() async throws -> [ProviderItem] {
        async let proxyProviders = providerItems(path: "/providers/proxies", kind: "Proxy")
        async let ruleProviders = providerItems(path: "/providers/rules", kind: "Rule")
        let proxyItems = try await proxyProviders
        let ruleItems = try await ruleProviders
        return proxyItems + ruleItems
    }

    func updateProvider(_ provider: ProviderItem) async throws {
        let segment = provider.kind == "Proxy" ? "proxies" : "rules"
        try await sendJSON("/providers/\(segment)/\(provider.name.urlPathEscaped)", method: "PUT", body: nil)
    }

    private func providerItems(path: String, kind: String) async throws -> [ProviderItem] {
        let json = try await getJSON(path)
        return Self.parseProviderItems(from: json, kind: kind)
    }

    private func getJSON(_ path: String) async throws -> [String: Any] {
        let url = try endpointURL(path)
        var request = URLRequest(url: url)
        applyAuthorization(to: &request)
        let (data, response) = try await NetworkClient.data(for: request, kind: .controller)
        try validate(response: response, data: data)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func sendJSON(_ path: String, method: String, body: [String: Any]?) async throws {
        let url = try endpointURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuthorization(to: &request)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await NetworkClient.data(for: request, kind: .controller)
        try validate(response: response, data: data)
    }

    private func endpointURL(_ path: String) throws -> URL {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHost.isEmpty == false, (1...65_535).contains(port) else {
            throw controllerError("核心控制地址无效：\(host):\(port)")
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = normalizedHost
        components.port = port

        let rawPath = path.hasPrefix("/") ? path : "/\(path)"
        if let queryStart = rawPath.firstIndex(of: "?") {
            components.path = String(rawPath[..<queryStart])
            components.percentEncodedQuery = String(rawPath[rawPath.index(after: queryStart)...])
        } else {
            components.path = rawPath
        }

        guard let url = components.url else {
            throw controllerError("核心控制地址无效：\(host):\(port)")
        }
        return url
    }

    private func applyAuthorization(to request: inout URLRequest) {
        let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw controllerError("运行中的核心返回了无效的网络响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let fallback = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw controllerError(parsedErrorMessage(data: data, fallback: fallback), code: http.statusCode)
        }
    }

    private func parsedErrorMessage(data: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }
        if let message = object["message"] as? String, message.isEmpty == false {
            return message
        }
        if let error = object["error"] as? String, error.isEmpty == false {
            return error
        }
        return fallback
    }

    private func controllerError(_ message: String, code: Int = 1) -> NSError {
        NSError(domain: "MihomoController", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

}

private extension String {
    var urlPathEscaped: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    var urlQueryEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
