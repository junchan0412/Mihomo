import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case remoteAccess
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .remoteAccess: return "远程访问"
        case .advanced: return "高级"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .remoteAccess: return "network"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct SettingsRemoteAccessPane: View {
    @Binding var draft: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "本机 Controller",
                subtitle: "用于应用连接 mihomo。配置文件中的同名字段会覆盖这些应用默认值。",
                systemImage: "point.3.connected.trianglepath.dotted"
            ) {
                SettingsRow("主机") {
                    TextField("127.0.0.1", text: $draft.controllerHost)
                }
                SettingsRow("端口") {
                    TextField("9090", value: $draft.controllerPort, format: .number)
                        .frame(width: 140)
                }
                SettingsRow("Secret") {
                    SecureField("可留空", text: $draft.controllerSecret)
                }
            }

            SettingsSection(
                title: "远程访问",
                subtitle: "仅在需要从其他设备管理此 Mac 时启用。建议限制监听地址并设置 Secret。",
                systemImage: "externaldrive.connected.to.line.below"
            ) {
                SettingsToggleRow("启用远程 HTTP API", isOn: $draft.remoteAPIEnabled)
                SettingsRow("绑定地址") {
                    TextField("127.0.0.1", text: $draft.remoteAPIBindAddress)
                }
                .disabled(!draft.remoteAPIEnabled)
                SettingsToggleRow("允许局域网访问代理", isOn: $draft.allowLAN)
            }

            SettingsSection(
                title: "延迟测试",
                subtitle: "策略页测速使用的目标、超时与并发限制。",
                systemImage: "speedometer"
            ) {
                SettingsRow("测试 URL") {
                    TextField("https://cp.cloudflare.com/generate_204", text: $draft.delayTestURL)
                }
                SettingsRow("超时（ms）") {
                    TextField("8000", value: $draft.delayTestTimeoutMS, format: .number)
                        .frame(width: 140)
                }
                SettingsRow("并发数") {
                    TextField("6", value: $draft.delayTestConcurrency, format: .number)
                        .frame(width: 140)
                }
            }
        }
    }
}

struct SettingsAdvancedPane: View {
    @Binding var draft: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "连接与端口",
                subtitle: "定义本机代理监听端口与策略切换行为。实时接管、DNS 和恢复统一在“网络”中管理。",
                systemImage: "network"
            ) {
                SettingsRow("Mixed 端口") {
                    TextField("7890", value: $draft.mixedPort, format: .number)
                        .frame(width: 140)
                }
                SettingsRow("SOCKS 端口") {
                    TextField("0", value: $draft.socksPort, format: .number)
                        .frame(width: 140)
                }
                SettingsToggleRow("策略切换后关闭旧连接", isOn: $draft.closeConnectionsOnPolicyChange)
            }

            SettingsSection(
                title: "Sniffer",
                subtitle: "帮助核心从连接中还原域名；不熟悉时保持关闭即可。",
                systemImage: "waveform.path.ecg"
            ) {
                SettingsToggleRow("启用 Sniffer", isOn: $draft.snifferEnabled)
                SettingsRow("端口") {
                    TextField("80,443", text: $draft.snifferPorts)
                }
                SettingsRow("Force Domain") {
                    TextField("逗号或换行分隔", text: $draft.snifferForceDomains)
                }
                SettingsRow("Skip Domain") {
                    TextField("逗号或换行分隔", text: $draft.snifferSkipDomains)
                }
            }

        }
    }
}

struct SettingsSoftwareUpdatePane: View {
    @EnvironmentObject private var store: AppStore
    var openSoftwareUpdate: () -> Void

    var body: some View {
        SettingsSection(title: "软件更新", subtitle: "检查 GitHub Release，并在安装前验证更新包。", systemImage: "arrow.down.app") {
            SettingsRow("当前版本") {
                Text("\(store.currentAppVersion) (\(store.currentAppBuild))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
                        Label("检查更新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        openSoftwareUpdate()
                        Task { await store.installSoftwareUpdate() }
                    } label: {
                        Label(installTitle, systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.availableUpdate == nil)
                }
            }
        }
    }

    private var installTitle: String {
        store.availableUpdate.map { "安装 \($0.version)" } ?? "安装更新"
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 0) { content }
                .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(MihomoUI.cardStroke, lineWidth: 1) }
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
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .trailing)
            content
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 204)
        }
    }
}

struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
