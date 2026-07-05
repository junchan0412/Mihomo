import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                networkTakeoverSection
                quickOperationsSection
                runtimeSection
                recentLogsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("概览")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("概览")
                    .font(.largeTitle.bold())
                Text(store.activeProfile?.name ?? "没有启用的配置")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            quickActions
        }
    }

    private var networkTakeoverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("网络接管")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                TakeoverCard(
                    title: "系统代理",
                    subtitle: "将 HTTP / SOCKS 流量交给 mihomo mixed-port。",
                    status: store.systemProxyEnabled ? "已启用" : "未启用",
                    systemImage: "network",
                    tint: .blue,
                    isOn: systemProxyBinding
                )

                TakeoverCard(
                    title: "TUN 模式",
                    subtitle: "写入运行配置并通过 Helper 捕获 DNS 与路由回滚快照。",
                    status: store.settings.tunEnabled ? tunStatusText : "未启用",
                    systemImage: "lock.shield",
                    tint: .purple,
                    isOn: tunBinding
                )

                TakeoverCard(
                    title: "系统 DNS",
                    subtitle: "核心启动时临时设置 DNS，停止或退出时恢复。",
                    status: store.settings.autoSetSystemDNS ? "随核心启用" : "未启用",
                    systemImage: "globe",
                    tint: .green,
                    isOn: autoDNSBinding
                )
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("运行状态")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                OverviewMetricTile(title: "核心", value: store.coreStatus, systemImage: "cpu", state: store.isCoreRunning ? .ok : .idle)
                OverviewMetricTile(title: "Controller", value: store.coreVersion, systemImage: "point.3.connected.trianglepath.dotted", state: store.coreVersion == "未知" ? .warning : .ok)
                OverviewMetricTile(title: "出站模式", value: modeTitle(store.currentMode), systemImage: "arrow.triangle.branch", state: .ok)
                OverviewMetricTile(title: "活动连接", value: "\(store.connections.count)", systemImage: "link", state: store.connections.isEmpty ? .idle : .ok)
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.refreshController() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Button {
                Task { await store.runDiagnostics() }
            } label: {
                Label("运行诊断", systemImage: "stethoscope")
            }
        }
    }

    private var quickOperationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快速操作")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    Task { await store.toggleCore() }
                } label: {
                    Label(store.isCoreRunning ? "停止核心" : "启动核心", systemImage: store.isCoreRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await store.restartCore() }
                } label: {
                    Label("重启核心", systemImage: "arrow.clockwise")
                }

                Button {
                    Task { await store.toggleSystemProxy() }
                } label: {
                    Label(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理", systemImage: "network")
                }

                Button {
                    Task { await store.setTunEnabled(!store.settings.tunEnabled) }
                } label: {
                    Label(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN", systemImage: "lock.shield")
                }

                Button {
                    store.enterLightweightMode()
                } label: {
                    Label("轻量模式", systemImage: "menubar.rectangle")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recentLogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近日志")
                .font(.headline)
                .foregroundStyle(.secondary)
            RecentLogList(logs: Array(store.logs.suffix(10)))
        }
    }

    private var tunStatusText: String {
        store.isCoreRunning ? "已启用，运行中" : "已启用，下次启动生效"
    }

    private var systemProxyBinding: Binding<Bool> {
        Binding(
            get: { store.systemProxyEnabled },
            set: { _ in Task { await store.toggleSystemProxy() } }
        )
    }

    private var tunBinding: Binding<Bool> {
        Binding(
            get: { store.settings.tunEnabled },
            set: { enabled in Task { await store.setTunEnabled(enabled) } }
        )
    }

    private var autoDNSBinding: Binding<Bool> {
        Binding(
            get: { store.settings.autoSetSystemDNS },
            set: { enabled in
                var updated = store.settings
                updated.autoSetSystemDNS = enabled
                Task { await store.saveSettings(updated) }
            }
        )
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode {
        case "global": return "全局"
        case "direct": return "直连"
        default: return "规则"
        }
    }
}

private struct TakeoverCard: View {
    var title: String
    var subtitle: String
    var status: String
    var systemImage: String
    var tint: Color
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(status)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum MetricState {
    case ok
    case warning
    case idle

    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .idle: return .secondary
        }
    }
}

private struct OverviewMetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var state: MetricState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(state.color)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecentLogList: View {
    var logs: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if logs.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "terminal")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(logs) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Formatters.logTime.string(from: entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text(entry.level.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text(entry.message)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    Divider()
                }
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let isGood: Bool

    var body: some View {
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
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
