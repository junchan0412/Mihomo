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

    /// Sortable, locale-independent stamp for file names.
    ///
    /// Never use a user-locale formatter for anything written to disk: under a non-Gregorian
    /// calendar `DateFormatter` emits a different era and digits, producing unsortable names
    /// that no longer match the rotation/pruning globs.
    static let fileStamp = posixFormatter("yyyyMMdd-HHmmss")

    /// Same contract as `fileStamp`, with milliseconds for log rotation collisions.
    static let fileStampWithMilliseconds = posixFormatter("yyyyMMdd-HHmmss-SSS")

    /// Timestamp prefix for persisted log lines: fixed width, sortable, and greppable.
    static let logTimestamp = posixFormatter("yyyy-MM-dd HH:mm:ss.SSS")

    private static func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

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
        guard limit > 1 else { return "" }
        if value.count <= limit { return value }
        return String(value.prefix(limit - 1)) + "..."
    }

    static func chineseBool(_ value: Bool) -> String {
        value ? "开启" : "关闭"
    }
}
