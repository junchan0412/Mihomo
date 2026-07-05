import Foundation

enum Formatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: value)
    }

    static func rate(_ value: Int64) -> String {
        "\(bytes(value))/s"
    }

    static func trimmedMenuText(_ value: String, limit: Int = 30) -> String {
        if value.count <= limit { return value }
        return String(value.prefix(limit - 1)) + "..."
    }
}
