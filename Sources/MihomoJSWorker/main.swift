import Darwin
import Foundation
import JavaScriptCore

private let maximumFragmentBytes = 64 * 1024
private let maximumInputBytes = 1 * 1024 * 1024
private let maximumOutputBytes = 2 * 1024 * 1024

private struct Request: Codable {
    let source: String
    let input: String
}

private struct Response: Codable {
    let output: String?
    let error: String?
}

private func configureResourceLimits() {
    var cpuLimit = rlimit(rlim_cur: 2, rlim_max: 2)
    _ = setrlimit(RLIMIT_CPU, &cpuLimit)
    let addressSpace = rlim_t(128 * 1024 * 1024)
    var memoryLimit = rlimit(rlim_cur: addressSpace, rlim_max: addressSpace)
    _ = setrlimit(RLIMIT_AS, &memoryLimit)
}

private func write(_ response: Response) {
    guard let data = try? JSONEncoder().encode(response) else { return }
    FileHandle.standardOutput.write(data)
}

configureResourceLimits()

do {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let request = try JSONDecoder().decode(Request.self, from: data)
    guard request.source.lengthOfBytes(using: .utf8) <= maximumFragmentBytes else {
        write(Response(output: nil, error: "JS 片段超过 64 KiB 限制"))
        exit(1)
    }
    guard request.input.lengthOfBytes(using: .utf8) <= maximumInputBytes else {
        write(Response(output: nil, error: "JS transform 输入超过 1 MiB 限制"))
        exit(1)
    }
    guard let context = JSContext() else {
        write(Response(output: nil, error: "无法创建 JavaScript 上下文"))
        exit(1)
    }

    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    context.evaluateScript(request.source)
    if let exceptionMessage {
        write(Response(output: nil, error: exceptionMessage))
        exit(1)
    }
    guard let transform = context.objectForKeyedSubscript("transform"), transform.isUndefined == false else {
        write(Response(output: request.input, error: nil))
        exit(0)
    }
    guard let output = transform.call(withArguments: [request.input])?.toString() else {
        write(Response(output: nil, error: "transform(config) 必须返回字符串"))
        exit(1)
    }
    if let exceptionMessage {
        write(Response(output: nil, error: exceptionMessage))
        exit(1)
    }
    guard output.lengthOfBytes(using: .utf8) <= maximumOutputBytes else {
        write(Response(output: nil, error: "JS transform 输出超过 2 MiB 限制"))
        exit(1)
    }
    write(Response(output: output, error: nil))
} catch {
    write(Response(output: nil, error: "JS worker 请求无效：\(error.localizedDescription)"))
    exit(1)
}
