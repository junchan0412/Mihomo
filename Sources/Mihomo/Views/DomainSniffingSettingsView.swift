import SwiftUI

struct DomainSniffingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var draft: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                title: "域名嗅探",
                subtitle: "从 HTTP Host、TLS SNI 和 QUIC 握手中识别域名，让直接连接 IP 的应用也能匹配域名规则。它不会解密 HTTPS，也不是 DNS 查询。",
                systemImage: "viewfinder"
            ) {
                SettingsToggleDescriptionRow(
                    "由 Mihomo 管理域名嗅探",
                    description: "开启后使用本页设置；关闭后完全遵循当前 Profile 中的 sniffer 配置。",
                    isOn: $draft.snifferManagedByApp
                )
                SettingsToggleDescriptionRow(
                    "启用域名嗅探",
                    description: "建议在 TUN、透明代理或部分应用直接访问 IP 时开启。",
                    isOn: $draft.snifferEnabled
                )
                .disabled(!draft.snifferManagedByApp)
                SettingsRow("当前行为") {
                    Label(statusTitle, systemImage: statusIcon)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(
                title: "协议与端口",
                subtitle: "分别指定需要检查初始握手的端口。支持单个端口和 8000-9000 范围。",
                systemImage: "point.3.filled.connected.trianglepath.dotted"
            ) {
                SettingsRow("HTTP") {
                    TextField("80,443", text: $draft.snifferHTTPPorts)
                }
                SettingsRow("TLS") {
                    TextField("443", text: $draft.snifferTLSPorts)
                }
                SettingsRow("QUIC") {
                    TextField("可留空", text: $draft.snifferQUICPorts)
                }
            }
            .disabled(!isEditable)

            SettingsSection(
                title: "识别方式",
                subtitle: "推荐保持前两项开启；替换连接目标可能改善路由，也可能影响少数兼容性较差的服务。",
                systemImage: "scope"
            ) {
                SettingsToggleDescriptionRow(
                    "识别直接使用 IP 的连接",
                    description: "连接没有 DNS 映射时，仍尝试从握手中读取域名。",
                    isOn: $draft.snifferParsePureIP
                )
                SettingsToggleDescriptionRow(
                    "使用 DNS 映射辅助识别",
                    description: "结合 Fake-IP 或 DNS 映射还原连接原本访问的域名。",
                    isOn: $draft.snifferForceDNSMapping
                )
                SettingsToggleDescriptionRow(
                    "使用识别出的域名替换目标",
                    description: "让后续连接以域名重新解析；遇到特定应用连接异常时请关闭。",
                    isOn: $draft.snifferOverrideDestination
                )
            }
            .disabled(!isEditable)

            SettingsSection(
                title: "例外规则",
                subtitle: "每项使用逗号或换行分隔。域名可使用 +.example.com，地址使用 IP 或 CIDR。",
                systemImage: "line.3.horizontal.decrease.circle"
            ) {
                SettingsRow("不嗅探的域名") {
                    TextField("+.push.apple.com", text: $draft.snifferSkipDomains)
                }
                SettingsRow("强制嗅探的域名") {
                    TextField("可留空", text: $draft.snifferForceDomains)
                }
                SettingsRow("不嗅探的目标地址") {
                    TextField("例如 1.1.1.1/32", text: $draft.snifferSkipDestinationAddresses)
                }
                SettingsRow("不嗅探的来源地址") {
                    TextField("例如 192.168.1.0/24", text: $draft.snifferSkipSourceAddresses)
                }
            }
            .disabled(!isEditable)

            footer
        }
    }

    private var isEditable: Bool {
        draft.snifferManagedByApp && draft.snifferEnabled
    }

    private var statusTitle: String {
        if !draft.snifferManagedByApp { return "由当前 Profile 决定" }
        return draft.snifferEnabled ? "已启用，使用本页规则" : "已关闭"
    }

    private var statusIcon: String {
        if !draft.snifferManagedByApp { return "doc.text" }
        return draft.snifferEnabled ? "checkmark.circle.fill" : "pause.circle"
    }

    private var footer: some View {
        HStack {
            Text(draft == store.settings ? "域名嗅探设置已应用" : "有尚未应用的更改")
                .foregroundStyle(.secondary)
            Spacer()
            Button("取消") { draft = store.settings }
                .keyboardShortcut(.cancelAction)
                .disabled(draft == store.settings)
            Button(store.isCoreRunning ? "应用并重启核心" : "应用") {
                Task { await applySettings() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(draft == store.settings)
        }
    }

    private func applySettings() async {
        let updated = draft
        let shouldRestart = store.isCoreRunning && snifferSettingsChanged(from: store.settings, to: updated)
        await store.saveSettings(updated)
        if shouldRestart, store.settings == updated {
            await store.restartCore()
        }
    }

    private func snifferSettingsChanged(from old: AppSettings, to new: AppSettings) -> Bool {
        old.snifferManagedByApp != new.snifferManagedByApp
            || old.snifferEnabled != new.snifferEnabled
            || old.snifferParsePureIP != new.snifferParsePureIP
            || old.snifferForceDNSMapping != new.snifferForceDNSMapping
            || old.snifferOverrideDestination != new.snifferOverrideDestination
            || old.snifferHTTPPorts != new.snifferHTTPPorts
            || old.snifferTLSPorts != new.snifferTLSPorts
            || old.snifferQUICPorts != new.snifferQUICPorts
            || old.snifferForceDomains != new.snifferForceDomains
            || old.snifferSkipDomains != new.snifferSkipDomains
            || old.snifferSkipDestinationAddresses != new.snifferSkipDestinationAddresses
            || old.snifferSkipSourceAddresses != new.snifferSkipSourceAddresses
    }
}

struct DomainSniffingSummaryCard: View {
    @EnvironmentObject private var store: AppStore
    var openDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.title2)
                    .foregroundStyle(store.settings.snifferEnabled ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("域名嗅探").font(.headline)
                    Text("从连接握手识别域名，帮助直接访问 IP 的应用匹配域名规则。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("域名嗅探", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!store.settings.snifferManagedByApp)
            }

            Divider()

            HStack {
                Label(summaryStatus, systemImage: summaryIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("详细设置", action: openDetails)
            }
        }
        .padding(16)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(MihomoUI.cardStroke, lineWidth: 1) }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.snifferEnabled },
            set: { enabled in
                Task {
                    var updated = store.settings
                    updated.snifferEnabled = enabled
                    await store.saveSettings(updated)
                    if store.settings == updated, store.isCoreRunning {
                        await store.restartCore()
                    }
                }
            }
        )
    }

    private var summaryStatus: String {
        if !store.settings.snifferManagedByApp { return "由当前 Profile 决定" }
        return store.settings.snifferEnabled ? "已启用" : "已关闭"
    }

    private var summaryIcon: String {
        if !store.settings.snifferManagedByApp { return "doc.text" }
        return store.settings.snifferEnabled ? "checkmark.circle.fill" : "pause.circle"
    }
}
