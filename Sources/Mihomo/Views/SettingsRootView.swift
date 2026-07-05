import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default
    @State private var tab: SettingsTab = .core

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .core:
                        corePane
                    case .controller:
                        controllerPane
                    case .network:
                        networkPane
                    case .routine:
                        routinePane
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .frame(minWidth: 720, minHeight: 560)
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

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.title2.bold())
                Text("核心、Controller、网络接管与常驻行为。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("设置分类", selection: $tab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 430)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var corePane: some View {
        SettingsSection(title: "核心", systemImage: "cpu") {
            SettingsRow("mihomo 可执行文件") {
                HStack {
                    TextField("路径", text: $draft.mihomoPath)
                    Button {
                        chooseMihomoBinary()
                    } label: {
                        Label("选择", systemImage: "folder")
                    }
                }
            }

            SettingsRow("日志等级") {
                Picker("日志等级", selection: $draft.logLevel) {
                    Text("调试").tag("debug")
                    Text("信息").tag("info")
                    Text("警告").tag("warning")
                    Text("错误").tag("error")
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            SettingsToggleRow("打开后自动启动核心", isOn: $draft.autoStartCore)
            SettingsToggleRow("核心异常退出后自动恢复", isOn: $draft.restartCoreOnCrash)
            SettingsRow("崩溃恢复次数上限") {
                TextField("3", value: $draft.maxCrashRestarts, format: .number)
                    .frame(width: 120)
            }
        }
    }

    private var controllerPane: some View {
        SettingsSection(title: "Controller", systemImage: "point.3.connected.trianglepath.dotted") {
            SettingsRow("主机") {
                TextField("127.0.0.1", text: $draft.controllerHost)
            }
            SettingsRow("Controller 端口") {
                TextField("9090", value: $draft.controllerPort, format: .number)
                    .frame(width: 120)
            }
            SettingsRow("Mixed 端口") {
                TextField("7890", value: $draft.mixedPort, format: .number)
                    .frame(width: 120)
            }
            SettingsRow("SOCKS 端口") {
                TextField("0", value: $draft.socksPort, format: .number)
                    .frame(width: 120)
            }
            SettingsRow("延迟测试 URL") {
                TextField("https://www.gstatic.com/generate_204", text: $draft.delayTestURL)
            }
            SettingsRow("延迟测试并发数") {
                TextField("6", value: $draft.delayTestConcurrency, format: .number)
                    .frame(width: 120)
            }
        }
    }

    private var networkPane: some View {
        SettingsSection(title: "网络接管", systemImage: "network") {
            SettingsToggleRow("允许局域网访问", isOn: $draft.allowLAN)
            SettingsToggleRow("在运行配置中启用 TUN", isOn: $draft.tunEnabled)
            SettingsToggleRow("停止/退出时回滚 TUN DNS 与路由", isOn: $draft.restoreTunOnStop)
            SettingsToggleRow("策略切换后关闭连接", isOn: $draft.closeConnectionsOnPolicyChange)
            SettingsToggleRow("退出时恢复系统代理", isOn: $draft.restoreSystemProxyOnQuit)
            SettingsRow("TUN 状态") {
                Text(store.tunRecoveryStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var routinePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "订阅与常驻", systemImage: "clock.arrow.circlepath") {
                SettingsToggleRow("自动刷新远程订阅", isOn: $draft.autoRefreshProfiles)
                SettingsRow("刷新间隔（小时）") {
                    TextField("24", value: $draft.profileRefreshIntervalHours, format: .number)
                        .frame(width: 120)
                }
                SettingsRow("订阅刷新并发数") {
                    TextField("2", value: $draft.profileRefreshMaxConcurrent, format: .number)
                        .frame(width: 120)
                }
                SettingsToggleRow("登录后自动打开 Mihomo", isOn: $draft.launchAtLogin)
                SettingsToggleRow("轻量模式启动", isOn: $draft.lightweightMode)
                SettingsRow("登录项") {
                    Text(store.loginItemStatus)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: "日志", systemImage: "terminal") {
                SettingsRow("日志保留天数") {
                    TextField("7", value: $draft.logRetentionDays, format: .number)
                        .frame(width: 120)
                }
                SettingsRow("单文件滚动大小（MB）") {
                    TextField("8", value: $draft.logMaxFileSizeMB, format: .number)
                        .frame(width: 120)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(store.profileAutoRefreshStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                draft = store.settings
            } label: {
                Label("重置", systemImage: "arrow.uturn.backward")
            }
            .disabled(draft == store.settings)

            Button {
                Task { await store.saveSettings(draft) }
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft == store.settings)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
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

private enum SettingsTab: String, CaseIterable, Identifiable {
    case core
    case controller
    case network
    case routine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: return "核心"
        case .controller: return "Controller"
        case .network: return "网络"
        case .routine: return "高级"
        }
    }

    var systemImage: String {
        switch self {
        case .core: return "cpu"
        case .controller: return "point.3.connected.trianglepath.dotted"
        case .network: return "network"
        case .routine: return "gearshape.2"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(spacing: 0) {
                content
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .trailing)

            content
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 210)
        }
    }
}

private struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
    }
}
