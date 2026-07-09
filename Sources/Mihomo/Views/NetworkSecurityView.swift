import AppKit
import SwiftUI

struct NetworkSecurityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTakeoverKind: NetworkTakeoverKind? = .systemProxy
    @State private var selectedSnapshotKind: NetworkSecuritySnapshotKind? = .systemProxy

    private var states: [NetworkTakeoverState] {
        let current = store.networkTakeoverStates
        guard current.isEmpty else { return current }
        return NetworkTakeoverKind.allCases.map { store.networkTakeoverState(for: $0) }
    }

    private var snapshots: [NetworkSecuritySnapshotItem] {
        store.networkSecuritySnapshotItems
    }

    private var selectedState: NetworkTakeoverState? {
        guard let selectedTakeoverKind else { return states.first }
        return states.first { $0.kind == selectedTakeoverKind } ?? states.first
    }

    private var selectedSnapshot: NetworkSecuritySnapshotItem? {
        guard let selectedSnapshotKind else { return snapshots.first }
        return snapshots.first { $0.kind == selectedSnapshotKind } ?? snapshots.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                takeoverControls
                HStack(alignment: .top, spacing: 14) {
                    takeoverPanel
                    snapshotPanel
                }
                NetworkRepairCenterView()
                    .environmentObject(store)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("网络安全")
        .onAppear {
            ensureSelection()
            store.refreshNetworkTakeoverStates()
        }
        .onChange(of: store.networkTakeoverStates) {
            ensureSelection()
        }
        .onChange(of: store.lastSystemProxySnapshot) {
            ensureSelection()
        }
        .onChange(of: store.lastSystemDNSSnapshot) {
            ensureSelection()
        }
        .onChange(of: store.lastTunRecoverySnapshot) {
            ensureSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("网络安全")
                    .font(.largeTitle.bold())
                Text("集中管理系统代理、系统 DNS、TUN 路由、恢复快照和修复动作。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Label(overallHealthTitle, systemImage: overallHealthIcon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(overallHealthColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(overallHealthColor.opacity(0.12), in: Capsule())

                HStack(spacing: 8) {
                    Button {
                        store.refreshNetworkTakeoverStates(force: true)
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task { await store.runDiagnostics() }
                    } label: {
                        Label("诊断", systemImage: "stethoscope")
                    }

                    Button {
                        store.exportDiagnosticBundle()
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var takeoverControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("接管模式", systemImage: "switch.2")
                    .font(.headline)
                Spacer()
                if let advisory = store.networkModeAdvisory {
                    Label(advisory, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 18) {
                Toggle("系统代理", isOn: systemProxyBinding)
                    .toggleStyle(.switch)
                Toggle("TUN / 路由", isOn: tunBinding)
                    .toggleStyle(.switch)
                Toggle("系统 DNS", isOn: autoDNSBinding)
                    .toggleStyle(.switch)
                Spacer()
                Text("系统代理与 TUN 会自动互斥；DNS 快照、代理快照和 TUN 快照互不混用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .font(.callout)
        .padding(12)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }

    private var takeoverPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("接管状态")
                    .font(.headline)
                Spacer()
                Text("\(states.count) 项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AppKitTable(
                rows: states,
                selection: $selectedTakeoverKind,
                columns: [
                    .init(title: "类型", width: 110) { $0.kind.title },
                    .init(title: "实际状态", width: 220, textColor: takeoverTextColor) { $0.actualState },
                    .init(title: "恢复动作", width: 170) { $0.recoveryAction }
                ],
                hasHorizontalScroller: false
            )
            .frame(height: 142)

            if let selectedState {
                NetworkSecurityDetailBlock(
                    title: selectedState.kind.title,
                    systemImage: selectedState.kind.systemImage,
                    health: selectedState.health,
                    rows: [
                        ("期望", selectedState.desiredState),
                        ("实际", selectedState.actualState),
                        ("最近操作", selectedState.lastOperation),
                        ("修复动作", selectedState.recoveryAction)
                    ]
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var snapshotPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("快照边界")
                    .font(.headline)
                Spacer()
                Text(snapshotSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AppKitTable(
                rows: snapshots,
                selection: $selectedSnapshotKind,
                columns: [
                    .init(title: "快照", width: 120) { $0.kind.title },
                    .init(title: "状态", width: 170, textColor: snapshotTextColor) { $0.status },
                    .init(title: "路径", width: 280) { $0.path }
                ],
                hasHorizontalScroller: true
            )
            .frame(height: 142)

            if let selectedSnapshot {
                NetworkSecurityDetailBlock(
                    title: selectedSnapshot.kind.title,
                    systemImage: selectedSnapshot.kind.systemImage,
                    health: selectedSnapshot.health,
                    rows: [
                        ("状态", selectedSnapshot.status),
                        ("创建", selectedSnapshot.createdAt.map { Formatters.shortDate.string(from: $0) } ?? "-"),
                        ("边界", selectedSnapshot.detail),
                        ("文件", selectedSnapshot.path)
                    ]
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var snapshotSummary: String {
        let active = snapshots.filter { $0.createdAt != nil }.count
        return "\(active)/\(snapshots.count) 个待恢复"
    }

    private var overallHealthTitle: String {
        switch store.networkSecurityOverallHealth {
        case .ok: return "接管正常"
        case .warning: return "需要关注"
        case .failed: return "存在故障"
        case .inactive: return "未接管"
        }
    }

    private var overallHealthIcon: String {
        switch store.networkSecurityOverallHealth {
        case .ok: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .inactive: return "shield"
        }
    }

    private var overallHealthColor: Color {
        healthColor(store.networkSecurityOverallHealth)
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

    private func ensureSelection() {
        if selectedTakeoverKind == nil || states.contains(where: { $0.kind == selectedTakeoverKind }) == false {
            selectedTakeoverKind = states.first?.kind
        }
        if selectedSnapshotKind == nil || snapshots.contains(where: { $0.kind == selectedSnapshotKind }) == false {
            selectedSnapshotKind = snapshots.first?.kind
        }
    }

    private func takeoverTextColor(_ state: NetworkTakeoverState) -> NSColor? {
        nsColor(state.health)
    }

    private func snapshotTextColor(_ item: NetworkSecuritySnapshotItem) -> NSColor? {
        nsColor(item.health)
    }

    private func nsColor(_ health: NetworkTakeoverHealth) -> NSColor? {
        switch health {
        case .ok:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .failed:
            return .systemRed
        case .inactive:
            return .secondaryLabelColor
        }
    }
}

private struct NetworkSecurityDetailBlock: View {
    var title: String
    var systemImage: String
    var health: NetworkTakeoverHealth
    var rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(healthColor(health))
                    .frame(width: 18)
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
            }

            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    Text(row.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
    }
}

private func healthColor(_ health: NetworkTakeoverHealth) -> Color {
    switch health {
    case .ok: return .green
    case .warning: return .orange
    case .failed: return .red
    case .inactive: return .secondary
    }
}
