import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack {
            Button("显示主窗口") {
                MainWindowPresenter.present(openWindow: openWindow)
            }
            .keyboardShortcut("m", modifiers: [.command])

            Divider()

            Menu("出站模式") {
                modeButton("规则", mode: "rule")
                modeButton("全局", mode: "global")
                modeButton("直连", mode: "direct")
            }

            Button(store.isCoreRunning ? "停止核心" : "启动核心") {
                Task { await store.toggleCore() }
            }

            Button("重启核心") {
                Task { await store.restartCore() }
            }

            Button(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理") {
                Task { await store.toggleSystemProxy() }
            }

            Button(store.settings.tunEnabled ? "关闭 TUN" : "开启 TUN") {
                Task { await store.setTunEnabled(!store.settings.tunEnabled) }
            }

            Divider()

            if store.proxyGroups.isEmpty {
                Text("暂无策略组")
            } else {
                ForEach(store.proxyGroups.prefix(10)) { group in
                    policyGroupMenu(group)
                }
            }

            Divider()

            Text("进程与客户端")
                .foregroundStyle(.secondary)
            Text("-")
            Text("-")
            Text("-")

            Divider()

            Button("设置为系统代理") {
                Task {
                    if store.systemProxyEnabled == false {
                        await store.toggleSystemProxy()
                    }
                }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("更新资源") {
                Task { await store.updateAllExternalResources() }
            }

            Menu("功能") {
                Button("运行诊断") {
                    Task { await store.runDiagnostics() }
                    show(.diagnostics)
                }

                Button("修复系统代理") {
                    Task { await store.repairSystemProxy() }
                }

                Button("测试全部节点延迟") {
                    Task { await store.testAllProxyDelays() }
                }

                Button(store.logsPaused ? "继续日志" : "暂停日志") {
                    store.toggleLogPause()
                }

                Button("轻量模式") {
                    store.enterLightweightMode()
                }
            }

            Menu("模块") {
                Button("刷新 Controller") {
                    Task { await store.refreshController() }
                }

                Button("刷新订阅") {
                    Task { await store.refreshAllRemoteProfiles() }
                }

                Button("更新资源") {
                    Task { await store.updateAllExternalResources() }
                }

                Button("更新 Geo 数据") {
                    Task { await store.updateGeoData() }
                }
            }

            Menu("面板") {
                sectionButton("概览", .overview)
                sectionButton("活动", .activity)
                sectionButton("策略", .policies)
                sectionButton("配置", .profiles)
                sectionButton("规则", .rules)
                sectionButton("资源", .resources)
                sectionButton("诊断", .diagnostics)
                SettingsLink {
                    Text("设置")
                }
            }

            Divider()

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

            Button("重载配置") {
                Task { await store.restartCore() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("检查更新...") {
                openWindow(id: "software-update")
                Task { await store.checkForSoftwareUpdate() }
            }
            .keyboardShortcut("u", modifiers: [.command])

            Divider()

            Button("退出 Mihomo") {
                Task {
                    await store.shutdown()
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func policyGroupMenu(_ group: ProxyGroup) -> some View {
        Menu {
            Text("当前：\(Formatters.trimmedMenuText(group.now.isEmpty ? "-" : group.now, limit: 28))")
            Divider()
            ForEach(group.all.prefix(18)) { node in
                Button {
                    Task { await store.selectProxy(group: group.name, proxy: node.name) }
                } label: {
                    if node.name == group.now {
                        Label(Formatters.trimmedMenuText(node.name, limit: 30), systemImage: "checkmark")
                    } else {
                        Text(Formatters.trimmedMenuText(node.name, limit: 30))
                    }
                }
            }
        } label: {
            Label(
                "\(Formatters.trimmedMenuText(group.name, limit: 18))  \(Formatters.trimmedMenuText(group.now, limit: 14))",
                systemImage: iconName(for: group)
            )
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
            show(section)
        }
    }

    private func show(_ section: AppSection) {
        store.selectedSection = section
        MainWindowPresenter.present(openWindow: openWindow)
    }

    private func iconName(for group: ProxyGroup) -> String {
        let type = group.type.lowercased()
        if type.contains("url") { return "speedometer" }
        if type.contains("fallback") { return "arrow.triangle.2.circlepath" }
        return "switch.2"
    }
}
