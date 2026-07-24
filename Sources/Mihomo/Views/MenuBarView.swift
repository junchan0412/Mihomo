import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var expandedGroupIDs: Set<String> = []
    @State private var isTestingDelays = false

    var body: some View {
        VStack(spacing: 0) {
            menuHeader

            Divider()

            delayTestBar

            Divider()

            policyGroupList

            Divider()

            quickControls
        }
        .frame(width: 380)
        .background(MihomoUI.pageBackground)
        .task {
            await store.preloadPolicyGroupIcons()
        }
    }

    private var menuHeader: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mihomo")
                    .font(.headline)
                Text(coreStateTitle)
                    .font(.caption)
                    .foregroundStyle(store.isCoreRunning ? .green : .secondary)
            }

            Spacer()

            Button {
                MainWindowPresenter.present(openWindow: openWindow)
            } label: {
                Image(systemName: "macwindow")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("显示主窗口")
            .accessibilityLabel("显示主窗口")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var delayTestBar: some View {
        HStack(spacing: 10) {
            Button {
                testAllDelays()
            } label: {
                Label(isTestingDelays ? "正在测速" : "延迟测试", systemImage: isTestingDelays ? "hourglass" : "speedometer")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.proxyGroups.isEmpty || isTestingDelays)

            VStack(alignment: .leading, spacing: 1) {
                Text("策略组与节点")
                    .font(.caption.weight(.semibold))
                Text(store.delayTestStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var policyGroupList: some View {
        Group {
            if store.proxyGroups.isEmpty {
                ContentUnavailableView("暂无策略组", systemImage: "switch.2")
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.proxyGroups) { group in
                            MenuBarPolicyGroupRow(
                                group: group,
                                image: store.policyGroupIconImages[group.id],
                                isExpanded: expandedBinding(for: group),
                                selectNode: { node in
                                    Task { await store.selectProxy(group: group.name, proxy: node.name) }
                                },
                                testGroup: {
                                    Task { await store.testGroupDelay(group) }
                                }
                            )

                            if group.id != store.proxyGroups.last?.id {
                                Divider()
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 440)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quickControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.toggleCore() }
            } label: {
                Image(systemName: store.isCoreRunning ? "stop.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .help(store.isCoreRunning ? "停止核心" : "启动核心")
            .accessibilityLabel(store.isCoreRunning ? "停止核心" : "启动核心")

            Button {
                Task { await store.toggleSystemProxy() }
            } label: {
                Image(systemName: "network")
                    .foregroundStyle(store.systemProxyEnabled ? .green : .primary)
                    .frame(width: 18, height: 18)
            }
            .help(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理")
            .accessibilityLabel(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理")
            .disabled(!store.isCoreRunning && !store.systemProxyEnabled)

            Button {
                Task { await store.setTunEnabled(!store.settings.tunEnabled) }
            } label: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(store.settings.tunEnabled ? .purple : .primary)
                    .frame(width: 18, height: 18)
            }
            .help(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN")
            .accessibilityLabel(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN")

            Spacer()

            Menu {
                Menu("出站模式") {
                    modeButton("规则", mode: "rule")
                    modeButton("全局", mode: "global")
                    modeButton("直连", mode: "direct")
                }

                Toggle("显示上传下载速率", isOn: $store.settings.showMenuBarTrafficRates)

                Divider()

                Button("重启核心") {
                    Task { await store.restartCore() }
                }

                Button("更新资源") {
                    Task { await store.updateAllExternalResources() }
                }

                Menu("切换配置") {
                    if store.profiles.isEmpty {
                        Text("暂无配置")
                    } else {
                        ForEach(store.profiles) { profile in
                            Button {
                                Task { await store.setActiveProfile(profile) }
                            } label: {
                                if profile.id == store.settings.activeProfileID {
                                    Label(Formatters.trimmedMenuText(profile.name, limit: 30), systemImage: "checkmark")
                                } else {
                                    Text(Formatters.trimmedMenuText(profile.name, limit: 30))
                                }
                            }
                        }
                    }
                }

                Menu("打开面板") {
                    sectionButton("概览", .overview)
                    sectionButton("策略", .policies)
                    sectionButton("配置", .profiles)
                    sectionButton("规则", .rules)
                    sectionButton("资源", .resources)
                    sectionButton("诊断", .diagnostics)
                    Button("连接") {
                        openWindow(id: "connections")
                    }
                }

                Divider()

                Button("检查更新...") {
                    openWindow(id: "software-update")
                    Task { await store.checkForSoftwareUpdate() }
                }

                Button("退出 Mihomo") {
                    Task {
                        await store.shutdown()
                        NSApp.terminate(nil)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 18, height: 18)
            }
            .help("更多操作")
            .accessibilityLabel("更多操作")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var coreStateTitle: String {
        store.isCoreRunning ? "核心运行中" : "核心已停止"
    }

    private func expandedBinding(for group: ProxyGroup) -> Binding<Bool> {
        Binding(
            get: { expandedGroupIDs.contains(group.id) },
            set: { expanded in
                if expanded {
                    expandedGroupIDs.insert(group.id)
                } else {
                    expandedGroupIDs.remove(group.id)
                }
            }
        )
    }

    private func testAllDelays() {
        isTestingDelays = true
        Task {
            await store.testAllProxyDelays()
            isTestingDelays = false
        }
    }

    private func modeButton(_ title: String, mode: String) -> some View {
        Button {
            Task { await store.setMode(mode) }
        } label: {
            if store.currentMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func sectionButton(_ title: String, _ section: AppSection) -> some View {
        Button(title) {
            store.selectedSection = section
            MainWindowPresenter.present(openWindow: openWindow)
        }
    }
}

private struct MenuBarPolicyGroupRow: View {
    var group: ProxyGroup
    var image: NSImage?
    @Binding var isExpanded: Bool
    var selectNode: (ProxyNode) -> Void
    var testGroup: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DisclosureGroup(isExpanded: $isExpanded) {
                LazyVStack(spacing: 2) {
                    ForEach(group.all) { node in
                        MenuBarProxyNodeRow(
                            node: node,
                            isCurrent: node.name == group.now,
                            select: { selectNode(node) }
                        )
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 2)
            } label: {
                HStack(spacing: 9) {
                    groupIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formatters.trimmedMenuText(group.name, limit: 28))
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(currentNodeTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    MenuBarDelayBadge(node: currentNode)
                }
                .padding(.vertical, 8)
            }

            Button(action: testGroup) {
                Image(systemName: "speedometer")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("测试 \(group.name) 的节点延迟")
            .accessibilityLabel("测试 \(group.name) 的节点延迟")
            .padding(.top, 7)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    private var currentNode: ProxyNode? {
        group.all.first { $0.name == group.now }
    }

    private var currentNodeTitle: String {
        let current = group.now.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? group.type : "\(current) · \(group.type)"
    }

    @ViewBuilder
    private var groupIcon: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: groupIconName)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }

    private var groupIconName: String {
        let type = group.type.lowercased()
        if type.contains("url") { return "speedometer" }
        if type.contains("fallback") { return "arrow.triangle.2.circlepath" }
        return "switch.2"
    }
}

private struct MenuBarProxyNodeRow: View {
    var node: ProxyNode
    var isCurrent: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.45))
                    .imageScale(.small)
                    .frame(width: 14)

                Text(Formatters.trimmedMenuText(node.name, limit: 34))
                    .font(.callout)
                    .lineLimit(1)

                Spacer(minLength: 8)

                MenuBarDelayBadge(node: node)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(node.name)
    }
}

private struct MenuBarDelayBadge: View {
    var node: ProxyNode?

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(minWidth: 44, alignment: .trailing)
            .accessibilityLabel("延迟")
            .accessibilityValue(title)
    }

    private var title: String {
        if node?.available == false { return "不可用" }
        guard let delay = node?.delay, delay > 0 else { return "未测试" }
        return "\(delay) ms"
    }

    private var color: Color {
        if node?.available == false { return .red }
        guard let delay = node?.delay, delay > 0 else { return .secondary }
        if delay < 150 { return .green }
        if delay < 350 { return .orange }
        return .red
    }
}
