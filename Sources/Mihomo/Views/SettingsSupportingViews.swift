import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
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
        case .routine: return "常驻"
        }
    }

    var systemImage: String {
        switch self {
        case .core: return "cpu"
        case .controller: return "point.3.connected.trianglepath.dotted"
        case .network: return "network"
        case .routine: return "clock.arrow.circlepath"
        }
    }
}

struct SettingsControllerPane: View {
    @Binding var draft: AppSettings

    var body: some View {
        SettingsSection(title: "Controller", systemImage: "point.3.connected.trianglepath.dotted") {
            SettingsRow("主机") {
                TextField("127.0.0.1", text: $draft.controllerHost)
            }
            SettingsRow("Controller 端口") {
                TextField("9090", value: $draft.controllerPort, format: .number)
                    .frame(width: 120)
            }
            SettingsRow("Secret") {
                SecureField("Bearer token", text: $draft.controllerSecret)
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
                TextField("https://cp.cloudflare.com/generate_204", text: $draft.delayTestURL)
            }
            SettingsRow("延迟测试超时（ms）") {
                TextField("8000", value: $draft.delayTestTimeoutMS, format: .number)
                    .frame(width: 120)
            }
            SettingsRow("延迟测试并发数") {
                TextField("6", value: $draft.delayTestConcurrency, format: .number)
                    .frame(width: 120)
            }
        }
    }
}

struct SettingsNetworkPane: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings

    var body: some View {
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
}

struct SettingsRoutinePane: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings
    var openSoftwareUpdate: () -> Void

    var body: some View {
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

            SettingsSoftwareUpdatePane(openSoftwareUpdate: openSoftwareUpdate)
        }
    }
}

private struct SettingsSoftwareUpdatePane: View {
    @EnvironmentObject private var store: AppStore
    var openSoftwareUpdate: () -> Void

    var body: some View {
        SettingsSection(title: "软件更新", systemImage: "arrow.down.app") {
            SettingsRow("当前版本") {
                Text("\(store.currentAppVersion) (\(store.currentAppBuild))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            SettingsRow("检查来源") {
                Link(store.softwareUpdateSourceDescription, destination: store.softwareUpdateSourceURL)
            }
            SettingsRow("状态") {
                Text(store.softwareUpdateStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            SettingsRow("操作") {
                HStack {
                    Button {
                        openSoftwareUpdate()
                        Task { await store.checkForSoftwareUpdate() }
                    } label: {
                        Label("检查 GitHub", systemImage: "arrow.clockwise")
                    }

                    Button {
                        openSoftwareUpdate()
                        Task { await store.installSoftwareUpdate() }
                    } label: {
                        Label("\(installUpdateTitle) 并重启", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.availableUpdate == nil)
                }
            }
        }
    }

    private var installUpdateTitle: String {
        if let version = store.availableUpdate?.version {
            return "安装 \(version)"
        }
        return "安装更新"
    }
}

struct SettingsSection<Content: View>: View {
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

struct SettingsRow<Content: View>: View {
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

struct SettingsToggleRow: View {
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
