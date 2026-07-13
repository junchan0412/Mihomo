import SwiftUI

struct NetworkSecurityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default
    @State private var lastSavedSettings = AppSettings.default
    @State private var selectedSnapshotKind: NetworkSecuritySnapshotKind? = .systemProxy

    private var states: [NetworkTakeoverState] {
        store.networkTakeoverStates.isEmpty
            ? NetworkTakeoverKind.allCases.map { store.networkTakeoverState(for: $0) }
            : store.networkTakeoverStates
    }

    private var snapshots: [NetworkSecuritySnapshotItem] { store.networkSecuritySnapshotItems }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch store.networkWorkspaceTab {
                    case .overview: overviewPane
                    case .dns: dnsPane
                    case .domainSniffing:
                        DomainSniffingSettingsView(draft: $draft)
                            .environmentObject(store)
                    case .recovery: recoveryPane
                    }
                }
                .frame(maxWidth: 900, alignment: .topLeading)
                .padding(.horizontal, MihomoUI.pageHorizontalPadding)
                .padding(.vertical, MihomoUI.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("网络")
        .focusedSceneValue(
            \.workspaceCommands,
            WorkspaceCommandContext(refresh: { store.refreshNetworkTakeoverStates(force: true) })
        )
        .onAppear {
            synchronizeDraft(with: store.settings, force: true)
            store.refreshNetworkTakeoverStates()
        }
        .onReceive(store.$settings) { synchronizeDraft(with: $0, force: false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("网络").font(MihomoUI.Fonts.pageTitle)
                    Text("管理网络接管、DNS、域名嗅探与异常恢复。")
                        .font(MihomoUI.Fonts.pageSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(overallHealthTitle, systemImage: overallHealthIcon)
                    .foregroundStyle(overallHealthColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(overallHealthColor.opacity(0.12), in: Capsule())
            }

            HStack {
                Picker("网络分类", selection: $store.networkWorkspaceTab) {
                    ForEach(NetworkWorkspaceTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 680)
                Spacer()
                Button { store.refreshNetworkTakeoverStates(force: true) } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, 14)
    }

    private var overviewPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "接管方式",
                subtitle: "系统代理适合日常使用；需要透明接管更多应用时切换到 TUN。两者自动互斥，系统 DNS 可独立开启。",
                systemImage: "switch.2"
            ) {
                takeoverRow(
                    title: "系统代理",
                    subtitle: "适合大多数浏览器与遵循 macOS 代理设置的应用。",
                    icon: "network",
                    kind: .systemProxy,
                    isOn: systemProxyBinding
                )
                takeoverRow(
                    title: "TUN / 路由",
                    subtitle: "透明接管更广，但需要 Helper 权限和正确的恢复快照。",
                    icon: "point.3.connected.trianglepath.dotted",
                    kind: .tun,
                    isOn: tunBinding
                )
                takeoverRow(
                    title: "系统 DNS",
                    subtitle: "将 macOS DNS 临时切换为指定服务器；与运行时 DNS 不同。",
                    icon: "server.rack",
                    kind: .systemDNS,
                    isOn: systemDNSBinding
                )
            }

            SettingsSection(
                title: "流量识别",
                subtitle: "域名嗅探不改变接管范围，只从连接握手中补充域名信息。",
                systemImage: "viewfinder"
            ) {
                DomainSniffingSummaryCard {
                    store.networkWorkspaceTab = .domainSniffing
                }
                .environmentObject(store)
            }

            if let advisory = store.networkModeAdvisory {
                Label(advisory, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            SettingsSection(title: "使用建议", subtitle: "从最简单的模式开始，需要时再逐步增加接管范围。", systemImage: "lightbulb") {
                SettingsRow("常规使用") { Text("系统代理").foregroundStyle(.secondary) }
                SettingsRow("游戏 / 命令行 / 特殊应用") { Text("TUN / 路由").foregroundStyle(.secondary) }
                SettingsRow("需要固定 macOS DNS") { Text("系统 DNS；服务器在 DNS 标签中设置").foregroundStyle(.secondary) }
            }
        }
    }

    private var dnsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "运行时 DNS",
                subtitle: "当前配置中的 DNS 会先载入本页；应用修改后同步回当前配置，启用的覆写片段仍保持最高优先级。",
                systemImage: "shippingbox"
            ) {
                SettingsRow("Enhanced Mode") {
                    Picker("Enhanced Mode", selection: $draft.dnsEnhancedMode) {
                        Text("fake-ip").tag("fake-ip")
                        Text("redir-host").tag("redir-host")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                SettingsRow("Nameserver") {
                    TextField("逗号或换行分隔", text: listBinding(\.dnsNameservers))
                }
                SettingsRow("Fallback") {
                    TextField("可选", text: listBinding(\.dnsFallbacks))
                }
            }

            SettingsSection(
                title: "macOS 系统 DNS",
                subtitle: "开启后修改系统网络服务的 DNS，并创建独立快照用于恢复。",
                systemImage: "desktopcomputer"
            ) {
                SettingsToggleRow("核心运行时接管系统 DNS", isOn: $draft.autoSetSystemDNS)
                SettingsRow("DNS 服务器") {
                    TextField("1.1.1.1, 8.8.8.8", text: listBinding(\.systemDNSServers))
                }
                SettingsRow("当前状态") {
                    Text(state(for: .systemDNS).actualState).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(draft == store.settings ? "DNS 设置已应用" : "DNS 设置尚未应用")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { draft = store.settings }.disabled(draft == store.settings)
                Button("应用 DNS 设置") { Task { await store.saveSettings(draft) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == store.settings)
            }
        }
    }

    private var recoveryPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "恢复快照",
                subtitle: "每种接管模式使用独立快照，避免代理、DNS 与 TUN 状态互相覆盖。",
                systemImage: "externaldrive.badge.timemachine"
            ) {
                ForEach(snapshots) { snapshot in
                    Button {
                        selectedSnapshotKind = snapshot.kind
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: snapshot.kind.systemImage)
                                .foregroundStyle(healthColor(snapshot.health))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.kind.title).foregroundStyle(.primary)
                                Text(snapshot.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(snapshot.status).foregroundStyle(healthColor(snapshot.health))
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selected = snapshots.first(where: { $0.kind == selectedSnapshotKind }) ?? snapshots.first {
                SettingsSection(title: selected.kind.title, subtitle: selected.detail, systemImage: selected.kind.systemImage) {
                    SettingsRow("状态") { Text(selected.status).foregroundStyle(healthColor(selected.health)) }
                    SettingsRow("创建时间") { Text(selected.createdAt.map { Formatters.shortDate.string(from: $0) } ?? "-").foregroundStyle(.secondary) }
                    SettingsRow("文件") { Text(selected.path).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }

            SettingsSection(
                title: "自动恢复策略",
                subtitle: "这些偏好只影响网络接管退出和停止时的恢复行为。",
                systemImage: "arrow.uturn.backward.circle"
            ) {
                SettingsToggleRow("停止核心时恢复 TUN、DNS 与路由", isOn: $draft.restoreTunOnStop)
                SettingsToggleRow("退出应用时恢复系统代理", isOn: $draft.restoreSystemProxyOnQuit)
                SettingsRow("状态") {
                    Text(store.tunRecoveryStatus).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            NetworkRepairCenterView().environmentObject(store)

            HStack {
                Text(draft == store.settings ? "恢复策略已应用" : "恢复策略尚未应用")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { draft = store.settings }.disabled(draft == store.settings)
                Button("应用恢复策略") { Task { await store.saveSettings(draft) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == store.settings)
            }
        }
    }

    private func takeoverRow(title: String, subtitle: String, icon: String, kind: NetworkTakeoverKind, isOn: Binding<Bool>) -> some View {
        let item = state(for: kind)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(healthColor(item.health))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.actualState)
                    .font(.caption)
                    .foregroundStyle(healthColor(item.health))
                    .lineLimit(1)
            }
            Spacer(minLength: 20)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityValue(item.actualState)
                .accessibilityHint(subtitle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 58) }
    }

    private func state(for kind: NetworkTakeoverKind) -> NetworkTakeoverState {
        states.first(where: { $0.kind == kind }) ?? store.networkTakeoverState(for: kind)
    }

    private var systemProxyBinding: Binding<Bool> {
        Binding(get: { store.systemProxyEnabled }, set: { _ in Task { await store.toggleSystemProxy() } })
    }

    private var tunBinding: Binding<Bool> {
        Binding(get: { store.settings.tunEnabled }, set: { enabled in Task { await store.setTunEnabled(enabled) } })
    }

    private func synchronizeDraft(with settings: AppSettings, force: Bool) {
        if force || draft == lastSavedSettings {
            draft = settings
        }
        lastSavedSettings = settings
    }

    private var systemDNSBinding: Binding<Bool> {
        Binding(get: { store.settings.autoSetSystemDNS }, set: { enabled in
            var settings = store.settings
            settings.autoSetSystemDNS = enabled
            Task { await store.saveSettings(settings) }
        })
    }

    private func listBinding(_ keyPath: WritableKeyPath<AppSettings, [String]>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath].joined(separator: ", ") },
            set: { value in
                draft[keyPath: keyPath] = value.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
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

    private var overallHealthColor: Color { healthColor(store.networkSecurityOverallHealth) }
}

private func healthColor(_ health: NetworkTakeoverHealth) -> Color {
    switch health {
    case .ok: return .green
    case .warning: return .orange
    case .failed: return .red
    case .inactive: return .secondary
    }
}
