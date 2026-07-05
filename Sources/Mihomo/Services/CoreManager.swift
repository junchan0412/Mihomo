import Foundation

final class CoreManager {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func validateConfig(mihomoPath: String, configPath: URL, workDirectory: URL) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: mihomoPath) else {
            throw NSError(domain: "Mihomo", code: 10, userInfo: [NSLocalizedDescriptionKey: "mihomo binary is not executable"])
        }

        let result = try Shell.run(mihomoPath, ["-t", "-d", workDirectory.path, "-f", configPath.path])
        let output = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard result.status == 0 else {
            throw NSError(domain: "Mihomo", code: Int(result.status), userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "mihomo config test failed" : output
            ])
        }
        return output
    }

    func start(
        mihomoPath: String,
        configPath: URL,
        workDirectory: URL,
        onLog: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) throws {
        stop()

        guard FileManager.default.isExecutableFile(atPath: mihomoPath) else {
            throw NSError(domain: "Mihomo", code: 10, userInfo: [NSLocalizedDescriptionKey: "mihomo binary is not executable"])
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: mihomoPath)
        process.currentDirectoryURL = workDirectory
        process.arguments = ["-d", workDirectory.path, "-f", configPath.path]
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { onLog(text) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { onLog(text) }
        }

        process.terminationHandler = { process in
            DispatchQueue.main.async { onExit(process.terminationStatus) }
        }

        try process.run()
        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        guard let process, process.isRunning else {
            self.process = nil
            return
        }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                process.interrupt()
            }
        }
        self.process = nil
    }
}
