import Foundation

enum ConfigFragmentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case yaml
    case javascript

    var title: String {
        switch self {
        case .yaml: return "YAML"
        case .javascript: return "JavaScript"
        }
    }
}

enum ConfigFragmentSource: String, Codable, CaseIterable, Hashable, Sendable {
    case local
    case remote

    var title: String {
        switch self {
        case .local: return "本地"
        case .remote: return "远程"
        }
    }
}

struct ConfigFragment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: ConfigFragmentKind
    var enabled: Bool
    var content: String
    var updatedAt = Date()
    var appliesGlobally = true
    var profileIDs: [UUID] = []
    var source: ConfigFragmentSource = .local
    var location = ""
    var certificateFingerprint: String?

    var isRemote: Bool { source == .remote }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case enabled
        case content
        case updatedAt
        case appliesGlobally
        case profileIDs
        case source
        case location
        case certificateFingerprint
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: ConfigFragmentKind,
        enabled: Bool,
        content: String,
        updatedAt: Date = Date(),
        appliesGlobally: Bool = true,
        profileIDs: [UUID] = [],
        source: ConfigFragmentSource = .local,
        location: String = "",
        certificateFingerprint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.content = content
        self.updatedAt = updatedAt
        self.appliesGlobally = appliesGlobally
        self.profileIDs = profileIDs
        self.source = source
        self.location = location
        self.certificateFingerprint = certificateFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ConfigFragmentKind.self, forKey: .kind)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        content = try container.decode(String.self, forKey: .content)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        appliesGlobally = try container.decodeIfPresent(Bool.self, forKey: .appliesGlobally) ?? true
        profileIDs = try container.decodeIfPresent([UUID].self, forKey: .profileIDs) ?? []
        source = try container.decodeIfPresent(ConfigFragmentSource.self, forKey: .source) ?? .local
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        certificateFingerprint = try container.decodeIfPresent(String.self, forKey: .certificateFingerprint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(content, forKey: .content)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(appliesGlobally, forKey: .appliesGlobally)
        try container.encode(profileIDs, forKey: .profileIDs)
        try container.encode(source, forKey: .source)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(certificateFingerprint, forKey: .certificateFingerprint)
    }

    func applies(to profileID: UUID) -> Bool {
        enabled && (appliesGlobally || profileIDs.contains(profileID))
    }
}

struct ConfigFragmentEditorRoute: Codable, Hashable {
    var fragmentID: UUID?
    var windowID: UUID

    static func editing(_ fragmentID: UUID) -> Self {
        Self(fragmentID: fragmentID, windowID: fragmentID)
    }

    static func creating() -> Self {
        Self(fragmentID: nil, windowID: UUID())
    }
}

struct ConfigFragmentPreviewRoute: Codable, Hashable {
    var fragmentIDs: [UUID]
}
