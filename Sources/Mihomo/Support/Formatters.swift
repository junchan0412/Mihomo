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

    private static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesActualByteCount = false
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        if abs(value) < 1024 {
            return "\(value) B"
        }
        return byteCount.string(fromByteCount: value)
    }

    static func rate(_ value: Int64) -> String {
        "\(bytes(value))/s"
    }

    static func trimmedMenuText(_ value: String, limit: Int = 30) -> String {
        if value.count <= limit { return value }
        return String(value.prefix(limit - 1)) + "..."
    }

    static func chineseBool(_ value: Bool) -> String {
        value ? "开启" : "关闭"
    }
}
