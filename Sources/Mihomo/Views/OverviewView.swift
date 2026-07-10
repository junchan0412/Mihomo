import SwiftUI

struct OverviewView: View {
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
                if store.proxyGroups.isEmpty {
                    Text("暂无数据")
                        .font(MihomoUI.Fonts.sectionTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 126, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.proxyGroups.prefix(4)) { group in
                            HStack {
                                Text(group.name)
                                    .lineLimit(1)
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
            .frame(minHeight: 206)
        }
    }

    private var trafficTimelinePanel: some View {
        OverviewPanel(title: "流量时间轴", systemImage: "chart.bar", tint: .indigo) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(timelineSamples.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.45))
                        .frame(height: timelineHeight(for: timelineSamples[index]))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 106, maxHeight: 106, alignment: .bottomLeading)
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
        Array(activityStore.trafficSamples.suffix(28))
    }

    private func timelineHeight(for sample: TrafficSample) -> CGFloat {
        let maxValue = max(timelineSamples.map { max($0.downloadRate, $0.uploadRate) }.max() ?? 1, 1)
        let value = max(sample.downloadRate, sample.uploadRate)
        return max(8, CGFloat(value) / CGFloat(maxValue) * 104)
    }
}
