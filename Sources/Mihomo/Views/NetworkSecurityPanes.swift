import SwiftUI

struct NetworkSecurityOverviewPane: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "接管方式",
                subtitle: "系统代理服务遵守 macOS 代理设置的应用；TUN 负责不遵守系统代理的透明流量。两者可以同时开启，分别处理不同流量范围。",
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

    private var states: [NetworkTakeoverState] {
        store.networkTakeoverStates.isEmpty
            ? NetworkTakeoverKind.allCases.map { store.networkTakeoverState(for: $0) }
            : store.networkTakeoverStates
    }

    private func state(for kind: NetworkTakeoverKind) -> NetworkTakeoverState {
        states.first(where: { $0.kind == kind }) ?? store.networkTakeoverState(for: kind)
    }

    private func takeoverRow(
        title: String,
        subtitle: String,
        icon: String,
        kind: NetworkTakeoverKind,
        isOn: Binding<Bool>
    ) -> some View {
        let item = state(for: kind)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(NetworkHealthPresentation.color(for: item.health))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.actualState)
                    .font(.caption)
                    .foregroundStyle(NetworkHealthPresentation.color(for: item.health))
                    .lineLimit(1)
            }
            Spacer(minLength: 20)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(store.isNetworkOperationRunning(kind))
                .accessibilityLabel(title)
                .accessibilityValue(item.actualState)
                .accessibilityHint(subtitle)
        }
        .overlay(alignment: .bottomLeading) {
            if let message = store.networkOperationMessages[kind], message.isEmpty == false {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 58)
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 58) }
    }

    private var systemProxyBinding: Binding<Bool> {
        Binding(get: { store.systemProxyEnabled }, set: { _ in Task { await store.toggleSystemProxy() } })
    }

    private var tunBinding: Binding<Bool> {
        Binding(get: { store.settings.tunEnabled }, set: { enabled in Task { await store.setTunEnabled(enabled) } })
    }

    private var systemDNSBinding: Binding<Bool> {
        Binding(get: { store.settings.autoSetSystemDNS }, set: { enabled in
            var settings = store.settings
            settings.autoSetSystemDNS = enabled
            Task { await store.saveSettings(settings) }
        })
    }
}

struct NetworkSecurityDNSPane: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "运行时 DNS",
                subtitle: "由 Mihomo 内置 DNS 解析请求。TUN 开启时会自动启用，并通过 dns-hijack 接管 53 端口流量；Fake-IP 将 IP 连接重新关联到域名。",
                systemImage: "shippingbox"
            ) {
                SettingsToggleRow("启用 Mihomo DNS", isOn: $draft.dnsEnabled)
                    .disabled(draft.tunEnabled)
                SettingsRow("Enhanced Mode") {
                    Picker("Enhanced Mode", selection: $draft.dnsEnhancedMode) {
                        Text("fake-ip").tag("fake-ip")
                        Text("redir-host").tag("redir-host")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                SettingsRow("Nameserver", validationMessage: AppSettingsValidation.issue(for: .dnsNameservers, in: draft)) {
                    TextField("逗号或换行分隔", text: listBinding(\.dnsNameservers))
                }
                SettingsRow("Fallback", validationMessage: AppSettingsValidation.issue(for: .dnsFallbacks, in: draft)) {
                    TextField("可选", text: listBinding(\.dnsFallbacks))
                }
            }

            SettingsSection(
                title: "macOS DNS 兼容模式",
                subtitle: "仅为无法使用 TUN DNS Hijacking 的特殊网络改写系统 DNS。通常无需开启；该操作会创建独立快照用于恢复。",
                systemImage: "desktopcomputer"
            ) {
                SettingsToggleRow("改写 macOS 系统 DNS", isOn: $draft.autoSetSystemDNS)
                SettingsRow("DNS 服务器", validationMessage: AppSettingsValidation.issue(for: .systemDNSServers, in: draft)) {
                    TextField("1.1.1.1, 8.8.8.8", text: listBinding(\.systemDNSServers))
                }
                SettingsRow("当前状态") {
                    Text(store.networkTakeoverState(for: .systemDNS).actualState).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(draft == store.settings ? "DNS 设置已应用" : "DNS 设置尚未应用")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { draft = store.settings }.disabled(draft == store.settings)
                Button("应用 DNS 设置") { Task { await store.saveSettings(draft) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == store.settings || validationIssues.isEmpty == false)
            }
        }
    }

    private var validationIssues: [AppSettingsValidation.Issue] {
        AppSettingsValidation.validate(draft).filter {
            [.dnsNameservers, .dnsFallbacks, .systemDNSServers].contains($0.field)
        }
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
}

struct NetworkSecurityRecoveryPane: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings
    @Binding var selectedSnapshotKind: NetworkSecuritySnapshotKind?

    private var snapshots: [NetworkSecuritySnapshotItem] {
        store.networkSecuritySnapshotItems
    }

    var body: some View {
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
                                .foregroundStyle(NetworkHealthPresentation.color(for: snapshot.health))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.kind.title).foregroundStyle(.primary)
                                Text(snapshot.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(snapshot.status).foregroundStyle(NetworkHealthPresentation.color(for: snapshot.health))
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
                    SettingsRow("状态") { Text(selected.status).foregroundStyle(NetworkHealthPresentation.color(for: selected.health)) }
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
                SettingsToggleRow("系统代理被外部修改时自动恢复", isOn: $draft.systemProxyGuardEnabled)
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
}
