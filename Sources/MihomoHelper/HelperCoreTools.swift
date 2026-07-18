import Foundation
import Darwin
import MihomoShared

final class HelperCoreRuntime {
    private let lock = NSRecursiveLock()
    private var process: Process?
    private var logHandle: FileHandle?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    func validate(mihomoPath: String, configPath: String, workDirectory: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try validateLocked(
            mihomoPath: mihomoPath,
            configPath: configPath,
            workDirectory: workDirectory
        )
    }

    private func validateLocked(mihomoPath: String, configPath: String, workDirectory: String) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: mihomoPath) else {
            throw NSError(domain: "MihomoHelper.Core", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "mihomo binary is not executable: \(mihomoPath)"
            ])
        }
        let result = try HelperShell.run(
            mihomoPath,
            ["-t", "-d", workDirectory, "-f", configPath],
            workDirectory: URL(fileURLWithPath: workDirectory)
        )
        let output = HelperShell.output(result)
        guard result.status == 0 else {
            throw NSError(domain: "MihomoHelper.Core", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "mihomo config test failed" : output
            ])
        }
        return output
    }

    func start(
        mihomoPath: String,
        configPath: String,
        workDirectory: String,
        logPath: String,
        allowedExecutablePaths: Set<String>
    ) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let validation = try validateLocked(
            mihomoPath: mihomoPath,
            configPath: configPath,
            workDirectory: workDirectory
        )
        _ = try stopLocked(allowedExecutablePaths: allowedExecutablePaths)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: logPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: logPath) == false {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mihomoPath)
        process.arguments = ["-d", workDirectory, "-f", configPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workDirectory)
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self] terminatedProcess in
            self?.handleTermination(of: terminatedProcess)
        }
        self.process = process
        self.logHandle = handle
        do {
            try process.run()
        } catch {
            self.process = nil
            closeLogHandle()
            throw error
        }
        return validation
    }

    @discardableResult
    func stop(allowedExecutablePaths: Set<String>) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try stopLocked(allowedExecutablePaths: allowedExecutablePaths)
    }

    private func stopLocked(allowedExecutablePaths: Set<String>) throws -> String {
        let normalizedPaths = Set(allowedExecutablePaths.map(normalizedPath))
        var processIDs = matchingCoreProcessIDs(allowedExecutablePaths: normalizedPaths)
        if let process, process.isRunning,
           normalizedPaths.contains(normalizedPath(process.executableURL?.path ?? "")) {
            processIDs.insert(process.processIdentifier)
        }

        guard processIDs.isEmpty == false else {
            process = nil
            closeLogHandle()
            return "未发现运行中的 mihomo core"
        }

        let originalCount = processIDs.count
        signal(SIGTERM, processIDs: processIDs, allowedExecutablePaths: normalizedPaths)
        processIDs = waitForExit(
            processIDs: processIDs,
            allowedExecutablePaths: normalizedPaths,
            timeout: 2
        )

        var escalation = "SIGTERM"
        if processIDs.isEmpty == false {
            escalation = "SIGINT"
            signal(SIGINT, processIDs: processIDs, allowedExecutablePaths: normalizedPaths)
            processIDs = waitForExit(
                processIDs: processIDs,
                allowedExecutablePaths: normalizedPaths,
                timeout: 2
            )
        }

        if processIDs.isEmpty == false {
            escalation = "SIGKILL"
            signal(SIGKILL, processIDs: processIDs, allowedExecutablePaths: normalizedPaths)
            processIDs = waitForExit(
                processIDs: processIDs,
                allowedExecutablePaths: normalizedPaths,
                timeout: 2
            )
        }

        guard processIDs.isEmpty else {
            throw NSError(domain: "MihomoHelper.Core", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "mihomo core 未能停止，仍在运行的 PID：\(processIDs.sorted().map(String.init).joined(separator: "、"))"
            ])
        }

        process = nil
        closeLogHandle()
        return "已停止 \(originalCount) 个 mihomo core 进程（\(escalation)）"
    }

    private func matchingCoreProcessIDs(allowedExecutablePaths: Set<String>) -> Set<pid_t> {
        guard allowedExecutablePaths.isEmpty == false,
              let result = try? HelperShell.run("/usr/bin/pgrep", ["-x", "mihomo"]),
              result.status == 0
        else { return [] }

        return Set(result.stdout.split(whereSeparator: \.isWhitespace).compactMap { value in
            guard let processID = pid_t(value),
                  let path = processPath(processID),
                  allowedExecutablePaths.contains(normalizedPath(path))
            else { return nil }
            return processID
        })
    }

    private func signal(
        _ signal: Int32,
        processIDs: Set<pid_t>,
        allowedExecutablePaths: Set<String>
    ) {
        for processID in processIDs {
            guard let path = processPath(processID),
                  allowedExecutablePaths.contains(normalizedPath(path))
            else { continue }
            _ = Darwin.kill(processID, signal)
        }
    }

    private func waitForExit(
        processIDs: Set<pid_t>,
        allowedExecutablePaths: Set<String>,
        timeout: TimeInterval
    ) -> Set<pid_t> {
        let deadline = Date().addingTimeInterval(timeout)
        var remaining = runningProcessIDs(
            processIDs,
            allowedExecutablePaths: allowedExecutablePaths
        )
        while remaining.isEmpty == false, Date() < deadline {
            usleep(50_000)
            remaining = runningProcessIDs(
                remaining,
                allowedExecutablePaths: allowedExecutablePaths
            )
        }
        return remaining
    }

    private func runningProcessIDs(
        _ processIDs: Set<pid_t>,
        allowedExecutablePaths: Set<String>
    ) -> Set<pid_t> {
        Set(processIDs.filter { processID in
            guard let path = processPath(processID) else { return false }
            return allowedExecutablePaths.contains(normalizedPath(path))
        })
    }

    private func processPath(_ processID: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(processID, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private func normalizedPath(_ path: String) -> String {
        guard path.isEmpty == false else { return "" }
        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func handleTermination(of terminatedProcess: Process) {
        lock.lock()
        defer { lock.unlock() }
        guard process === terminatedProcess else { return }
        process = nil
        closeLogHandle()
    }

    private func closeLogHandle() {
        do {
            try logHandle?.close()
        } catch {
            // The process may close asynchronously while a stop transaction is completing.
        }
        logHandle = nil
    }
}

final class HelperCoreLaunchDaemonTool {
    var plistPath: String {
        MihomoHelperConstants.coreLaunchDaemonPlistPath
    }

    func install(corePath: String, configPath: String, workDirectory: String, logPath: String) throws -> String {
        let plist = launchDaemonPlist(corePath: corePath, configPath: configPath, workDirectory: workDirectory, logPath: logPath)
        let target = URL(fileURLWithPath: plistPath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        try bootoutIfLoaded()
        try bootstrap()
        return target.path
    }

    func uninstall() throws {
        try bootoutIfLoaded()
        let target = URL(fileURLWithPath: plistPath)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }

    func start() throws {
        if FileManager.default.fileExists(atPath: plistPath) {
            try bootstrap()
        } else {
            throw NSError(domain: "MihomoHelper.CoreDaemon", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Core LaunchDaemon plist 不存在：\(plistPath)"
            ])
        }
    }

    func stop() throws {
        try bootoutIfLoaded()
    }

    private func bootstrap() throws {
        let result = try HelperShell.run("/bin/launchctl", ["bootstrap", "system", plistPath])
        if result.status != 0 {
            let output = HelperShell.output(result)
            if output.localizedCaseInsensitiveContains("service already loaded") == false,
               output.localizedCaseInsensitiveContains("already exists") == false {
                throw NSError(domain: "MihomoHelper.CoreDaemon", code: Int(result.status), userInfo: [
                    NSLocalizedDescriptionKey: output
                ])
            }
        }
    }

    private func bootoutIfLoaded() throws {
        _ = try? HelperShell.run("/bin/launchctl", ["bootout", "system", plistPath])
    }

    private func launchDaemonPlist(corePath: String, configPath: String, workDirectory: String, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(xml(MihomoHelperConstants.coreLaunchDaemonLabel))</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xml(corePath))</string>
            <string>-d</string>
            <string>\(xml(workDirectory))</string>
            <string>-f</string>
            <string>\(xml(configPath))</string>
          </array>
          <key>WorkingDirectory</key>
          <string>\(xml(workDirectory))</string>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(xml(logPath))</string>
          <key>StandardErrorPath</key>
          <string>\(xml(logPath))</string>
        </dict>
        </plist>
        """
    }

    private func xml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
