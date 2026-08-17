import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var isTestingDelays = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                primaryAction
                Divider().padding(.leading, 14)
                outboundModeMenu
                Divider().padding(.leading, 14)
                policyMenus
                if activeConnections.isEmpty == false {
                    Divider().padding(.leading, 14)
                    connectionMenus
                }
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
            .padding(.vertical, 5)
        }
        .frame(width: 312, height: 620)
        .background(MihomoUI.pageBackground)
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
                    Button("测试此策略组") { Task { await store.testGroupDelay(group) } }
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
                        subtitle: group.type,
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

    private var connectionMenus: some View {
        VStack(spacing: 0) {
            MenuBarSectionHeader(title: "进程与客户端", detail: "\(activeConnections.count)")
            ForEach(activeConnections) { connection in
                HStack(spacing: 10) {
                    Image(systemName: "app.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(Formatters.trimmedMenuText(connection.processName, limit: 24))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Formatters.rate(connection.upload + connection.download))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
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
                    title: "增强模式 (TUN)",
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
                Button("重启核心") { Task { await store.restartCore() } }
                    .disabled(!store.isCoreRunning)
                Divider()
                Button(isTestingDelays ? "正在测速…" : "测试全部节点延迟") { testAllDelays() }
                    .disabled(store.proxyGroups.isEmpty || isTestingDelays)
                Button("更新所有资源") { Task { await store.updateAllExternalResources() } }
                Button("刷新远程订阅") { Task { await store.refreshAllRemoteSubscriptions() } }
            } label: {
                MenuBarRowLabel(title: "功能", systemImage: "wrench.and.screwdriver", showChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Menu {
                sectionButton(.overview)
                sectionButton(.policies)
                sectionButton(.profiles)
                sectionButton(.rules)
                Divider()
                Button("连接") { openWindow(id: "connections") }
            } label: {
                MenuBarRowLabel(title: "面板", systemImage: "rectangle.3.group", showChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

            Menu {
                sectionButton(.resources)
                sectionButton(.overrides)
                sectionButton(.networkSecurity)
                sectionButton(.advanced)
                sectionButton(.diagnostics)
            } label: {
                MenuBarRowLabel(title: "模块", systemImage: "square.grid.2x2", showChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)

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

    private var activeConnections: [ConnectionItem] {
        Array(store.activityStore.connections.prefix(5))
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
        Button(section.title) {
            store.selectedSection = section
            MainWindowPresenter.present(openWindow: openWindow)
        }
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
