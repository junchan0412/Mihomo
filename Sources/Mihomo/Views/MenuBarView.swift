import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var expandedGroupIDs: Set<String> = []
    @State private var isTestingDelays = false
    @State private var nodeSearchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                menuHeader
                Divider()
                primaryActionRow
                Divider()
                outboundModeRow
                Divider()
                MenuBarSectionHeader(title: "策略组")
                delayTestBar
                policyGroupList
                if hasRecentSelections {
                    MenuBarSectionHeader(title: "进程与客户端")
                    recentSelectionPane
                }
                MenuBarSectionHeader(title: "功能")
                quickControls
                MenuBarSectionHeader(title: "面板")
                panelActions
            }
            .padding(.vertical, 6)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var primaryActionRow: some View {
        Button {
            MainWindowPresenter.present(openWindow: openWindow)
        } label: {
            MenuBarRowLabel(
                title: "显示主窗口",
                systemImage: "macwindow",
                detail: "⌘M"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("显示主窗口")
    }

    private var outboundModeRow: some View {
        Menu {
            modeButton("规则", mode: "rule")
            modeButton("全局", mode: "global")
            modeButton("直连", mode: "direct")
        } label: {
            MenuBarRowLabel(
                title: "出站模式",
                systemImage: "arrow.triangle.2.circlepath",
                tint: MenuBarPresentation.modeTint(for: store.currentMode),
                detail: MenuBarPresentation.modeTitle(for: store.currentMode),
                rightBadge: MenuBarPresentation.modeLetter(for: store.currentMode),
                showChevron: true
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var delayTestBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                testAllDelays()
            } label: {
                MenuBarRowLabel(
                    title: isTestingDelays ? "正在测速" : "延迟测试",
                    systemImage: isTestingDelays ? "hourglass" : "speedometer",
                    detail: store.delayTestStatus
                )
            }
            .buttonStyle(.plain)
            .disabled(store.proxyGroups.isEmpty || isTestingDelays)

            TextField("搜索节点或策略组", text: $nodeSearchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 14)
        }
        .padding(.vertical, 4)
    }

    private var policyGroupList: some View {
        Group {
            if store.proxyGroups.isEmpty {
                ContentUnavailableView("暂无策略组", systemImage: "switch.2")
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleGroups) { group in
                            MenuBarPolicyGroupRow(
                                group: group,
                                image: store.policyGroupIconImages[group.id],
                                searchText: nodeSearchText,
                                isExpanded: expandedBinding(for: group),
                                isFavorite: store.favoritePolicyGroupNames.contains(group.name),
                                selectNode: { node in
                                    Task { await store.selectProxy(group: group.name, proxy: node.name) }
                                },
                                testGroup: {
                                    Task { await store.testGroupDelay(group) }
                                },
                                toggleFavorite: {
                                    store.toggleFavoritePolicyGroup(group.name)
                                }
                            )

                            if group.id != visibleGroups.last?.id {
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
        VStack(spacing: 0) {
            Button {
                Task { await store.toggleCore() }
            } label: {
                MenuBarRowLabel(
                    title: store.isCoreRunning ? "停止核心" : "启动核心",
                    systemImage: store.isCoreRunning ? "stop.fill" : "play.fill",
                    detail: coreStateTitle
                )
            }
            .buttonStyle(.plain)
            .help(store.isCoreRunning ? "停止核心" : "启动核心")
            .accessibilityLabel(store.isCoreRunning ? "停止核心" : "启动核心")

            Button {
                Task { await store.toggleSystemProxy() }
            } label: {
                MenuBarRowLabel(
                    title: "系统代理",
                    systemImage: "network",
                    tint: store.systemProxyEnabled ? .green : .primary,
                    detail: store.systemProxyEnabled ? "已开启" : "未开启"
                )
            }
            .buttonStyle(.plain)
            .help(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理")
            .accessibilityLabel(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理")
            .disabled(!store.isCoreRunning && !store.systemProxyEnabled)

            Button {
                Task { await store.setTunEnabled(!store.settings.tunEnabled) }
            } label: {
                MenuBarRowLabel(
                    title: "TUN",
                    systemImage: "lock.shield",
                    tint: store.settings.tunEnabled ? .purple : .primary,
                    detail: store.settings.tunEnabled ? "已开启" : "未开启"
                )
            }
            .buttonStyle(.plain)
            .help(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN")
            .accessibilityLabel(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN")

            Toggle(isOn: menuBarTrafficRatesBinding) {
                MenuBarRowLabel(
                    title: "显示上传下载速率",
                    systemImage: "chart.line.uptrend.xyaxis",
                    detail: store.settings.showMenuBarTrafficRates ? "已开启" : "已关闭"
                )
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private var menuBarTrafficRatesBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showMenuBarTrafficRates },
            set: { enabled in
                var updated = store.settings
                updated.showMenuBarTrafficRates = enabled
                Task { await store.saveSettings(updated) }
            }
        )
    }

    private var panelActions: some View {
        VStack(spacing: 0) {
            Menu {
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
            } label: {
                MenuBarRowLabel(
                    title: "切换配置",
                    systemImage: "doc.on.doc",
                    detail: store.activeProfile?.name ?? "未选择",
                    showChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Button {
                Task { await store.restartCore() }
            } label: {
                MenuBarRowLabel(title: "重启核心", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Button {
                Task { await store.updateAllExternalResources() }
            } label: {
                MenuBarRowLabel(title: "更新资源", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "software-update")
                store.startSoftwareUpdateCheck()
            } label: {
                MenuBarRowLabel(title: "检查更新", systemImage: "square.and.arrow.down", detail: "⌘U")
            }
            .buttonStyle(.plain)

            Menu {
                sectionButton("概览", .overview)
                sectionButton("策略", .policies)
                sectionButton("配置", .profiles)
                sectionButton("规则", .rules)
                sectionButton("资源", .resources)
                sectionButton("诊断", .diagnostics)
                Button("连接") {
                    openWindow(id: "connections")
                }
            } label: {
                MenuBarRowLabel(
                    title: "打开面板",
                    systemImage: "macwindow",
                    showChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Button(role: .destructive) {
                Task {
                    await store.shutdown()
                    NSApp.terminate(nil)
                }
            } label: {
                MenuBarRowLabel(title: "退出 Mihomo", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
    }

    private var coreStateTitle: String {
        store.isCoreRunning ? "核心运行中" : "核心已停止"
    }

    private var visibleGroups: [ProxyGroup] {
        let query = nodeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? store.proxyGroups : store.proxyGroups.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.now.localizedCaseInsensitiveContains(query)
                || $0.all.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return filtered.sorted { lhs, rhs in
            let lhsFavorite = store.favoritePolicyGroupNames.contains(lhs.name)
            let rhsFavorite = store.favoritePolicyGroupNames.contains(rhs.name)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var hasRecentSelections: Bool {
        store.recentProxySelections.contains { selection in
            guard let group = store.proxyGroups.first(where: { $0.name == selection.groupName }) else {
                return false
            }
            return group.all.contains { $0.name == selection.proxyName }
        }
    }

    private var recentSelectionPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近切换")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            ForEach(store.recentProxySelections) { selection in
                if let group = store.proxyGroups.first(where: { $0.name == selection.groupName }),
                   let node = group.all.first(where: { $0.name == selection.proxyName }) {
                    Button {
                        Task { await store.selectProxy(group: group.name, proxy: node.name) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: node.name == group.now ? "checkmark.circle.fill" : "arrow.turn.down.right")
                                .foregroundStyle(node.name == group.now ? Color.accentColor : Color.secondary)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Formatters.trimmedMenuText(node.name, limit: 28))
                                    .lineLimit(1)
                                Text(group.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            MenuBarDelayBadge(node: node)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
