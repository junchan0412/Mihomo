import Foundation
import MihomoShared

final class HelperCoreRuntime {
    private var process: Process?
    private var logHandle: FileHandle?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func validate(mihomoPath: String, configPath: String, workDirectory: String) throws -> String {
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

    func start(mihomoPath: String, configPath: String, workDirectory: String, logPath: String) throws -> String {
        stop()

        let validation = try validate(mihomoPath: mihomoPath, configPath: configPath, workDirectory: workDirectory)
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
        process.terminationHandler = { [weak self] _ in
            self?.closeLogHandle()
        }
        try process.run()
        self.process = process
        self.logHandle = handle
        return validation
    }

    func stop() {
        guard let process else {
            closeLogHandle()
            return
        }
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    process.interrupt()
                }
            }
        }
        self.process = nil
        closeLogHandle()
    }

    private func closeLogHandle() {
        try? logHandle?.close()
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
