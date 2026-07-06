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
        return Self.parseProxyGroups(from: json)
    }

    static func parseProxyGroups(from json: [String: Any]) -> [ProxyGroup] {
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
                all: nodes,
                icon: detail["icon"] as? String
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

    static func parseConnections(from json: [String: Any]) -> ([ConnectionItem], Int64, Int64) {
        let uploadTotal = Self.number(json["uploadTotal"])
        let downloadTotal = Self.number(json["downloadTotal"])
        guard let rows = json["connections"] as? [[String: Any]] else {
            return ([], uploadTotal, downloadTotal)
        }

        let items = rows.map { row -> ConnectionItem in
            let metadata = row["metadata"] as? [String: Any] ?? [:]
            let chains = row["chains"] as? [String] ?? []
            let ruleType = row["rule"] as? String ?? ""
            let rulePayload = row["rulePayload"] as? String ?? ""
            let rule = [
                ruleType,
                rulePayload
            ]
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
                ruleType: ruleType,
                rulePayload: rulePayload,
                chain: chains.joined(separator: " -> "),
                upload: Self.number(row["upload"]),
                download: Self.number(row["download"]),
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
        return Self.parseProviderItems(from: json, kind: kind)
    }

    static func parseProviderItems(from json: [String: Any], kind: String) -> [ProviderItem] {
        guard let providers = json["providers"] as? [String: [String: Any]] else { return [] }
        return providers.map { name, detail in
            let count = providerEntryCount(kind: kind, detail: detail)
            let members = providerMemberNames(kind: kind, detail: detail)
            let pieces = [
                detail["type"].map { "type: \($0)" },
                detail["vehicleType"].map { "vehicle: \($0)" },
                detail["updatedAt"].map { "updated: \($0)" },
                count > 0 ? "items: \(count)" : nil
            ].compactMap { $0 }
            return ProviderItem(
                kind: kind,
                name: name,
                detail: pieces.isEmpty ? "-" : pieces.joined(separator: " · "),
                providerType: detail["type"].map { "\($0)" } ?? "",
                ruleCount: count,
                memberNames: members
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func providerEntryCount(kind: String, detail: [String: Any]) -> Int {
        if kind == "Proxy" {
            if let proxies = detail["proxies"] as? [Any] { return proxies.count }
        } else {
            if let rules = detail["rules"] as? [Any] { return rules.count }
            if let count = detail["ruleCount"] as? Int { return count }
        }
        return 0
    }

    private static func providerMemberNames(kind: String, detail: [String: Any]) -> [String] {
        let entries: [Any]
        if kind == "Proxy" {
            entries = detail["proxies"] as? [Any] ?? []
        } else {
            entries = detail["rules"] as? [Any] ?? []
        }

        return entries.compactMap { entry in
            if let name = entry as? String { return name }
            if let map = entry as? [String: Any] {
                return (map["name"] as? String)
                    ?? (map["payload"] as? String)
                    ?? (map["rule"] as? String)
            }
            return nil
        }
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

    private static func number(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
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
