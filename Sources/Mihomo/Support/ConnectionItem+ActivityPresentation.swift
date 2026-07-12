import AppKit
import Foundation

extension ConnectionItem {
    var processName: String {
        if process.isEmpty || process == "-" {
            return processPathDisplay == "-" ? "未知客户端" : URL(fileURLWithPath: processPathDisplay).lastPathComponent
        }
        if process.contains("/") {
            return URL(fileURLWithPath: process).lastPathComponent
        }
        return process
    }

    var processPathDisplay: String {
        if processPath.isEmpty {
            return process.contains("/") ? process : "-"
        }
        return processPath
    }

    var clientGroupingKey: String {
        processName
    }

    var hostGroupingKey: String {
        if hostDisplay != "-" {
            return hostDisplay
        }
        let remoteHost = remoteEndpoint.split(separator: ":").first.map(String.init) ?? ""
        return remoteHost.isEmpty ? "未知主机" : remoteHost
    }

    var processIcon: NSImage? {
        guard let path = processIconPath else { return nil }
        return ConnectionProcessIconCache.icon(for: path)
    }

    private var processIconPath: String? {
        let path = processPathDisplay
        guard path != "-" && path.isEmpty == false else { return nil }

        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let appIndex = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            let appPath = parts.prefix(appIndex + 1).joined(separator: "/")
            if FileManager.default.fileExists(atPath: appPath) {
                return appPath
            }
        }

        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    var hostDisplay: String {
        host.isEmpty ? "-" : host
    }

    var networkDisplay: String {
        network.isEmpty ? "-" : network.uppercased()
    }

    var displayMethod: String {
        let value = metadataType.isEmpty ? network : metadataType
        return value.isEmpty ? "-" : value.uppercased()
    }

    var ruleTypeDisplay: String {
        ruleType.isEmpty ? "-" : ruleType
    }

    var rulePayloadDisplay: String {
        rulePayload.isEmpty ? "-" : rulePayload
    }

    var ruleDisplay: String {
        if rule.isEmpty || rule == "-" {
            return [ruleType, rulePayload].filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty ?? "-"
        }
        return rule
    }

    var chainDisplay: String {
        chain.isEmpty ? "-" : chain
    }

    var policyDisplay: String {
        let policy = chain.components(separatedBy: " -> ").last ?? ""
        return policy.isEmpty ? "DIRECT" : policy
    }

    var sourceIPDisplay: String {
        sourceIP.isEmpty ? "-" : sourceIP
    }

    var sourcePortDisplay: String {
        sourcePort.isEmpty ? "-" : sourcePort
    }

    var destinationIPDisplay: String {
        destinationIP.isEmpty ? "-" : destinationIP
    }

    var destinationPortDisplay: String {
        destinationPort.isEmpty ? "-" : destinationPort
    }

    var remoteDestinationDisplay: String {
        remoteDestination.isEmpty ? "-" : remoteDestination
    }

    var sourceEndpoint: String {
        endpoint(host: sourceIP, port: sourcePort)
    }

    var remoteEndpoint: String {
        if remoteDestination.isEmpty == false {
            return remoteDestination
        }
        return endpoint(host: hostDisplay == "-" ? destinationIP : hostDisplay, port: destinationPort)
    }

    var startText: String {
        guard let start else { return "-" }
        return Formatters.shortDate.string(from: start)
    }

    var durationText: String {
        guard let start else { return "-" }
        let seconds = max(0, Int(Date().timeIntervalSince(start).rounded()))
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) m"
        }
        return "\(minutes / 60) h"
    }

    private func endpoint(host: String, port: String) -> String {
        let cleanHost = host.isEmpty ? "-" : host
        guard port.isEmpty == false, cleanHost != "-" else {
            return cleanHost
        }
        return "\(cleanHost):\(port)"
    }
}
private enum ConnectionProcessIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
