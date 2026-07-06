import Foundation
import Darwin
import MihomoShared
import Security

private final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard authorize(connection: connection) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: MihomoHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    private func authorize(connection: NSXPCConnection) -> Bool {
        guard let executablePath = processPath(pid: connection.processIdentifier),
              executablePath.hasSuffix("/Contents/MacOS/Mihomo"),
              let appURL = appBundleURL(forExecutablePath: executablePath),
              bundleIdentifier(appURL: appURL) == MihomoHelperConstants.appBundleIdentifier,
              codeSignatureIdentifier(appURL: appURL) == MihomoHelperConstants.appBundleIdentifier,
              appSatisfiesCodeRequirement(appURL: appURL)
        else {
            return false
        }
        return true
    }

    private func processPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private func appBundleURL(forExecutablePath path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private func bundleIdentifier(appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: infoURL) as? [String: Any])?["CFBundleIdentifier"] as? String
    }

    private func codeSignatureIdentifier(appURL: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", appURL.path]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.components(separatedBy: .newlines) where line.hasPrefix("Identifier=") {
            return String(line.dropFirst("Identifier=".count))
        }
        return nil
    }

    private func appSatisfiesCodeRequirement(appURL: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess,
              let code
        else { return false }

        var requirement: SecRequirement?
        let requirementText = #"identifier "\#(MihomoHelperConstants.appBundleIdentifier)""# as CFString
        guard SecRequirementCreateWithString(requirementText, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }

        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}

private let delegate = HelperDelegate()
private let listener = NSXPCListener(machServiceName: MihomoHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
