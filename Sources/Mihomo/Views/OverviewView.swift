import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryStrip
                mainDashboardGrid
                secondaryDashboardGrid
                trafficTimelinePanel
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("概览")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("晨光微熹，开启新篇！")
                .font(.title2.weight(.bold))
            Text(store.activeProfile?.name ?? "没有启用的配置")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            OverviewSummaryMetric(title: "总下载", value: totalDownloadText, systemImage: "arrow.down.circle", tint: .blue)
            OverviewDivider()
            OverviewSummaryMetric(title: "总上传", value: totalUploadText, systemImage: "arrow.up.circle", tint: .red)
            OverviewDivider()
            OverviewSummaryMetric(title: "连接数", value: "\(store.connections.count)", systemImage: "link", tint: .cyan)
            OverviewDivider()
            OverviewSummaryMetric(title: "访问目标", value: "\(uniqueTargetCount)", systemImage: "location.north.circle", tint: .purple)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var mainDashboardGrid: some View {
        HStack(alignment: .top, spacing: 18) {
            OverviewPanel(title: "流量趋势", systemImage: "chart.line.uptrend.xyaxis", tint: .blue) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 44) {
                        TrafficRateLabel(title: "↓", value: Formatters.rate(store.downloadRate), total: totalDownloadText, tint: .blue)
                        TrafficRateLabel(title: "↑", value: Formatters.rate(store.uploadRate), total: totalUploadText, tint: .red)
                    }
                    TrafficGraphView(samples: store.trafficSamples)
                        .frame(minHeight: 230)
                }
            }
            .frame(minHeight: 332)

            VStack(spacing: 18) {
                OverviewSideStat(title: "活跃连接", value: "\(store.connections.count)", detail: "已关闭 0", systemImage: "link", tint: .cyan)
                OverviewSideStat(title: "核心状态", value: store.coreStatus, detail: store.controllerEventStreamStatus, systemImage: "cpu", tint: .purple)
                OverviewSideStat(title: "出站模式", value: modeTitle(store.currentMode), detail: store.isCoreRunning ? "运行中" : "未运行", systemImage: "arrow.triangle.branch", tint: .red)
            }
            .frame(width: 330)
        }
    }

    private var secondaryDashboardGrid: some View {
        HStack(alignment: .top, spacing: 18) {
            OverviewPanel(title: "流量分布", systemImage: "arrow.triangle.branch", tint: .indigo) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(totalTrafficText)
                        .font(.title.weight(.bold))
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
                        .font(.headline)
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
                            .font(.callout.weight(.medium))
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
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .bottomLeading)
        }
        .frame(minHeight: 186)
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode {
        case "global": return "全局"
        case "direct": return "直连"
        default: return "规则"
        }
    }

    private var totalDownloadBytes: Int64 {
        store.connections.reduce(Int64(0)) { $0 + $1.download }
    }

    private var totalUploadBytes: Int64 {
        store.connections.reduce(Int64(0)) { $0 + $1.upload }
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
        Set(store.connections.map(\.host).filter { !$0.isEmpty }).count
    }

    private var directTrafficBytes: Int64 {
        trafficBytes { connection in
            let text = "\(connection.rule) \(connection.chain)".lowercased()
            return text.contains("direct") || text.contains("直连")
        }
    }

    private var proxyTrafficBytes: Int64 {
        max(0, totalDownloadBytes + totalUploadBytes - directTrafficBytes)
    }

    private var timelineSamples: [TrafficSample] {
        Array(store.trafficSamples.suffix(28))
    }

    private func trafficBytes(where predicate: (ConnectionItem) -> Bool) -> Int64 {
        store.connections.reduce(Int64(0)) { total, connection in
            predicate(connection) ? total + connection.download + connection.upload : total
        }
    }

    private func timelineHeight(for sample: TrafficSample) -> CGFloat {
        let maxValue = max(timelineSamples.map { max($0.downloadRate, $0.uploadRate) }.max() ?? 1, 1)
        let value = max(sample.downloadRate, sample.uploadRate)
        return max(8, CGFloat(value) / CGFloat(maxValue) * 104)
    }
}
