import Foundation

enum ActivityTrafficWindow: CaseIterable, Hashable {
    case today
    case fiveMinutes
    case fifteenMinutes
    case sixtyMinutes
    case sixHours
    case twelveHours

    func startDate(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .fiveMinutes: return now.addingTimeInterval(-5 * 60)
        case .fifteenMinutes: return now.addingTimeInterval(-15 * 60)
        case .sixtyMinutes: return now.addingTimeInterval(-60 * 60)
        case .sixHours: return now.addingTimeInterval(-6 * 60 * 60)
        case .twelveHours: return now.addingTimeInterval(-12 * 60 * 60)
        }
    }
}

struct ActivityTrafficValue: Hashable {
    var upload: Int64 = 0
    var download: Int64 = 0
    var total: Int64 { upload + download }

    mutating func add(upload: Int64, download: Int64) {
        self.upload += upload
        self.download += download
    }
}

struct ActivityTrafficRow: Identifiable, Hashable {
    var name: String
    var values: [ActivityTrafficWindow: ActivityTrafficValue]
    var id: String { name }

    func value(for window: ActivityTrafficWindow) -> ActivityTrafficValue {
        values[window] ?? ActivityTrafficValue()
    }

    func text(for window: ActivityTrafficWindow) -> String {
        let value = value(for: window)
        return "↑ \(Formatters.bytes(value.upload))  ↓ \(Formatters.bytes(value.download))"
    }
}

enum ActivityTrafficPresentation {
    static func rows(
        samples: [PolicyTrafficSample],
        grouping: ActivityTrafficGrouping,
        searchText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ActivityTrafficRow] {
        let windows = ActivityTrafficWindow.allCases.map { window in
            (window, window.startDate(now: now, calendar: calendar))
        }
        let earliestStartDate = windows.lazy.map(\.1).min() ?? now
        var totalsByName: [String: [ActivityTrafficWindow: ActivityTrafficValue]] = [:]

        let firstVisibleIndex = firstSampleIndex(onOrAfter: earliestStartDate, in: samples)
        for sample in samples[firstVisibleIndex...] {
            let name = sample[keyPath: grouping.sampleKeyPath]
            for (window, startDate) in windows where sample.date >= startDate {
                totalsByName[name, default: [:]][window, default: ActivityTrafficValue()].add(
                    upload: sample.uploadBytes,
                    download: sample.downloadBytes
                )
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return totalsByName.compactMap { name, values in
            guard query.isEmpty || name.localizedCaseInsensitiveContains(query) else { return nil }
            return ActivityTrafficRow(name: name, values: values)
        }
        .sorted { lhs, rhs in
            let lhsTotal = lhs.value(for: .today).total
            let rhsTotal = rhs.value(for: .today).total
            if lhsTotal == rhsTotal {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhsTotal > rhsTotal
        }
    }

    private static func firstSampleIndex(
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
