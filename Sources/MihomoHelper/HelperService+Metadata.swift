import Foundation
import MihomoShared

extension HelperService {
    func helperVersion(withReply reply: @escaping (NSDictionary) -> Void) {
        let appInfo = appBundleInfo()
        reply(HelperReply.ok("MihomoHelper 0.6.0", payload: [
            "machService": MihomoHelperConstants.machServiceName,
            "effectiveUID": Int(geteuid()),
            "authorizedUserHome": userHomeDirectory.path,
            "authorizedAppBundle": appBundleURL?.path ?? "",
            "authorizedAppVersion": appInfo.version,
            "authorizedAppBuild": appInfo.build
        ]))
    }

    func verifyPrivileges(withReply reply: @escaping (NSDictionary) -> Void) {
        if geteuid() == 0 {
            reply(HelperReply.ok("Helper 正以 root 权限运行", payload: ["effectiveUID": 0]))
        } else {
            reply(HelperReply.error("Helper 未以 root 权限运行，当前 euid=\(geteuid())"))
        }
    }

    private func appBundleInfo() -> (version: String, build: String) {
        guard let appBundleURL else { return ("", "") }
        let infoURL = appBundleURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
        return (
            info?["CFBundleShortVersionString"] as? String ?? "",
            info?["CFBundleVersion"] as? String ?? ""
        )
    }
}
