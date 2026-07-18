import Foundation
import Darwin
import MihomoShared
import Security

private struct AuthorizedClient {
    var appURL: URL
    var userHomeDirectory: URL
}

private struct LegacyAuthorization {
    var appPath: String
    var bundleIdentifier: String
    var cdHash: String
}

private final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let coreRuntime = HelperCoreRuntime()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let client = authorizedClient(connection: connection) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: MihomoHelperXPCProtocol.self)
        connection.exportedObject = HelperService(
            appBundleURL: client.appURL,
            userHomeDirectory: client.userHomeDirectory,
            coreRuntime: coreRuntime
        )
        connection.resume()
        return true
    }

    private func authorizedClient(connection: NSXPCConnection) -> AuthorizedClient? {
        guard let executablePath = processPath(pid: connection.processIdentifier),
              executablePath.hasSuffix("/Contents/MacOS/Mihomo"),
              let appURL = appBundleURL(forExecutablePath: executablePath),
              bundleIdentifier(appURL: appURL) == MihomoHelperConstants.appBundleIdentifier,
              codeSignatureIdentifier(appURL: appURL) == MihomoHelperConstants.appBundleIdentifier,
              appSatisfiesCodeRequirement(appURL: appURL),
              helperAuthorizes(appURL: appURL),
              let homeDirectory = userHomeDirectory(pid: connection.processIdentifier)
        else {
            return nil
        }
        return AuthorizedClient(appURL: appURL.standardizedFileURL, userHomeDirectory: homeDirectory)
    }

    private func helperAuthorizes(appURL: URL) -> Bool {
        if let helperAppURL = helperContainingAppBundleURL() {
            return appURLsMatch(appURL, helperAppURL)
        }
        guard standaloneHelperIsRootOwned(),
              let authorization = legacyAuthorization(),
              authorization.bundleIdentifier == MihomoHelperConstants.appBundleIdentifier,
              appURL.standardizedFileURL.resolvingSymlinksInPath().path == URL(fileURLWithPath: authorization.appPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path,
              let cdHash = codeSignatureValue(named: "CDHash", appURL: appURL)
        else { return false }
        return cdHash.lowercased() == authorization.cdHash.lowercased()
    }

    private func standaloneHelperIsRootOwned() -> Bool {
        guard let path = Bundle.main.executableURL?.path else { return false }
        var info = stat()
        return lstat(path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFREG
            && info.st_uid == 0
            && (info.st_mode & 0o022) == 0
    }

    private func legacyAuthorization() -> LegacyAuthorization? {
        let url = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/dev.codex.Mihomo.Helper.authorization.plist")
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == 0,
              (info.st_mode & 0o022) == 0,
              let values = NSDictionary(contentsOf: url) as? [String: Any],
              let appPath = values["AuthorizedAppPath"] as? String,
              let bundleIdentifier = values["AuthorizedAppBundleIdentifier"] as? String,
              let cdHash = values["AuthorizedAppCDHash"] as? String
        else { return nil }
        return LegacyAuthorization(appPath: appPath, bundleIdentifier: bundleIdentifier, cdHash: cdHash)
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

    private func helperContainingAppBundleURL() -> URL? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        return appBundleURL(forExecutablePath: executableURL.path)
    }

    private func appURLsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func bundleIdentifier(appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: infoURL) as? [String: Any])?["CFBundleIdentifier"] as? String
    }

    private func codeSignatureIdentifier(appURL: URL) -> String? {
        codeSignatureValue(named: "Identifier", appURL: appURL)
    }

    private func codeSignatureValue(named name: String, appURL: URL) -> String? {
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
        let prefix = "\(name)="
        for line in text.components(separatedBy: .newlines) where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
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

    private func userHomeDirectory(pid: pid_t) -> URL? {
        var info = proc_bsdshortinfo()
        let size = MemoryLayout<proc_bsdshortinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: size) { buffer in
                proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, buffer, Int32(size))
            }
        }
        guard result == Int32(size),
              let entry = getpwuid(info.pbsi_uid),
              let home = entry.pointee.pw_dir
        else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: home)).standardizedFileURL
    }
}

private let delegate = HelperDelegate()
private let listener = NSXPCListener(machServiceName: MihomoHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
