import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

final class SpotlightIndexer {
    private let domainIdentifier = "dev.codex.Mihomo.content"
    private var lastFingerprint: String?

    func index(profiles: [ProfileItem], providers: [ProviderItem]) {
        let fingerprint = makeFingerprint(profiles: profiles, providers: providers)
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint

        let profileItems = profiles.map { profile in
            let attributes = CSSearchableItemAttributeSet(contentType: .data)
            attributes.title = profile.name
            attributes.contentDescription = profile.isRemote ? "Mihomo 远程配置" : "Mihomo 本地配置"
            attributes.keywords = ["Mihomo", "配置", profile.isRemote ? "订阅" : "本地"]
            attributes.contentURL = URL(string: "mihomo://open-section?section=profiles")
            return CSSearchableItem(
                uniqueIdentifier: "profile.\(profile.id.uuidString)",
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }

        let providerItems = providers.map { provider in
            let attributes = CSSearchableItemAttributeSet(contentType: .data)
            attributes.title = provider.name
            attributes.contentDescription = "Mihomo \(provider.kind) Provider"
            attributes.keywords = ["Mihomo", "Provider", provider.kind]
            attributes.contentURL = URL(string: "mihomo://open-section?section=resources")
            return CSSearchableItem(
                uniqueIdentifier: "provider.\(provider.id)",
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }

        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            index.indexSearchableItems(profileItems + providerItems)
        }
    }

    private func makeFingerprint(profiles: [ProfileItem], providers: [ProviderItem]) -> String {
        let profileFingerprint = profiles
            .map { "\($0.id.uuidString)|\($0.name)|\($0.isRemote)" }
            .sorted()
            .joined(separator: "\n")
        let providerFingerprint = providers
            .map { "\($0.id)|\($0.name)|\($0.kind)" }
            .sorted()
            .joined(separator: "\n")
        return "profiles:\n\(profileFingerprint)\nproviders:\n\(providerFingerprint)"
    }
}
