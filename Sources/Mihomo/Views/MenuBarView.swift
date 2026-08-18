import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var isTestingDelays = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MenuBarStatusHeader(
                    mode: store.currentMode,
                    isRunning: store.isCoreRunning,
                    title: store.menuBarTitle,
                    uploadRate: Formatters.rate(store.activityStore.uploadRate),
                    downloadRate: Formatters.rate(store.activityStore.downloadRate)
                )
                primaryAction
                Divider().padding(.leading, 14)
                outboundModeMenu
                Divider().padding(.leading, 14)
                policyMenus
                Divider().padding(.leading, 14)
                maintenanceMenus
                Divider().padding(.leading, 14)
                managementMenus
                Divider().padding(.leading, 14)
                Button(role: .destructive, action: quit) {
                    MenuBarRowLabel(title: "退出 Mihomo", systemImage: "power")
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 332, height: 648)
        .scrollIndicators(.hidden)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task { await store.preloadPolicyGroupIcons() }
    }

    private var primaryAction: some View {
        Button {
            MainWindowPresenter.present(openWindow: openWindow)
        } label: {
            MenuBarRowLabel(title: "显示主窗口", systemImage: "macwindow", detail: "⌘M")
        }
        .buttonStyle(.plain)
    }

    private var outboundModeMenu: some View {
        Menu {
            modeButton("规则模式", mode: "rule")
            modeButton("全局模式", mode: "global")
            modeButton("直连模式", mode: "direct")
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

    private var policyMenus: some View {
        VStack(spacing: 0) {
            ForEach(orderedGroups) { group in
                Menu {
                    Button("延迟测试") { Task { await store.testGroupDelay(group) } }
                    Divider()
                    ForEach(group.all) { node in
                        Button {
                            Task { await store.selectProxy(group: group.name, proxy: node.name) }
                        } label: {
                            if node.name == group.now {
                                Label(nodeTitle(node), systemImage: "checkmark")
                            } else {
                                Text(nodeTitle(node))
                            }
                        }
                    }
                } label: {
                    MenuBarRowLabel(
                        title: Formatters.trimmedMenuText(group.name, limit: 23),
                        systemImage: groupIcon(for: group),
                        detail: nodeTitle(group.all.first { $0.name == group.now }),
                        showChevron: true
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
            if orderedGroups.isEmpty {
                MenuBarRowLabel(title: "暂无策略组", systemImage: "switch.2", detail: "请先启动核心")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var maintenanceMenus: some View {
        VStack(spacing: 0) {
            Button {
                Task { await store.toggleSystemProxy() }
            } label: {
                MenuBarRowLabel(
                    title: store.systemProxyEnabled ? "关闭系统代理" : "设置为系统代理",
                    systemImage: store.systemProxyEnabled ? "checkmark.circle.fill" : "circle",
                    tint: store.systemProxyEnabled ? .green : .primary,
                    detail: store.systemProxyEnabled ? "已启用" : "未启用"
                )
            }
            .buttonStyle(.plain)
            .disabled(!store.isCoreRunning && !store.systemProxyEnabled)

            Button {
                Task { await store.setTunEnabled(!store.settings.tunEnabled) }
            } label: {
                MenuBarRowLabel(
                    title: "TUN 模式",
                    systemImage: "lock.shield",
                    tint: store.settings.tunEnabled ? .purple : .primary,
                    detail: store.settings.tunEnabled ? "已启用" : "未启用"
                )
            }
            .buttonStyle(.plain)

            Button(action: copyTerminalProxyCommand) {
                MenuBarRowLabel(title: "复制终端代理命令", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
    }

    private var managementMenus: some View {
        VStack(spacing: 0) {
            Menu {
                Button(store.isCoreRunning ? "停止核心" : "启动核心") { Task { await store.toggleCore() } }
                Divider()
                Button(isTestingDelays ? "正在测速…" : "测试全部节点延迟") { testAllDelays() }
                    .disabled(store.proxyGroups.isEmpty || isTestingDelays)
                Button("刷新远程订阅") { Task { await store.refreshAllRemoteSubscriptions() } }
                Divider()
                sectionButton(.overview)
                sectionButton(.policies)
                sectionButton(.profiles)
                sectionButton(.rules)
                Button("连接") { openWindow(id: "connections") }
            } label: {
                MenuBarRowLabel(title: "功能面板", systemImage: "rectangle.3.group", showChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Menu {
                if applicableConfigFragments.isEmpty {
                    Text(store.configFragments.isEmpty ? "暂无覆写" : "当前配置没有可用覆写")
                } else {
                    ForEach(applicableConfigFragments) { fragment in
                        Button {
                            Task { await store.toggleConfigFragmentEnabled(fragment) }
                        } label: {
                            if fragment.enabled {
                                Label(Formatters.trimmedMenuText(fragment.name, limit: 30), systemImage: "checkmark")
                            } else {
                                Label(Formatters.trimmedMenuText(fragment.name, limit: 30), systemImage: "circle")
                            }
                        }
                    }
                }
                Divider()
                Button("管理覆写…") { sectionButtonAction(.overrides) }
            } label: {
                MenuBarRowLabel(
                    title: "覆写列表",
                    systemImage: "slider.horizontal.3",
                    detail: configFragmentSummary,
                    showChevron: true
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Button {
                Task { await store.updateAllExternalResources() }
            } label: {
                MenuBarRowLabel(
                    title: store.isResourceBatchOperationInProgress ? "正在更新外部资源…" : "更新外部资源",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isResourceBatchOperationInProgress)

            Menu {
                if store.profiles.isEmpty { Text("暂无配置") }
                ForEach(store.profiles) { profile in
                    Button {
                        Task { await store.setActiveProfile(profile) }
                    } label: {
                        if profile.id == store.settings.activeProfileID {
                            Label(Formatters.trimmedMenuText(profile.name, limit: 30), systemImage: "checkmark")
                        } else {
                            Label(Formatters.trimmedMenuText(profile.name, limit: 30), systemImage: "doc")
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
                MenuBarRowLabel(title: "重载配置", systemImage: "arrow.clockwise", detail: "⌘R")
            }
            .buttonStyle(.plain)
            .disabled(!store.isCoreRunning)

            Button {
                openWindow(id: "software-update")
                store.startSoftwareUpdateCheck()
            } label: {
                MenuBarRowLabel(title: "检查更新…", systemImage: "square.and.arrow.down", detail: "⌘U")
            }
            .buttonStyle(.plain)
        }
    }

    private var orderedGroups: [ProxyGroup] {
        store.proxyGroups.sorted { lhs, rhs in
            let lhsFavorite = store.favoritePolicyGroupNames.contains(lhs.name)
            let rhsFavorite = store.favoritePolicyGroupNames.contains(rhs.name)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var applicableConfigFragments: [ConfigFragment] {
        guard let profileID = store.activeProfile?.id else { return [] }
        return store.configFragments.filter { fragment in
            fragment.appliesGlobally || fragment.profileIDs.contains(profileID)
        }
    }

    private var configFragmentSummary: String {
        let enabled = applicableConfigFragments.filter(\.enabled).count
        return "\(enabled)/\(applicableConfigFragments.count)"
    }

    private func nodeTitle(_ node: ProxyNode?) -> String {
        guard let node else { return "未选择" }
        return "\(Formatters.trimmedMenuText(node.name, limit: 22)) · \(MenuBarDelayBadgeTitle(node: node))"
    }

    private func groupIcon(for group: ProxyGroup) -> String {
        let type = group.type.lowercased()
        if type.contains("url") { return "speedometer" }
        if type.contains("fallback") { return "arrow.triangle.2.circlepath" }
        return "switch.2"
    }

    private func modeButton(_ title: String, mode: String) -> some View {
        Button { Task { await store.setMode(mode) } } label: {
            store.currentMode == mode ? Label(title, systemImage: "checkmark") : Label(title, systemImage: "circle")
        }
    }

    private func sectionButton(_ section: AppSection) -> some View {
        Button(section.title) { sectionButtonAction(section) }
    }

    private func sectionButtonAction(_ section: AppSection) {
        store.selectedSection = section
        MainWindowPresenter.present(openWindow: openWindow)
    }

    private func testAllDelays() {
        isTestingDelays = true
        Task {
            await store.testAllProxyDelays()
            isTestingDelays = false
        }
    }

    private func copyTerminalProxyCommand() {
        let port = store.settings.mixedPort
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "export http_proxy=http://127.0.0.1:\(port) https_proxy=http://127.0.0.1:\(port) all_proxy=socks5://127.0.0.1:\(port)",
            forType: .string
        )
        store.appendLog("info", "已复制终端代理命令")
    }

    private func quit() {
        Task {
            await store.shutdown()
            NSApp.terminate(nil)
        }
    }
}
