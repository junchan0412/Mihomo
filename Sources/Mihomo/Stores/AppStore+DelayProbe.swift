import Foundation

// The off-actor half of policy delay testing: pure probes plus the value types they exchange with
// `AppStore+PolicyTesting`, which keeps the store-facing orchestration.
extension AppStore {
    nonisolated static func measureDelay(
        for target: ProxyDelayTarget,
        request: DelayProbeRequest
    ) async -> ProxyDelayResult {
        if isRejectProxy(type: target.type, name: target.proxy) {
            return ProxyDelayResult(proxy: target.proxy, delay: nil, errorMessage: nil, skippedMessage: "REJECT 不可测速")
        }
        if isDirectProxy(type: target.type, name: target.proxy) {
            do {
                let delay = try await measureDirectDelay(urls: request.directURLs, timeout: request.timeout)
                return ProxyDelayResult(proxy: target.proxy, delay: delay, errorMessage: nil, skippedMessage: nil)
            } catch {
                return ProxyDelayResult(
                    proxy: target.proxy,
                    delay: nil,
                    errorMessage: describeProbeFailure(error),
                    skippedMessage: nil
                )
            }
        }

        let client = MihomoControllerClient(host: request.host, port: request.port, secret: request.secret)
        var failures: [String] = []
        for url in request.urls {
            do {
                let delay = try await client.proxyDelay(proxy: target.proxy, url: url, timeout: request.timeout)
                return ProxyDelayResult(proxy: target.proxy, delay: delay, errorMessage: nil, skippedMessage: nil)
            } catch {
                failures.append(describeProbeFailure(error))
            }
        }
        return ProxyDelayResult(
            proxy: target.proxy,
            delay: nil,
            errorMessage: failures.joined(separator: "，"),
            skippedMessage: nil
        )
    }

    /// Classifies by error code before falling back to text.
    ///
    /// `URLError.localizedDescription` follows the system language, so matching it against English
    /// phrases silently stops working on a non-English Mac. Only mihomo's own messages — which it
    /// emits in English — are left to the string matching in `friendlyDelayError`.
    nonisolated static func describeProbeFailure(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "超时"
            case .cannotFindHost, .dnsLookupFailed:
                return "DNS 解析失败"
            case .cannotConnectToHost:
                return "连接被拒绝"
            case .userAuthenticationRequired:
                return "核心控制通道的访问密钥错误"
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络不可用"
            default:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == "MihomoController", nsError.code == 401 {
            return "核心控制通道的访问密钥错误"
        }
        return error.localizedDescription
    }

    nonisolated static func isDirectProxy(type: String, name: String) -> Bool {
        type.localizedCaseInsensitiveCompare("direct") == .orderedSame
            || name.localizedCaseInsensitiveCompare("direct") == .orderedSame
    }

    nonisolated static func isRejectProxy(type: String, name: String) -> Bool {
        type.localizedCaseInsensitiveCompare("reject") == .orderedSame
            || name.localizedCaseInsensitiveCompare("reject") == .orderedSame
    }

    nonisolated static func measureDirectDelay(urls: [String], timeout: Int) async throws -> Int {
        var failures: [String] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else {
                failures.append("测速 URL 无效")
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.timeoutInterval = TimeInterval(timeout) / 1000

                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = TimeInterval(timeout) / 1000
                configuration.timeoutIntervalForResource = TimeInterval(timeout) / 1000
                configuration.waitsForConnectivity = false
                configuration.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: false,
                    kCFNetworkProxiesHTTPSEnable as String: false,
                    kCFNetworkProxiesSOCKSEnable as String: false
                ]

                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                let startedAt = Date()
                _ = try await session.data(for: request)
                return max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        throw NSError(domain: "DirectDelay", code: 1, userInfo: [
            NSLocalizedDescriptionKey: failures.isEmpty ? "DIRECT 直连测速失败" : failures.joined(separator: "，")
        ])
    }
}

enum DelayTestURLSelection {
    static func proxyURLs(settings: AppSettings) -> [String] {
        let configured = settings.delayTestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = configured.isEmpty ? AppSettings.default.delayTestURL : configured
        return unique([
            primary,
            AppSettings.default.delayTestURL,
            "https://www.gstatic.com/generate_204"
        ])
    }

    static func directURLs(settings: AppSettings) -> [String] {
        let configured = settings.directDelayTestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = configured.isEmpty ? AppSettings.default.directDelayTestURL : configured
        return unique([primary, AppSettings.default.directDelayTestURL])
    }

    private static func unique(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}

struct ProxyDelayResult: Sendable {
    var proxy: String
    var delay: Int?
    var errorMessage: String?
    var skippedMessage: String?
}

struct ProxyDelayTarget: Sendable {
    var proxy: String
    var type: String
}

struct DelayProbeRequest: Sendable {
    var host: String
    var port: Int
    var secret: String
    var urls: [String]
    var directURLs: [String]
    var timeout: Int
}
