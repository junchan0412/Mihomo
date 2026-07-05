import Foundation

enum PrivilegedShell {
    static func run(_ shellScript: String) throws -> String {
        let oneLineScript = shellScript
            .split(separator: "\n")
            .map { String($0) }
            .joined(separator: "; ")
        let appleScript = "do shell script \(appleScriptLiteral(oneLineScript)) with administrator privileges"
        let result = try Shell.run("/usr/bin/osascript", ["-e", appleScript])
        guard result.status == 0 else {
            throw NSError(domain: "PrivilegedShell", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: result.stderr.isEmpty ? result.stdout : result.stderr
            ])
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func verifyAdministratorAccess() throws {
        _ = try run("/usr/bin/true")
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
