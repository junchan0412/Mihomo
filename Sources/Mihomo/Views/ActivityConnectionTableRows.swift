import AppKit
import Foundation

struct ConnectionTableRow: Identifiable, Hashable {
    var connection: ConnectionItem
    var isActive = true
    var sequence: Int = 0

    var id: String { connection.id }
    var idText: String { "#\(sequence)" }

    var timeText: String {
        guard let start = connection.start else { return "-" }
        return Formatters.logTime.string(from: start)
    }

    var clientText: String { connection.processName }

    var clientIcon: NSImage? {
        connection.processIcon
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: connection.processName)
    }

    var ruleText: String {
        let type = connection.ruleType.isEmpty ? connection.rule : connection.ruleType
        let payload = connection.rulePayload
        if payload.isEmpty || payload == "-" {
            return type.isEmpty ? "-" : type
        }
        return "\(type) \(payload)"
    }

    var policyText: String {
        let last = connection.chain.components(separatedBy: " -> ").last ?? ""
        return last.isEmpty ? "DIRECT" : last
    }

    var uploadText: String { Formatters.bytes(connection.upload) }
    var downloadText: String { Formatters.bytes(connection.download) }

    var durationText: String {
        guard let start = connection.start else { return "-" }
        return Self.durationText(from: Date().timeIntervalSince(start))
    }

    var methodText: String {
        let text = connection.metadataType.isEmpty ? connection.network : connection.metadataType
        return text.isEmpty ? "-" : text.uppercased()
    }

    var addressText: String { connection.remoteEndpoint }
    var statusColor: NSColor { isActive ? .systemGreen : .systemYellow }

    private static func durationText(from interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) m" }
        return "\(minutes / 60) h"
    }
}

struct ActivityConnectionTableRowsInput: Equatable {
    var sourceRevision: Int
    var filterText: String
    var selectedFilterID: String
    var moduleTab: ActivityModuleTab
    var grouping: ConnectionSidebarGrouping
}

enum ActivityConnectionTableRows {
    static func make(
        from connections: [ConnectionItem],
        activeConnectionIDs: Set<String>
    ) -> [ConnectionTableRow] {
        connections
            .sorted(by: newestFirst)
            .enumerated()
            .map { offset, connection in
                ConnectionTableRow(
                    connection: connection,
                    isActive: activeConnectionIDs.contains(connection.id),
                    sequence: offset + 1
                )
            }
    }

    private static func newestFirst(_ lhs: ConnectionItem, _ rhs: ConnectionItem) -> Bool {
        switch (lhs.start, rhs.start) {
        case let (lhs?, rhs?):
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
        }
    }
}
