import Foundation
import MihomoShared

typealias ShellResult = ProcessRunResult

/// App-side entry point for the shared subprocess runner.
enum Shell {
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        workDirectory: URL? = nil,
        forcesPOSIXLocale: Bool = false
    ) throws -> ShellResult {
        try ProcessRunner.run(
            executable,
            arguments,
            workDirectory: workDirectory,
            forcesPOSIXLocale: forcesPOSIXLocale
        )
    }
}
