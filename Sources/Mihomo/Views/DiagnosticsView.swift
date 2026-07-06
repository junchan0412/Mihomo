import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("诊断")
                        .font(.largeTitle.bold())
                    Text("检查核心、运行配置、系统代理快照、TUN 状态、Controller 和日志。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("运行诊断") {
                    Task { await store.runDiagnostics() }
                }
                .buttonStyle(.borderedProminent)

                Button("修复系统代理") {
                    Task { await store.repairSystemProxy() }
                }

                Button("恢复 DNS") {
                    Task { await store.restoreSystemDNS() }
                }

                Button("修复 Helper") {
                    Task { await store.repairHelperRegistration() }
                }

                Button("验证 TUN 权限") {
                    Task { await store.verifyTunPrivileges() }
                }

                Button("回滚 TUN") {
                    Task { await store.restoreTunRecovery() }
                }
            }

            NetworkRepairCenterView()

            List(store.diagnostics) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: item.state))
                        .foregroundStyle(color(for: item.state))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.detail)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if item.title == "系统代理快照", item.state == .warning {
                            Button {
                                Task { await store.repairSystemProxy() }
                            } label: {
                                Label("恢复代理快照", systemImage: "wrench.and.screwdriver")
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
                        if item.title == "XPC Helper", item.state != .ok {
                            Button {
                                Task { await store.repairHelperRegistration() }
                            } label: {
                                Label("重建 Helper 注册", systemImage: "hammer")
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            .overlay {
                if store.diagnostics.isEmpty {
                    ContentUnavailableView("尚未运行诊断", systemImage: "stethoscope", description: Text("运行诊断以验证第三个 MVP 的运行状态。"))
                }
            }
        }
        .padding(24)
        .navigationTitle("诊断")
    }

    private func icon(for state: DiagnosticState) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for state: DiagnosticState) -> Color {
        switch state {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}

private struct NetworkRepairCenterView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("网络修复中心", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
                Spacer()
                Button {
                    store.refreshNetworkTakeoverStates()
                } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(store.networkTakeoverStates) { state in
                    NetworkRepairStateCard(state: state)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.repairSystemProxy() }
                } label: {
                    Label("恢复代理", systemImage: "network.badge.shield.half.filled")
                }

                Button {
                    Task { await store.restoreSystemDNS() }
                } label: {
                    Label("恢复 DNS", systemImage: "globe.badge.chevron.backward")
                }

                Button {
                    Task { await store.restoreTunRecovery() }
                } label: {
                    Label("恢复 TUN 路由", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    store.clearNetworkRecoverySnapshots()
                } label: {
                    Label("清理快照", systemImage: "trash")
                }

                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NetworkRepairStateCard: View {
    var state: NetworkTakeoverState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: state.kind.systemImage)
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(state.kind.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }

            Text(state.desiredState)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(state.actualState)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Text(state.recoveryAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(.background.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch state.health {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        case .inactive: return .secondary
        }
    }
}
