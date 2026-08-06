import Foundation

struct NodeProviderProfileSynchronization {
    var content: String
    var changes: [NodeProviderProfileChange]
}

struct NodeProviderPreservationResult {
    var content: String
    var preservedProviderNames: [String]
}

struct YAMLSection {
    var start: Int
    var end: Int
}

struct YAMLProviderBlock {
    var name: String
    var start: Int
    var end: Int
    var indent: Int
}
