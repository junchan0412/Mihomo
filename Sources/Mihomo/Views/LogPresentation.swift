import AppKit
import SwiftUI

enum LogCategory: String, CaseIterable, Identifiable {
    case all
    case general
    case network
    case dhcp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .general: return "常规"
        case .network: return "网络切换"
        case .dhcp: return "DHCP"
        }
    }

    var color: NSColor {
        switch self {
        case .all, .general: return .labelColor
        case .network: return .systemBlue
        case .dhcp: return .systemOrange
        }
    }

    func matches(_ category: LogCategory) -> Bool {
        self == .all || self == category
    }

    static func classify(_ entry: LogEntry) -> LogCategory {
        let text = entry.message.lowercased()
        if text.contains("dhcp") {
            return .dhcp
        }

        let networkKeywords = [
            "系统代理", "代理", "network", "连接", "controller",
            "核心", "helper", "tun", "dns", "route", "路由"
        ]
        if networkKeywords.contains(where: text.contains) {
            return .network
        }
        return .general
    }
}

struct LogPresentationRow: Identifiable, Hashable {
    var entry: LogEntry
    var category: LogCategory
    var title: String
    var detail: String

    var id: UUID { entry.id }
    var time: String { Formatters.shortDate.string(from: entry.date) }
    var level: String { entry.level.uppercased() }

    init(entry: LogEntry) {
        self.entry = entry
        category = LogCategory.classify(entry)

        let message = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let split = Self.splitMessage(message) {
            title = split.title
            detail = split.detail
        } else {
            title = Formatters.trimmedMenuText(message, limit: 54)
            detail = message.count > 54 ? message : "[\(entry.level.uppercased())] \(message)"
        }
    }

    private static func splitMessage(_ message: String) -> (title: String, detail: String)? {
        for separator in ["：", " - "] {
            guard let range = message.range(of: separator) else { continue }
            let title = String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !detail.isEmpty {
                return (title, detail)
            }
        }
        return nil
    }
}

struct LogCategorySidebar: View {
    @Binding var selection: LogCategory

    var body: some View {
        List(selection: $selection) {
            Section("类型") {
            ForEach(LogCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage)
                        .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private extension LogCategory {
    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .general: return "text.alignleft"
        case .network: return "network"
        case .dhcp: return "cable.connector"
        }
    }
}
