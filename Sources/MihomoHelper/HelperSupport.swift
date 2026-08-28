import Foundation
import MihomoShared

typealias HelperShellResult = ProcessRunResult

/// Helper-side entry point for the shared subprocess runner.
enum HelperShell {
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        workDirectory: URL? = nil,
        forcesPOSIXLocale: Bool = false
    ) throws -> HelperShellResult {
        try ProcessRunner.run(
            executable,
            arguments,
            workDirectory: workDirectory,
            forcesPOSIXLocale: forcesPOSIXLocale
        )
    }

    static func output(_ result: HelperShellResult) -> String {
        result.combinedOutput
    }
}

enum HelperReply {
    static func ok(_ message: String, payload: [String: Any] = [:]) -> NSDictionary {
        var result = payload
        result["ok"] = true
        result["message"] = message
        return result as NSDictionary
    }

    static func transactionOK(
        _ message: String,
        steps: [String],
        rollbackSuggestion: String,
        payload: [String: Any] = [:]
    ) -> NSDictionary {
        var result = payload
        result["transactionSteps"] = steps.joined(separator: "\n")
        result["rollbackSuggestion"] = rollbackSuggestion
        return ok(message, payload: result)
    }

    static func error(_ error: Error, steps: [String] = [], rollbackSuggestion: String = "") -> NSDictionary {
        [
            "ok": false,
            "message": error.localizedDescription,
            "transactionSteps": steps.joined(separator: "\n"),
            "rollbackSuggestion": rollbackSuggestion
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
