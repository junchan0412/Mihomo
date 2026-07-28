import SwiftUI

struct PolicyDelayHistoryPane: View {
    var entries: [PolicyDelayHistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("最近测速", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if entries.isEmpty {
                Text("尚无测速记录。运行一次延迟测试后会保留结果、失败原因和时间。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.proxyName)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(entry.outcomeTitle)
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(entry.delay == nil ? .orange : .green)
                        Text(Formatters.shortDate.string(from: entry.recordedAt))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

enum PolicyDelayFilter: String, CaseIterable, Identifiable {
    case all
    case untested
    case fast
    case moderate
    case slow
    case unavailable

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部延迟"
        case .untested: return "未测速"
        case .fast: return "快速 (<150 ms)"
        case .moderate: return "一般 (150-349 ms)"
        case .slow: return "较慢 (>=350 ms)"
        case .unavailable: return "不可用"
        }
    }

    func matches(_ node: ProxyNode) -> Bool {
        switch self {
        case .all: return true
        case .untested: return node.delay == nil || node.delay == 0
        case .fast: return node.delay.map { $0 > 0 && $0 < 150 } ?? false
        case .moderate: return node.delay.map { $0 >= 150 && $0 < 350 } ?? false
        case .slow: return node.delay.map { $0 >= 350 } ?? false
        case .unavailable: return node.available == false
        }
    }
}
