import Foundation

struct TimelineRoutingMix: Equatable {
    var directBytes: Int64
    var proxyBytes: Int64

    var directRatio: CGFloat {
        let total = directBytes + proxyBytes
        guard total > 0 else { return 0 }
        return CGFloat(directBytes) / CGFloat(total)
    }

    var proxyRatio: CGFloat {
        let total = directBytes + proxyBytes
        guard total > 0 else { return 1 }
        return CGFloat(proxyBytes) / CGFloat(total)
    }

    static func isDirect(policy: String) -> Bool {
        let normalized = policy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "direct" || normalized == "直连"
    }
}

struct OverviewTimelineBarItem: Identifiable, Equatable {
    var id: String
    var height: CGFloat
    var mix: TimelineRoutingMix
    var helpText: String
}

struct OverviewTimelineAxisLabel: Identifiable, Equatable {
    var id: String
    var date: Date
    var text: String
}

struct OverviewTimelineSnapshot: Equatable {
    var bars: [OverviewTimelineBarItem]
    var axisLabels: [OverviewTimelineAxisLabel]

    static let empty = OverviewTimelineSnapshot(bars: [], axisLabels: [])
}

enum OverviewTimelinePresentation {
    private static let leadingWindow: TimeInterval = 1
    private static let trailingWindow: TimeInterval = 1
    private static let maximumBarHeight: CGFloat = 104
    private static let minimumBarHeight: CGFloat = 8

    static func make(
        samples: [TrafficSample],
        policySamples: [PolicyTrafficSample],
        fallbackMix: TimelineRoutingMix,
        timeText: (Date) -> String
    ) -> OverviewTimelineSnapshot {
        guard let firstSample = samples.first, let lastSample = samples.last else {
            return .empty
        }

        let mixes = routingMixes(
            samples: samples,
            policySamples: policySamples,
            fallback: fallbackMix,
            lowerBound: firstSample.date.addingTimeInterval(-leadingWindow),
            upperBound: lastSample.date.addingTimeInterval(trailingWindow)
        )
        let maximumRate = max(samples.lazy.map { max($0.downloadRate, $0.uploadRate) }.max() ?? 1, 1)
        let bars = zip(samples, mixes).map { sample, mix in
            let rate = max(sample.downloadRate, sample.uploadRate)
            let height = max(minimumBarHeight, CGFloat(rate) / CGFloat(maximumRate) * maximumBarHeight)
            return OverviewTimelineBarItem(
                id: sample.id,
                height: height,
                mix: mix,
                helpText: "\(timeText(sample.date)) · 直连 \(Formatters.bytes(mix.directBytes)) · 代理 \(Formatters.bytes(mix.proxyBytes)) · ↓ \(Formatters.rate(sample.downloadRate)) · ↑ \(Formatters.rate(sample.uploadRate))"
            )
        }
        let labelIndices = Set([0, samples.count / 2, samples.count - 1]).sorted()
        let axisLabels = labelIndices.map { index in
            let sample = samples[index]
            return OverviewTimelineAxisLabel(
                id: sample.id,
                date: sample.date,
                text: timeText(sample.date)
            )
        }
        return OverviewTimelineSnapshot(bars: bars, axisLabels: axisLabels)
    }

    private static func routingMixes(
        samples: [TrafficSample],
        policySamples: [PolicyTrafficSample],
        fallback: TimelineRoutingMix,
        lowerBound: Date,
        upperBound: Date
    ) -> [TimelineRoutingMix] {
        var mixes = Array(
            repeating: TimelineRoutingMix(directBytes: 0, proxyBytes: 0),
            count: samples.count
        )
        let boundaries = zip(samples, samples.dropFirst()).map { previous, next in
            Date(timeIntervalSince1970: (
                previous.date.timeIntervalSince1970 + next.date.timeIntervalSince1970
            ) / 2)
        }

        var bucketIndex = 0
        var policyIndex = firstPolicySampleIndex(onOrAfter: lowerBound, in: policySamples)
        while policyIndex < policySamples.count {
            let sample = policySamples[policyIndex]
            guard sample.date < upperBound else { break }
            while bucketIndex < boundaries.count, sample.date >= boundaries[bucketIndex] {
                bucketIndex += 1
            }

            let bytes = sample.uploadBytes + sample.downloadBytes
            if TimelineRoutingMix.isDirect(policy: sample.policy) {
                mixes[bucketIndex].directBytes += bytes
            } else {
                mixes[bucketIndex].proxyBytes += bytes
            }
            policyIndex += 1
        }

        return mixes.map { mix in
            mix.directBytes + mix.proxyBytes > 0 ? mix : fallback
        }
    }

    private static func firstPolicySampleIndex(
        onOrAfter date: Date,
        in samples: [PolicyTrafficSample]
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].date < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}
