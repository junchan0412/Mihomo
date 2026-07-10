import Combine
import Foundation

@MainActor
final class RuntimeActivityStore: ObservableObject {
    @Published private(set) var connections: [ConnectionItem] = []
    @Published var uploadRate: Int64 = 0
    @Published var downloadRate: Int64 = 0
    @Published var trafficSamples: [TrafficSample] = []
    @Published var eventStreamStatus = "轮询"

    private(set) var totalUploadBytes: Int64 = 0
    private(set) var totalDownloadBytes: Int64 = 0
    private(set) var uniqueTargetCount = 0
    private(set) var directTrafficBytes: Int64 = 0

    var totalTrafficBytes: Int64 {
        totalUploadBytes + totalDownloadBytes
    }

    var proxyTrafficBytes: Int64 {
        max(0, totalTrafficBytes - directTrafficBytes)
    }

    func replaceConnections(_ items: [ConnectionItem]) {
        guard connections != items else { return }
        totalUploadBytes = items.reduce(Int64(0)) { $0 + $1.upload }
        totalDownloadBytes = items.reduce(Int64(0)) { $0 + $1.download }
        uniqueTargetCount = Set(items.map(\.host).filter { $0.isEmpty == false }).count
        directTrafficBytes = items.reduce(Int64(0)) { total, connection in
            let routing = "\(connection.rule) \(connection.chain)".lowercased()
            let isDirect = routing.contains("direct") || routing.contains("直连")
            return isDirect ? total + connection.download + connection.upload : total
        }
        connections = items
    }
}
