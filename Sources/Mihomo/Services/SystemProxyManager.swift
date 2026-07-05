import Foundation

final class SystemProxyManager {
    func networkServices() -> [String] {
        guard let result = try? Shell.run("/usr/sbin/networksetup", ["-listallnetworkservices"]),
              result.status == 0
        else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .dropFirst()
            .filter { !$0.hasPrefix("*") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func enable(host: String, port: Int, socksPort: Int) throws {
        for service in networkServices() {
            try run(["-setwebproxy", service, host, "\(port)"])
            try run(["-setsecurewebproxy", service, host, "\(port)"])
            if socksPort > 0 {
                try run(["-setsocksfirewallproxy", service, host, "\(socksPort)"])
            }
            try run(["-setproxybypassdomains", service, "localhost", "127.0.0.1", "*.local"])
        }
    }

    func disable() throws {
        for service in networkServices() {
            try run(["-setwebproxystate", service, "off"])
            try run(["-setsecurewebproxystate", service, "off"])
            try run(["-setsocksfirewallproxystate", service, "off"])
        }
    }

    private func run(_ arguments: [String]) throws {
        let result = try Shell.run("/usr/sbin/networksetup", arguments)
        guard result.status == 0 else {
            throw NSError(domain: "SystemProxy", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
    }
}
