import Combine
import Foundation

@MainActor
final class RuntimeActivityStore: ObservableObject {
    @Published private(set) var connections: [ConnectionItem] = []
    @Published private(set) var recentConnections: [ConnectionItem] = []
    @Published var uploadRate: Int64 = 0
    @Published var downloadRate: Int64 = 0
    @Published var trafficSamples: [TrafficSample] = []
    @Published private(set) var policyTrafficSamples: [PolicyTrafficSample] = []
    @Published var eventStreamStatus = "轮询"

    private var previousConnectionTraffic: [String: (upload: Int64, download: Int64)] = [:]
    private var lastTrafficSampleAppendAt = Date.distantPast
    private var lastConnectionsPublishAt = Date.distantPast

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
        if connections == items {
            return
        }

        recordPolicyTraffic(items)
        mergeRecentConnections(items)
        totalUploadBytes = items.reduce(Int64(0)) { $0 + $1.upload }
        totalDownloadBytes = items.reduce(Int64(0)) { $0 + $1.download }
        uniqueTargetCount = Set(items.map(\.host).filter { $0.isEmpty == false }).count
        directTrafficBytes = items.reduce(Int64(0)) { total, connection in
            let routing = "\(connection.rule) \(connection.chain)".lowercased()
            let isDirect = routing.contains("direct") || routing.contains("直连")
            return isDirect ? total + connection.download + connection.upload : total
        }

        // High-frequency stream frames often only change byte counters.
        // Keep totals fresh, but throttle full table publishes to cut AppKit/SwiftUI thrash.
        let structureChanged = connectionStructureChanged(from: connections, to: items)
        let now = Date()
        if structureChanged || now.timeIntervalSince(lastConnectionsPublishAt) >= 0.4 || connections.isEmpty {
            lastConnectionsPublishAt = now
            connections = items
        }
    }

    func connectionStructureChanged(from oldItems: [ConnectionItem], to newItems: [ConnectionItem]) -> Bool {
        if oldItems.count != newItems.count {
            return true
        }
        for index in oldItems.indices {
            let oldItem = oldItems[index]
            let newItem = newItems[index]
            if oldItem.id != newItem.id
                || oldItem.host != newItem.host
                || oldItem.process != newItem.process
                || oldItem.network != newItem.network
                || oldItem.rule != newItem.rule
                || oldItem.chain != newItem.chain
                || oldItem.sourceIP != newItem.sourceIP
                || oldItem.destinationIP != newItem.destinationIP
                || oldItem.destinationPort != newItem.destinationPort {
                return true
            }
        }
        return false
    }

    func updateTraffic(
        uploadRate nextUploadRate: Int64,
        downloadRate nextDownloadRate: Int64,
        sampleInterval: TimeInterval = 1.0,
        maxSamples: Int = 90
    ) {
        let rateChanged = uploadRate != nextUploadRate || downloadRate != nextDownloadRate
        if rateChanged {
            uploadRate = nextUploadRate
            downloadRate = nextDownloadRate
        }

        appendTrafficSampleIfNeeded(
            uploadRate: nextUploadRate,
            downloadRate: nextDownloadRate,
            sampleInterval: sampleInterval,
            maxSamples: maxSamples
        )
    }

    private func appendTrafficSampleIfNeeded(
        uploadRate nextUploadRate: Int64,
        downloadRate nextDownloadRate: Int64,
        sampleInterval: TimeInterval,
        maxSamples: Int
    ) {
        let now = Date()
        let idleQuiet =
            nextUploadRate == 0
            && nextDownloadRate == 0
            && connections.isEmpty
            && trafficSamples.last?.uploadRate == 0
            && trafficSamples.last?.downloadRate == 0
        if idleQuiet {
            return
        }

        if let last = trafficSamples.last,
           last.uploadRate == nextUploadRate,
           last.downloadRate == nextDownloadRate,
           now.timeIntervalSince(lastTrafficSampleAppendAt) < sampleInterval {
            return
        }

        lastTrafficSampleAppendAt = now
        var updatedSamples = trafficSamples
        updatedSamples.append(
            TrafficSample(
                date: now,
                uploadRate: nextUploadRate,
                downloadRate: nextDownloadRate
            )
        )
        if updatedSamples.count > maxSamples {
            updatedSamples.removeFirst(updatedSamples.count - maxSamples)
        }
        trafficSamples = updatedSamples
    }

    func clearRecentConnections() {
        recentConnections.removeAll()
    }

    func policyTrafficTotals(since date: Date) -> [PolicyTrafficTotals] {
        trafficTotals(since: date, key: \.policy)
    }

    func trafficTotals(
        since date: Date,
        key: KeyPath<PolicyTrafficSample, String>
    ) -> [PolicyTrafficTotals] {
        Dictionary(grouping: policyTrafficSamples.filter { $0.date >= date }) { sample in
            sample[keyPath: key]
        }
            .map { name, samples in
                PolicyTrafficTotals(
                    policy: name,
                    uploadBytes: samples.reduce(0) { $0 + $1.uploadBytes },
                    downloadBytes: samples.reduce(0) { $0 + $1.downloadBytes }
                )
            }
            .sorted { ($0.uploadBytes + $0.downloadBytes) > ($1.uploadBytes + $1.downloadBytes) }
    }

    private func mergeRecentConnections(_ items: [ConnectionItem]) {
        var merged = Dictionary(uniqueKeysWithValues: recentConnections.map { ($0.id, $0) })
        for item in items {
            merged[item.id] = item
        }
        recentConnections = merged.values
            .sorted { lhs, rhs in
                switch (lhs.start, rhs.start) {
                case let (lhs?, rhs?): return lhs > rhs
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
                }
            }
            .prefix(500)
            .map { $0 }
    }

    private func recordPolicyTraffic(_ items: [ConnectionItem], now: Date = Date()) {
        var samples = policyTrafficSamples
        var currentTraffic: [String: (upload: Int64, download: Int64)] = [:]

        for item in items {
            let identity = connectionTrafficIdentity(item)
            let previous = previousConnectionTraffic[identity]
            let uploadDelta = previous.map { max(0, item.upload - $0.upload) } ?? max(0, item.upload)
            let downloadDelta = previous.map { max(0, item.download - $0.download) } ?? max(0, item.download)
            currentTraffic[identity] = (item.upload, item.download)

            guard uploadDelta > 0 || downloadDelta > 0 else { continue }
            samples.append(PolicyTrafficSample(
                date: now,
                policy: policyName(for: item),
                process: item.processName,
                network: item.network.isEmpty ? "未知网络" : item.network.uppercased(),
                source: item.sourceIP.isEmpty ? "本机" : item.sourceIP,
                host: item.host.isEmpty ? item.remoteEndpoint : item.host,
                uploadBytes: uploadDelta,
                downloadBytes: downloadDelta
            ))
        }

        previousConnectionTraffic = currentTraffic
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        policyTrafficSamples = samples.filter { $0.date >= cutoff }
    }

    private func connectionTrafficIdentity(_ connection: ConnectionItem) -> String {
        if let start = connection.start {
            return "\(connection.id)@\(start.timeIntervalSince1970)"
        }
        return connection.id
    }

    private func policyName(for connection: ConnectionItem) -> String {
        let chain = connection.chain.components(separatedBy: " -> ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return chain.last ?? "DIRECT"
    }
}
