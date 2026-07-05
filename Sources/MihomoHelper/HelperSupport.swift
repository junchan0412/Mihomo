import Foundation

struct HelperShellResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum HelperShell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], workDirectory: URL? = nil) throws -> HelperShellResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return HelperShellResult(
            status: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    static func output(_ result: HelperShellResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum HelperReply {
    static func ok(_ message: String, payload: [String: Any] = [:]) -> NSDictionary {
        var result = payload
        result["ok"] = true
        result["message"] = message
        return result as NSDictionary
    }

    static func error(_ error: Error) -> NSDictionary {
        [
            "ok": false,
            "message": error.localizedDescription
        ] as NSDictionary
    }

    static func error(_ message: String) -> NSDictionary {
        [
            "ok": false,
            "message": message
        ] as NSDictionary
    }
}

extension String {
    var nonEmptyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
