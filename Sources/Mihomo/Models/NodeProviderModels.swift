import Foundation

struct NodeProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var path: String
    var providerType = "http"
    var interval: Int = 86_400
    var enabled = true
    var profileIDs: [UUID] = []
    // Imported definitions retain their origin so they win when merging a same-named local record.
    var sourceProfileID: UUID?
    var group = "未分组"
    var tags: [String] = []
    var updatedAt = Date()

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        path: String? = nil,
        providerType: String = "http",
        interval: Int = 86_400,
        enabled: Bool = true,
        profileIDs: [UUID] = [],
        sourceProfileID: UUID? = nil,
        group: String = "未分组",
        tags: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.path = path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? path!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "proxy_providers/managed-\(id.uuidString.lowercased()).yaml"
        self.providerType = providerType
        self.interval = interval
        self.enabled = enabled
        self.profileIDs = profileIDs
        self.sourceProfileID = sourceProfileID
        self.group = group
        self.tags = tags
        self.updatedAt = updatedAt
    }

    func applies(to profileID: UUID) -> Bool {
        enabled && profileIDs.contains(profileID)
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    var sourceIdentity: String {
        "\(sourceProfileID?.uuidString.lowercased() ?? "local-\(id.uuidString.lowercased())")\u{1F}\(normalizedName)"
    }

    var definition: NodeProviderDefinition {
        NodeProviderDefinition(providerType: providerType, url: url, path: path, interval: interval)
    }

    static func canonicalized(_ providers: [NodeProvider]) -> [NodeProvider] {
        providers.reduce(into: []) { result, candidate in
            guard let index = result.firstIndex(where: { $0.normalizedName == candidate.normalizedName }) else {
                result.append(candidate)
                return
            }

            let existing = result[index]
            // A Profile declaration is the canonical definition for a same-named local record.
            var merged = existing.sourceProfileID == nil && candidate.sourceProfileID != nil ? candidate : existing
            merged.id = existing.id
            merged.profileIDs = Array(Set(existing.profileIDs + candidate.profileIDs)).sorted { $0.uuidString < $1.uuidString }
            merged.tags = Array(Set(existing.tags + candidate.tags)).sorted()
            merged.enabled = existing.enabled || candidate.enabled
            merged.updatedAt = max(existing.updatedAt, candidate.updatedAt)
            if existing.group != "未分组", existing.group != "从配置导入" {
                merged.group = existing.group
            }
            result[index] = merged
        }
    }

    var providerItem: ProviderItem {
        ProviderItem(
            kind: "Node",
            name: name,
            detail: "type: \(providerType) · url: \(url) · path: \(path) · interval: \(interval)",
            providerType: providerType,
            remoteURL: url.isEmpty ? nil : url,
            path: path,
            interval: interval
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, url, path, providerType, interval, enabled, profileIDs, sourceProfileID, group, tags, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path)
            ?? "proxy_providers/managed-\(id.uuidString.lowercased()).yaml"
        providerType = try container.decodeIfPresent(String.self, forKey: .providerType) ?? "http"
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 86_400
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        profileIDs = try container.decodeIfPresent([UUID].self, forKey: .profileIDs) ?? []
        sourceProfileID = try container.decodeIfPresent(UUID.self, forKey: .sourceProfileID)
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? "未分组"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct NodeProviderDefinition: Hashable {
    var providerType: String
    var url: String
    var path: String
    var interval: Int

    var normalizedType: String {
        providerType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedInterval: Int { max(0, interval) }

    var summary: String {
        let urlPart = normalizedURL.isEmpty ? "无 URL" : normalizedURL
        return "\(normalizedType) · \(urlPart) · \(normalizedPath)"
    }

    func differs(from other: Self) -> [String] {
        var fields: [String] = []
        if normalizedType != other.normalizedType { fields.append("类型") }
        if normalizedURL != other.normalizedURL { fields.append("URL") }
        if normalizedPath != other.normalizedPath { fields.append("路径") }
        if normalizedInterval != other.normalizedInterval { fields.append("更新间隔") }
        return fields
    }
}

enum NodeProviderProfileChangeKind: String, Hashable {
    case add
    case update
    case remove
    case preserve

    var title: String {
        switch self {
        case .add: return "新增"
        case .update: return "更新"
        case .remove: return "删除"
        case .preserve: return "保留"
        }
    }
}

struct NodeProviderProfileChange: Identifiable, Hashable {
    var id: String { "\(profileID.uuidString)-\(providerName)-\(kind.rawValue)" }
    var profileID: UUID
    var profileName: String
    var providerName: String
    var kind: NodeProviderProfileChangeKind
    var fields: [String]
}

struct NodeProviderConflict: Identifiable, Hashable {
    var id: String { "\(profileID.uuidString)-\(providerName)-\(incomingProviderID.uuidString)" }
    var profileID: UUID
    var profileName: String
    var providerName: String
    var incomingProviderID: UUID
    var incomingSource: String
    var existingSource: String
    var differingFields: [String]
    var requiresResolution: Bool
}

struct NodeProviderProfilePatch: Hashable {
    var profileID: UUID
    var profileName: String
    var originalContent: String
    var updatedContent: String
}

struct NodeProviderChangePreview: Identifiable {
    let id = UUID()
    var title: String
    var proposedProviders: [NodeProvider]
    var profilePatches: [NodeProviderProfilePatch]
    var changes: [NodeProviderProfileChange]
    var conflicts: [NodeProviderConflict]
    var providerDelta: Int
    var providersChanged: Bool
    var deduplicatedProviderCount: Int

    var hasChanges: Bool {
        providersChanged || profilePatches.isEmpty == false || changes.isEmpty == false
    }

    var hasBlockingConflicts: Bool {
        conflicts.contains { $0.requiresResolution }
    }
}

struct NodeProviderUndoSnapshot {
    var title: String
    var nodeProviders: [NodeProvider]
    var profiles: [ProfileItem]
    var profileContents: [UUID: String]
}

struct RemoteProfileRefreshPreview: Identifiable {
    let id = UUID()
    var originalProfile: ProfileItem
    var refreshedProfile: ProfileItem
    var originalContent: String
    var refreshedContent: String
    var preservedProviderNames: [String]

    var requiresProviderConfirmation: Bool {
        preservedProviderNames.isEmpty == false
    }
}
