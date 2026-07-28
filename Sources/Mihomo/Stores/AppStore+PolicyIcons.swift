import AppKit
import Foundation

extension AppStore {
    func preloadPolicyGroupIcons() async {
        await preloadPolicyGroupIcons(for: proxyGroups)
    }

    func preloadPolicyGroupIcons(for groups: [ProxyGroup]) async {
        let groupIconPairs = groups.compactMap { group -> (String, String)? in
            guard let icon = group.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
                  icon.isEmpty == false
            else { return nil }
            return (group.id, icon)
        }
        let validIDs = Set(groupIconPairs.map(\.0))
        if policyGroupIconImages.keys.contains(where: { validIDs.contains($0) == false }) {
            policyGroupIconImages = policyGroupIconImages.filter { validIDs.contains($0.key) }
        }

        await withTaskGroup(of: (String, Data?).self) { taskGroup in
            for (groupID, icon) in groupIconPairs where policyGroupIconImages[groupID] == nil {
                taskGroup.addTask {
                    (groupID, await Self.loadPolicyGroupIconData(icon))
                }
            }

            var loadedImages: [String: NSImage] = [:]
            for await (groupID, data) in taskGroup {
                guard let data, let image = NSImage(data: data) else { continue }
                loadedImages[groupID] = image
            }

            if loadedImages.isEmpty == false {
                policyGroupIconImages.merge(loadedImages) { current, _ in current }
            }
        }
    }

    nonisolated private static func loadPolicyGroupIconData(_ icon: String) async -> Data? {
        if let url = URL(string: icon), url.scheme?.hasPrefix("http") == true {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 8
            guard let (data, _) = try? await NetworkClient.data(for: request, kind: .controller) else { return nil }
            return data
        }
        return try? Data(contentsOf: URL(fileURLWithPath: (icon as NSString).expandingTildeInPath))
    }
}
