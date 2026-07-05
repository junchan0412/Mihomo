import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default

    var body: some View {
        TabView {
            Form {
                Section("核心") {
                    HStack {
                        TextField("mihomo 可执行文件", text: $draft.mihomoPath)
                        Button("选择...") {
                            chooseMihomoBinary()
                        }
                    }

                    Picker("日志等级", selection: $draft.logLevel) {
                        Text("调试").tag("debug")
                        Text("信息").tag("info")
                        Text("警告").tag("warning")
                        Text("错误").tag("error")
                    }
                    .pickerStyle(.segmented)

                    Toggle("打开 Mihomo 后自动启动核心", isOn: $draft.autoStartCore)
                    Toggle("核心异常退出后自动恢复", isOn: $draft.restartCoreOnCrash)
                    TextField("崩溃恢复次数上限", value: $draft.maxCrashRestarts, format: .number)
                }
            }
            .tabItem { Label("核心", systemImage: "cpu") }

            Form {
                Section("Controller") {
                    TextField("主机", text: $draft.controllerHost)
                    TextField("Controller 端口", value: $draft.controllerPort, format: .number)
                    TextField("Mixed 端口", value: $draft.mixedPort, format: .number)
                    TextField("SOCKS 端口", value: $draft.socksPort, format: .number)
                    TextField("延迟测试 URL", text: $draft.delayTestURL)
                    TextField("延迟测试并发数", value: $draft.delayTestConcurrency, format: .number)
                }
            }
            .tabItem { Label("Controller", systemImage: "point.3.connected.trianglepath.dotted") }

            Form {
                Section("网络接管") {
                    Toggle("允许局域网访问", isOn: $draft.allowLAN)
                    Toggle("在运行配置中启用 TUN", isOn: $draft.tunEnabled)
                    Toggle("停止/退出时回滚 TUN DNS 与路由", isOn: $draft.restoreTunOnStop)
                    Toggle("策略切换后关闭连接", isOn: $draft.closeConnectionsOnPolicyChange)
                    Toggle("退出时恢复系统代理", isOn: $draft.restoreSystemProxyOnQuit)
                    Text(store.tunRecoveryStatus)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("网络", systemImage: "network") }

            Form {
                Section("订阅与常驻") {
                    Toggle("自动刷新远程订阅", isOn: $draft.autoRefreshProfiles)
                    TextField("刷新间隔（小时）", value: $draft.profileRefreshIntervalHours, format: .number)
                    TextField("订阅刷新并发数", value: $draft.profileRefreshMaxConcurrent, format: .number)
                    Toggle("登录后自动打开 Mihomo", isOn: $draft.launchAtLogin)
                    Toggle("轻量模式启动", isOn: $draft.lightweightMode)
                    Text(store.loginItemStatus)
                        .foregroundStyle(.secondary)
                }

                Section("日志") {
                    TextField("日志保留天数", value: $draft.logRetentionDays, format: .number)
                    TextField("单文件滚动大小（MB）", value: $draft.logMaxFileSizeMB, format: .number)
                }
            }
            .tabItem { Label("高级", systemImage: "gearshape.2") }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(store.profileAutoRefreshStatus)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重置") {
                    draft = store.settings
                }
                .disabled(draft == store.settings)

                Button("保存") {
                    Task { await store.saveSettings(draft) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == store.settings)
            }
            .padding([.horizontal, .bottom], 24)
            .padding(.top, 8)
            .background(.bar)
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 500)
        .navigationTitle("设置")
        .onAppear {
            draft = store.settings
        }
        .onReceive(store.$settings) { settings in
            if draft == AppSettings.default || draft == store.settings {
                draft = settings
            }
        }
    }

    private func chooseMihomoBinary() {
        let panel = NSOpenPanel()
        panel.title = "选择 mihomo 可执行文件"
        panel.message = "选择用于运行核心的 mihomo 可执行文件。"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            draft.mihomoPath = url.path
        }
    }
}
