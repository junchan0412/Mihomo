import SwiftUI

struct OverviewView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var activityStore: RuntimeActivityStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MihomoUI.sectionSpacing) {
                header
                summaryStrip
                mainDashboardGrid
                secondaryDashboardGrid
                trafficTimelinePanel
            }
            .padding(.horizontal, MihomoUI.pageHorizontalPadding)
            .padding(.vertical, MihomoUI.pageVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MihomoUI.pageBackground)
        .navigationTitle("概览")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(MihomoUI.Fonts.pageTitle)
            Text(store.activeProfile?.name ?? "没有启用的配置")
                .font(MihomoUI.Fonts.pageSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            OverviewSummaryMetric(title: "当前下载", value: totalDownloadText, systemImage: "arrow.down.circle", tint: .blue)
            OverviewDivider()
            OverviewSummaryMetric(title: "当前上传", value: totalUploadText, systemImage: "arrow.up.circle", tint: .red)
            OverviewDivider()
            OverviewSummaryMetric(title: "连接数", value: "\(activityStore.connections.count)", systemImage: "link", tint: .cyan)
            OverviewDivider()
            OverviewSummaryMetric(title: "访问目标", value: "\(uniqueTargetCount)", systemImage: "location.north.circle", tint: .purple)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            MihomoUI.cardFill,
            in: RoundedRectangle(cornerRadius: MihomoUI.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MihomoUI.cornerRadius, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var mainDashboardGrid: some View {
        HStack(alignment: .top, spacing: MihomoUI.cardSpacing) {
            OverviewPanel(title: "流量趋势", systemImage: "chart.line.uptrend.xyaxis", tint: .blue) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 36) {
                        TrafficRateLabel(title: "↓", value: Formatters.rate(activityStore.downloadRate), total: totalDownloadText, tint: .blue)
                        TrafficRateLabel(title: "↑", value: Formatters.rate(activityStore.uploadRate), total: totalUploadText, tint: .red)
                    }
                    TrafficGraphView(samples: activityStore.trafficSamples)
                        .frame(minHeight: 220)
                }
            }
            .frame(minHeight: 314)

            VStack(spacing: MihomoUI.cardSpacing) {
                OverviewSideStat(title: "活跃连接", value: "\(activityStore.connections.count)", detail: "当前会话", systemImage: "link", tint: .cyan)
                OverviewSideStat(title: "核心状态", value: store.coreStatus, detail: activityStore.eventStreamStatus, systemImage: "cpu", tint: .purple)
                OverviewSideStat(title: "出站模式", value: modeTitle(store.currentMode), detail: store.isCoreRunning ? "运行中" : "未运行", systemImage: "arrow.triangle.branch", tint: .red)
            }
            .frame(width: 318)
        }
    }

    private var secondaryDashboardGrid: some View {
        HStack(alignment: .top, spacing: MihomoUI.cardSpacing) {
            OverviewPanel(title: "流量分布", systemImage: "arrow.triangle.branch", tint: .indigo) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(totalTrafficText)
                        .font(MihomoUI.Fonts.metricLarge)
                    TrafficDistributionBar(directBytes: directTrafficBytes, proxyBytes: proxyTrafficBytes)
                    HStack(spacing: 22) {
                        DistributionLegend(title: "直连", value: Formatters.bytes(directTrafficBytes), tint: .cyan)
                        DistributionLegend(title: "代理", value: Formatters.bytes(proxyTrafficBytes), tint: .indigo)
                    }
                }
            }
            .frame(minHeight: 206)

            OverviewPanel(title: "策略组", systemImage: "square.grid.2x2", tint: .purple) {
                OverviewPolicyGroupsContent(groups: store.proxyGroups)
            }
            .frame(minHeight: 206)
        }
    }

    private var trafficTimelinePanel: some View {
        OverviewPanel(title: "流量时间轴", systemImage: "chart.bar", tint: .indigo) {
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(timelineBars) { bar in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(proxyRoutingColor)
                                .frame(height: bar.height * bar.mix.proxyRatio)
                            Rectangle()
                                .fill(directRoutingColor)
                                .frame(height: bar.height * bar.mix.directRatio)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .frame(maxWidth: .infinity)
                        .frame(height: bar.height, alignment: .bottom)
                        .help(bar.helpText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .bottomLeading)
                .drawingGroup(opaque: false)

                HStack {
                    ForEach(timelineAxisLabels, id: \.date) { label in
                        Text(label.text)
                        if label.date != timelineAxisLabels.last?.date { Spacer() }
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 168)
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode {
        case "global": return "全局"
        case "direct": return "直连"
        default: return "规则"
        }
    }

    private var directRoutingColor: Color {
        contrast == .increased ? .blue : .cyan.opacity(0.82)
    }

    private var proxyRoutingColor: Color {
        contrast == .increased ? .purple : .indigo.opacity(0.86)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "早上好，网络状态一目了然。"
        case 12..<18: return "下午好，保持连接稳定顺畅。"
        default: return "晚上好，随时掌握网络状态。"
        }
    }

    private var totalDownloadBytes: Int64 {
        activityStore.totalDownloadBytes
    }

    private var totalUploadBytes: Int64 {
        activityStore.totalUploadBytes
    }

    private var totalDownloadText: String {
        Formatters.bytes(totalDownloadBytes)
    }

    private var totalUploadText: String {
        Formatters.bytes(totalUploadBytes)
    }

    private var totalTrafficText: String {
        Formatters.bytes(totalDownloadBytes + totalUploadBytes)
    }

    private var uniqueTargetCount: Int {
        activityStore.uniqueTargetCount
    }

    private var directTrafficBytes: Int64 {
        activityStore.directTrafficBytes
    }

    private var proxyTrafficBytes: Int64 {
        activityStore.proxyTrafficBytes
    }

    private var timelineSamples: [TrafficSample] {
        Array(activityStore.trafficSamples.suffix(48))
    }

    private var timelineAxisLabels: [(date: Date, text: String)] {
        guard timelineSamples.isEmpty == false else { return [] }
        let indices = Set([0, timelineSamples.count / 2, timelineSamples.count - 1]).sorted()
        return indices.map { (timelineSamples[$0].date, Self.timelineTimeFormatter.string(from: timelineSamples[$0].date)) }
    }

    private var timelineBars: [TimelineBarItem] {
        let samples = timelineSamples
        guard samples.isEmpty == false else { return [] }

        let maxValue = max(samples.map { max($0.downloadRate, $0.uploadRate) }.max() ?? 1, 1)
        let policySamples = activityStore.policyTrafficSamples
        let fallbackMix = TimelineRoutingMix(directBytes: directTrafficBytes, proxyBytes: proxyTrafficBytes)

        return samples.enumerated().map { index, sample in
            let mix = timelineRoutingMix(
                samples: samples,
                policySamples: policySamples,
                index: index,
                fallback: fallbackMix
            )
            let height = max(8, CGFloat(max(sample.downloadRate, sample.uploadRate)) / CGFloat(maxValue) * 104)
            return TimelineBarItem(
                id: sample.id,
                height: height,
                mix: mix,
                helpText: "\(Self.timelineTimeFormatter.string(from: sample.date)) · 直连 \(Formatters.bytes(mix.directBytes)) · 代理 \(Formatters.bytes(mix.proxyBytes)) · ↓ \(Formatters.rate(sample.downloadRate)) · ↑ \(Formatters.rate(sample.uploadRate))"
            )
        }
    }

    private static let timelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func timelineRoutingMix(
        samples: [TrafficSample],
        policySamples: [PolicyTrafficSample],
        index: Int,
        fallback: TimelineRoutingMix
    ) -> TimelineRoutingMix {
        let sample = samples[index]
        let lowerBound: Date
        let upperBound: Date

        if index > 0 {
            lowerBound = Date(timeIntervalSince1970: (samples[index - 1].date.timeIntervalSince1970 + sample.date.timeIntervalSince1970) / 2)
        } else {
            lowerBound = sample.date.addingTimeInterval(-1)
        }
        if index + 1 < samples.count {
            upperBound = Date(timeIntervalSince1970: (sample.date.timeIntervalSince1970 + samples[index + 1].date.timeIntervalSince1970) / 2)
        } else {
            upperBound = sample.date.addingTimeInterval(1)
        }

        let bucket = policySamples.filter { $0.date >= lowerBound && $0.date < upperBound }
        let direct = bucket.filter { TimelineRoutingMix.isDirect(policy: $0.policy) }
            .reduce(Int64(0)) { $0 + $1.uploadBytes + $1.downloadBytes }
        let proxy = bucket.filter { TimelineRoutingMix.isDirect(policy: $0.policy) == false }
            .reduce(Int64(0)) { $0 + $1.uploadBytes + $1.downloadBytes }

        if direct + proxy > 0 {
            return TimelineRoutingMix(directBytes: direct, proxyBytes: proxy)
        }
        return fallback
    }
}

private struct OverviewPolicyGroupsContent: View {
    var groups: [ProxyGroup]
    @AppStorage("overview.policyGroupNames") private var storedNames = ""

    private var selectedNames: [String] {
        let available = Set(groups.map(\.name))
        let persisted = storedNames.components(separatedBy: "\u{1F}")
            .filter { $0.isEmpty == false && available.contains($0) }
        return persisted.isEmpty ? groups.prefix(4).map(\.name) : Array(persisted.prefix(4))
    }

    private var selectedGroups: [ProxyGroup] {
        let byName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) })
        return selectedNames.compactMap { byName[$0] }
    }

    var body: some View {
        if groups.isEmpty {
            Text("暂无数据")
                .font(MihomoUI.Fonts.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("显示 \(selectedGroups.count) 个策略组")
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(groups) { group in
                            Toggle(group.name, isOn: selectionBinding(for: group.name))
                                .disabled(selectedNames.contains(group.name) == false && selectedNames.count >= 4)
                        }
                        Divider()
                        Button("恢复默认") { storedNames = "" }
                    } label: {
                        Label("自定义", systemImage: "slider.horizontal.3")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                ForEach(selectedGroups) { group in
                    HStack {
                        Text(group.name).lineLimit(1)
                        Spacer()
                        Text(group.now.isEmpty ? "-" : group.now)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(MihomoUI.Fonts.bodyMedium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func selectionBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selectedNames.contains(name) },
            set: { enabled in
                var names = selectedNames
                if enabled, names.contains(name) == false, names.count < 4 {
                    names.append(name)
                } else if enabled == false {
                    names.removeAll { $0 == name }
                }
                storedNames = names.joined(separator: "\u{1F}")
            }
        )
    }
}

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

private struct TimelineBarItem: Identifiable {
    var id: String
    var height: CGFloat
    var mix: TimelineRoutingMix
    var helpText: String
}
