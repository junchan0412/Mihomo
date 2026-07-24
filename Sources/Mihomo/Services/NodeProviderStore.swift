import Foundation

struct NodeProviderStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [NodeProvider] {
        try AppPaths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: AppPaths.nodeProvidersFile.path) else { return [] }
        return try decoder.decode([NodeProvider].self, from: Data(contentsOf: AppPaths.nodeProvidersFile))
    }

    func save(_ providers: [NodeProvider]) throws {
        try validate(providers)
        try AppPaths.ensureBaseDirectories()
        try encoder.encode(providers).write(to: AppPaths.nodeProvidersFile, options: .atomic)
    }

    func validate(_ providers: [NodeProvider]) throws {
        var names = Set<String>()
        for provider in providers {
            let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { throw error("节点提供商名称不能为空。") }
            guard names.insert(provider.normalizedName).inserted else {
                throw error("节点提供商名称重复：\(name)。同名条目会自动合并，请使用不同名称。")
            }

            let type = provider.providerType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard type.isEmpty == false else { throw error("节点提供商类型不能为空。") }
            if ["http", "https"].contains(type) {
                guard let url = URL(string: provider.url.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      url.host?.isEmpty == false
                else { throw error("HTTP 节点提供商 URL 必须是有效的 HTTP(S) 地址。") }
            }

            guard provider.interval >= 0 else { throw error("节点提供商更新间隔不能小于 0。") }
            guard provider.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw error("节点提供商分组不能为空。")
            }
            _ = try ProviderResourceManager().targetURL(for: provider.providerItem)
        }
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "Mihomo.NodeProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
