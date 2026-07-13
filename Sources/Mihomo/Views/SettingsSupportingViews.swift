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
                title: "远程管理",
                subtitle: "Mihomo 会自动管理本机控制通道。只有需要从其他设备查看状态或切换策略时，才开启远程管理。",
                systemImage: "externaldrive.connected.to.line.below"
            ) {
                SettingsToggleDescriptionRow(
                    "允许其他设备管理此 Mac",
                    description: "关闭时仅 Mihomo 本机可以访问核心状态，日常使用无需配置地址或密钥。",
                    isOn: remoteManagementBinding
                )

                if draft.remoteAPIEnabled {
                    SettingsRow("监听地址") {
                        TextField("0.0.0.0", text: $draft.remoteAPIBindAddress)
                    }
                    SettingsRow("管理端口") {
                        TextField("9090", value: $draft.controllerPort, format: .number)
                            .frame(width: 140)
                    }
                    SettingsRow("访问密钥") {
                        HStack {
                            SecureField("应用会自动生成", text: $draft.controllerSecret)
                            Button("重新生成") { regenerateAccessKey() }
                        }
                    }
                    Label("请只在受信任网络中开放，并使用访问密钥。更改会在应用后重启核心。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                } else {
                    SettingsRow("当前状态") {
                        Label("仅本机访问 · 自动管理", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection(
                title: "局域网代理",
                subtitle: "这决定其他设备能否使用本机代理端口，与远程管理权限是两项独立能力。",
                systemImage: "network.badge.shield.half.filled"
            ) {
                SettingsToggleDescriptionRow(
                    "允许局域网设备使用代理",
                    description: "开启后，局域网设备可以连接 Mixed/SOCKS 端口；不会自动获得管理权限。",
                    isOn: $draft.allowLAN
                )
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

    private var remoteManagementBinding: Binding<Bool> {
        Binding(
            get: { draft.remoteAPIEnabled },
            set: { enabled in
                draft.remoteAPIEnabled = enabled
                draft.controllerHost = draft.localControlHost
                if enabled {
                    let address = draft.remoteAPIBindAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    if address.isEmpty || address == "127.0.0.1" || address == "localhost" {
                        draft.remoteAPIBindAddress = "0.0.0.0"
                    }
                    if draft.controllerSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        regenerateAccessKey()
                    }
                }
            }
        )
    }

    private func regenerateAccessKey() {
        draft.controllerSecret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
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

struct SettingsToggleDescriptionRow: View {
    var title: String
    var description: String
    @Binding var isOn: Bool

    init(_ title: String, description: String, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        _isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}
