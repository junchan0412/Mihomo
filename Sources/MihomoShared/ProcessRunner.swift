import Foundation

public struct ProcessRunResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    /// stdout and stderr joined, blank streams dropped — the shape most callers report to users.
    public var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
    }
}

/// The single subprocess runner shared by the app and the privileged helper.
public enum ProcessRunner {
    @discardableResult
    public static func run(
        _ executable: String,
        _ arguments: [String],
        workDirectory: URL? = nil,
        forcesPOSIXLocale: Bool = false
    ) throws -> ProcessRunResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        if forcesPOSIXLocale {
            // Tools like `networksetup` localise their output. Anything we parse by matching
            // literal English labels has to pin the locale or it silently misreads on a
            // non-English system.
            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"
            environment["LANG"] = "C"
            process.environment = environment
        }
        try process.run()

        // Both pipes must be drained while the child is still running. Waiting for exit first
        // deadlocks as soon as the child fills the 64 KiB pipe buffer: it blocks in write()
        // while we block in waitUntilExit().
        let outData = PipeDrain(stdout.fileHandleForReading)
        let errData = PipeDrain(stderr.fileHandleForReading)
        process.waitUntilExit()

        return ProcessRunResult(
            status: process.terminationStatus,
            stdout: String(data: outData.wait(), encoding: .utf8) ?? "",
            stderr: String(data: errData.wait(), encoding: .utf8) ?? ""
        )
    }
}

/// Reads a pipe to EOF on a background queue so the child process never blocks on a full buffer.
/// `wait()` joins the group before reading `data`, which is the only synchronisation needed.
private final class PipeDrain: @unchecked Sendable {
    private let group = DispatchGroup()
    private var data = Data()

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) { [self] in
            data = handle.readDataToEndOfFile()
        }
    }

    func wait() -> Data {
        group.wait()
        return data
    }
}
