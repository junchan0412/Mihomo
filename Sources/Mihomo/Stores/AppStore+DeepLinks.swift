import Foundation

extension AppStore {
    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "mihomo" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        do {
            switch command {
            case "open-section":
                guard let rawSection = query["section"], let section = AppSection(rawValue: rawSection) else { return }
                selectedSection = section
                isLightweightModeActive = false
            case "install-profile", "profile":
                guard let value = query["url"], let importURL = URL(string: value) else { return }
                if importURL.isFileURL {
                    let item = try profileStore.importLocalProfile(fileURL: importURL, name: query["name"], settings: settings)
                    profiles.append(item)
                    settings.activeProfileID = item.id
                } else {
                    let item = try await profileStore.importRemoteProfile(urlString: value, name: query["name"], settings: settings)
                    profiles.append(item)
                    settings.activeProfileID = item.id
                }
                try profileStore.saveProfiles(profiles)
                try profileStore.saveSettings(settings)
                refreshConfigArtifacts()
                appendLog("info", "深链已导入配置")
            case "install-fragment", "fragment":
                let kind = ConfigFragmentKind(rawValue: query["kind"] ?? "yaml") ?? .yaml
                if let value = query["content"] {
                    try configFragmentStore.validateFragmentContent(value, kind: kind)
                    addConfigFragment(name: query["name"] ?? "", kind: kind, content: value)
                } else if let value = query["url"], let importURL = URL(string: value) {
                    let succeeded: Bool
                    if importURL.isFileURL {
                        succeeded = await importLocalConfigFragment(
                            url: importURL,
                            name: query["name"],
                            kind: kind
                        )
                    } else {
                        succeeded = await importRemoteConfigFragment(
                            urlString: value,
                            name: query["name"] ?? "",
                            kind: kind
                        )
                    }
                    guard succeeded else {
                        throw NSError(
                            domain: "Mihomo.DeepLink",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: configFragmentImportStatus]
                        )
                    }
                } else {
                    throw NSError(
                        domain: "Mihomo.DeepLink",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "覆写深链缺少 content 或 url"]
                    )
                }
                appendLog("info", "深链已导入覆写片段")
            default:
                appendLog("warning", "未知深链命令：\(command)")
            }
        } catch {
            appendLog("error", "深链处理失败：\(error.localizedDescription)")
        }
    }
}
