import Foundation

struct JSOverrideRunner {
    static let maximumFragmentBytes = 64 * 1024
    static let maximumInputBytes = 1 * 1024 * 1024
    static let maximumOutputBytes = 2 * 1024 * 1024
    static let maximumEnabledFragments = 8
    static let executionTimeout: TimeInterval = 1.5

    private let workerURL: URL?

    init(workerURL: URL? = nil) {
        self.workerURL = workerURL
    }

    func apply(fragments: [ConfigFragment], to content: String) throws -> String {
        let enabledFragments = fragments.filter { $0.enabled && $0.kind == .javascript }
        guard enabledFragments.count <= Self.maximumEnabledFragments else {
            throw error("JS 片段数量不能超过 \(Self.maximumEnabledFragments) 个")
        }

        var result = try validatedInput(content)
        for fragment in enabledFragments {
            guard fragment.content.lengthOfBytes(using: .utf8) <= Self.maximumFragmentBytes else {
                throw error("\(fragment.name)：JS 片段不能超过 \(Self.maximumFragmentBytes / 1024) KiB")
            }
            result = try execute(fragment: fragment, input: result)
        }
        return result
    }

    private func execute(fragment: ConfigFragment, input: String) throws -> String {
        let worker = try resolvedWorkerURL()
        let request = JSOverrideWorkerRequest(source: fragment.content, input: input)
        let requestData = try JSONEncoder().encode(request)
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = worker
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let completion = DispatchGroup()
        completion.enter()
        process.terminationHandler = { _ in completion.leave() }
        do {
            try process.run()
        } catch let launchError {
            completion.leave()
            throw error("无法启动 JS worker：\(launchError.localizedDescription)")
        }
        var responseData = Data()
        var errorData = Data()
        let outputRead = DispatchGroup()
        outputRead.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            responseData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputRead.leave()
        }
        outputRead.enter()
        DispatchQueue.global(qos: .utility).async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            outputRead.leave()
        }
        inputPipe.fileHandleForWriting.write(requestData)
        try inputPipe.fileHandleForWriting.close()

        if completion.wait(timeout: .now() + Self.executionTimeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            outputRead.wait()
            throw error("\(fragment.name)：JS transform 执行超时（\(Self.executionTimeout) 秒），已终止 worker")
        }

        outputRead.wait()
        guard let response = try? JSONDecoder().decode(JSOverrideWorkerResponse.self, from: responseData) else {
            let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw error("\(fragment.name)：JS worker 未返回有效结果\(detail.map { "：\($0)" } ?? "")")
        }
        if let message = response.error {
            throw error("\(fragment.name)：\(message)")
        }
        guard let output = response.output else {
            throw error("\(fragment.name)：JS worker 未返回 transform 输出")
        }
        guard output.lengthOfBytes(using: .utf8) <= Self.maximumOutputBytes else {
            throw error("\(fragment.name)：JS transform 输出不能超过 \(Self.maximumOutputBytes / 1024 / 1024) MiB")
        }
        return output
    }

    private func validatedInput(_ content: String) throws -> String {
        guard content.lengthOfBytes(using: .utf8) <= Self.maximumInputBytes else {
            throw error("JS transform 输入不能超过 \(Self.maximumInputBytes / 1024 / 1024) MiB")
        }
        return content
    }

    private func resolvedWorkerURL() throws -> URL {
        if let workerURL {
            guard FileManager.default.isExecutableFile(atPath: workerURL.path) else {
                throw error("JS worker 不可执行：\(workerURL.path)")
            }
            return workerURL
        }
        guard let bundledWorker = Bundle.main.url(forResource: "MihomoJSWorker", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: bundledWorker.path)
        else {
            throw error("JS worker 未包含在应用包中")
        }
        return bundledWorker
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "JSOverride", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct JSOverrideWorkerRequest: Codable {
    let source: String
    let input: String
}

struct JSOverrideWorkerResponse: Codable {
    let output: String?
    let error: String?
}
