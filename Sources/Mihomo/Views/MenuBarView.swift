import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack {
            Text(store.isCoreRunning ? "Mihomo 运行中" : "Mihomo 已停止")
            if let profile = store.activeProfile {
                Text(Formatters.trimmedMenuText(profile.name))
            }

            Divider()

            Button("打开主窗口") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            SettingsLink {
                Text("设置")
            }

            Divider()

            Button(store.isCoreRunning ? "停止核心" : "启动核心") {
                Task { await store.toggleCore() }
            }

            Button("重启核心") {
                Task { await store.restartCore() }
            }

            Button(store.systemProxyEnabled ? "关闭系统代理" : "开启系统代理") {
                Task { await store.toggleSystemProxy() }
            }

            Menu("出站模式") {
                modeButton("规则", mode: "rule")
                modeButton("全局", mode: "global")
                modeButton("直连", mode: "direct")
            }

            Menu("策略快捷切换") {
                if store.proxyGroups.isEmpty {
                    Text("暂无策略组")
                } else {
                    ForEach(store.proxyGroups.prefix(8)) { group in
                        Menu(Formatters.trimmedMenuText(group.name, limit: 24)) {
                            Text("当前：\(Formatters.trimmedMenuText(group.now, limit: 24))")
                            Divider()
                            ForEach(group.all.prefix(16)) { node in
                                Button {
                                    Task { await store.selectProxy(group: group.name, proxy: node.name) }
                                } label: {
                                    if node.name == group.now {
                                        Label(Formatters.trimmedMenuText(node.name, limit: 28), systemImage: "checkmark")
                                    } else {
                                        Text(Formatters.trimmedMenuText(node.name, limit: 28))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Button("刷新 Controller") {
                Task { await store.refreshController() }
            }

            Button("刷新订阅") {
                Task { await store.refreshAllRemoteProfiles() }
            }

            Button(store.logsPaused ? "继续日志" : "暂停日志") {
                store.toggleLogPause()
            }

            Button("修复系统代理") {
                Task { await store.repairSystemProxy() }
            }

            Button("运行诊断") {
                Task { await store.runDiagnostics() }
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("轻量模式") {
                store.enterLightweightMode()
            }

            Divider()

            Button("退出 Mihomo") {
                Task {
                    await store.shutdown()
                    NSApp.terminate(nil)
                }
            }
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
}
