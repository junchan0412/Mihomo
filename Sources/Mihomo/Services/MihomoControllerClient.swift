import Foundation

struct MihomoControllerClient {
    var host: String
    var port: Int
    var secret: String = ""

    private var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

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
        guard let proxies = json["proxies"] as? [String: [String: Any]] else { return [] }

        return proxies.compactMap { name, detail in
            guard let allNames = detail["all"] as? [String], !allNames.isEmpty else { return nil }
            let nodes = allNames.map { proxyName in
                let proxy = proxies[proxyName]
                let history = proxy?["history"] as? [[String: Any]]
                let delay = history?.last?["delay"] as? Int
                return ProxyNode(
                    name: proxyName,
                    type: proxy?["type"] as? String ?? "proxy",
                    delay: delay
                )
            }
            return ProxyGroup(
                name: name,
                type: detail["type"] as? String ?? "select",
                now: detail["now"] as? String ?? "",
                all: nodes
            )
        }
        .sorted { lhs, rhs in
            if lhs.name == "GLOBAL" { return true }
            if rhs.name == "GLOBAL" { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func selectProxy(group: String, proxy: String) async throws {
        try await sendJSON("/proxies/\(group.urlPathEscaped)", method: "PUT", body: ["name": proxy])
    }

    func proxyDelay(proxy: String, url: String = "https://www.gstatic.com/generate_204", timeout: Int = 5000) async throws -> Int {
        let path = "/proxies/\(proxy.urlPathEscaped)/delay"
        let query = "?url=\(url.urlQueryEscaped)&timeout=\(timeout)"
        let json = try await getJSON(path + query)
        return Int(number(json["delay"]))
    }

    func closeConnections() async throws {
        try await sendJSON("/connections", method: "DELETE", body: nil)
    }

    func closeConnection(id: String) async throws {
        try await sendJSON("/connections/\(id.urlPathEscaped)", method: "DELETE", body: nil)
    }

    func connections() async throws -> ([ConnectionItem], Int64, Int64) {
        let json = try await getJSON("/connections")
        let uploadTotal = number(json["uploadTotal"])
        let downloadTotal = number(json["downloadTotal"])
        guard let rows = json["connections"] as? [[String: Any]] else {
            return ([], uploadTotal, downloadTotal)
        }

        let items = rows.map { row -> ConnectionItem in
            let metadata = row["metadata"] as? [String: Any] ?? [:]
            let chains = row["chains"] as? [String] ?? []
            let rule = [
                row["rule"] as? String,
                row["rulePayload"] as? String
            ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return ConnectionItem(
                id: row["id"] as? String ?? UUID().uuidString,
                host: (metadata["host"] as? String)
                    ?? (metadata["destinationIP"] as? String)
                    ?? (metadata["remoteDestination"] as? String)
                    ?? "-",
                process: (metadata["process"] as? String) ?? (metadata["processPath"] as? String) ?? "-",
                network: (metadata["network"] as? String) ?? "-",
                rule: rule.isEmpty ? "-" : rule,
                chain: chains.joined(separator: " -> "),
                upload: number(row["upload"]),
                download: number(row["download"]),
                start: nil
            )
        }
        return (items, uploadTotal, downloadTotal)
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
        guard let providers = json["providers"] as? [String: [String: Any]] else { return [] }
        return providers.map { name, detail in
            let pieces = [
                detail["type"].map { "type: \($0)" },
                detail["vehicleType"].map { "vehicle: \($0)" },
                detail["updatedAt"].map { "updated: \($0)" }
            ].compactMap { $0 }
            return ProviderItem(kind: kind, name: name, detail: pieces.isEmpty ? "-" : pieces.joined(separator: " · "))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func getJSON(_ path: String) async throws -> [String: Any] {
        let url = endpointURL(path)
        var request = URLRequest(url: url)
        applyAuthorization(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func sendJSON(_ path: String, method: String, body: [String: Any]?) async throws {
        let url = endpointURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuthorization(to: &request)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func endpointURL(_ path: String) -> URL {
        URL(string: path.hasPrefix("/") ? path : "/\(path)", relativeTo: baseURL)!.absoluteURL
    }

    private func applyAuthorization(to request: inout URLRequest) {
        let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.isEmpty == false else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw NSError(domain: "MihomoController", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func number(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }
}

private extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }

    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
