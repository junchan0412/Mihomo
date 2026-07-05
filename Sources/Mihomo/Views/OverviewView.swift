import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("概览")
                            .font(.largeTitle.bold())
                        Text(store.activeProfile?.name ?? "没有启用的配置")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("运行诊断") {
                        Task { await store.runDiagnostics() }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    StatusCard(title: "核心", value: store.coreStatus, systemImage: "cpu", isGood: store.isCoreRunning)
                    StatusCard(title: "Controller", value: store.coreVersion, systemImage: "point.3.connected.trianglepath.dotted", isGood: store.coreVersion != "未知")
                    StatusCard(title: "系统代理", value: store.systemProxyEnabled ? "已开启" : "已关闭", systemImage: "network", isGood: store.systemProxyEnabled)
                    StatusCard(title: "TUN", value: store.settings.tunEnabled ? "已写入配置" : "关闭", systemImage: "lock.shield", isGood: store.settings.tunEnabled)
                    StatusCard(title: "下载", value: Formatters.rate(store.downloadRate), systemImage: "arrow.down", isGood: true)
                    StatusCard(title: "上传", value: Formatters.rate(store.uploadRate), systemImage: "arrow.up", isGood: true)
                }

                GroupBox("快速操作") {
                    HStack {
                        Button(store.isCoreRunning ? "停止核心" : "启动核心") {
                            Task { await store.toggleCore() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("重启核心") {
                            Task { await store.restartCore() }
                        }

                        Button(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理") {
                            Task { await store.toggleSystemProxy() }
                        }

                        Button("刷新") {
                            Task { await store.refreshController() }
                        }

                        Button("轻量模式") {
                            store.enterLightweightMode()
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("实时流量") {
                    TrafficGraphView(samples: store.trafficSamples)
                        .frame(height: 160)
                }

                GroupBox("最近日志") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.logs.suffix(8)) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                Text(Formatters.logTime.string(from: entry.date))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)
                                Text(entry.level.uppercased())
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 62, alignment: .leading)
                                Text(entry.message)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if store.logs.isEmpty {
                            Text("暂无日志。")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("概览")
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let isGood: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3)
                    Spacer()
                    Circle()
                        .fill(isGood ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
