import SwiftUI

struct AdvancedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                coreGroup
                profileEncryptionGroup
                controllerGroup
                dnsGroup
                snifferGroup
                externalUIGroup
                previewGroup
                geoGroup
                backupGroup
                deepLinkGroup
            }
            .padding(.horizontal, MihomoUI.pageHorizontalPadding)
            .padding(.vertical, MihomoUI.pageVerticalPadding)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(store.advancedStatus)
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
            .padding(.horizontal, MihomoUI.pageHorizontalPadding)
            .padding(.bottom, MihomoUI.pageVerticalPadding)
            .padding(.top, 8)
            .background(.bar)
        }
        .navigationTitle("高级")
        .onAppear {
            draft = store.settings
            store.refreshConfigArtifacts()
        }
        .onReceive(store.$settings) { settings in
            draft = settings
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("高级")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("Helper、远程访问、DNS、Sniffer、备份与导入。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.runDiagnostics() }
            } label: {
                Label("诊断", systemImage: "stethoscope")
            }
        }
    }

    private var coreGroup: some View {
        GroupBox("Helper 与 LaunchDaemon") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("XPC Helper") {
                    Text(store.helperStatus)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button {
                        Task { await store.registerHelper() }
                    } label: {
                        Label("注册 Helper", systemImage: "person.badge.key")
                    }

                    Button {
                        Task { await store.refreshHelperStatus() }
                    } label: {
                        Label("检查 Helper", systemImage: "checkmark.shield")
                    }

                    Button {
                        Task { await store.auditHelper() }
                    } label: {
                        Label("审计 Helper", systemImage: "checklist")
                    }

                    Button {
                        Task { await store.repairHelperRegistration() }
                    } label: {
                        Label("修复注册", systemImage: "wrench.adjustable")
                    }

                    Button {
                        Task { await store.unregisterHelper() }
                    } label: {
                        Label("卸载 Helper", systemImage: "trash")
                    }
                }

                Divider()

                LabeledContent("核心来源") {
                    Text(store.settings.coreSource.title)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("当前有效路径") {
                    Text(store.effectiveMihomoPath.isEmpty ? "未设置" : store.effectiveMihomoPath)
                        .textSelection(.enabled)
                }
                HStack {
                    Toggle("LaunchDaemon 托管核心", isOn: $draft.launchDaemonEnabled)

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.installLaunchDaemon()
                        }
                    } label: {
                        Label("安装", systemImage: "lock.shield")
                    }

                    Button {
                        Task { await store.uninstallLaunchDaemon() }
                    } label: {
                        Label("卸载", systemImage: "trash")
                    }
                }
                Text(store.launchDaemonStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var controllerGroup: some View {
        GroupBox("远程访问") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("启用远程 HTTP API", isOn: $draft.remoteAPIEnabled)
                    TextField("绑定地址", text: $draft.remoteAPIBindAddress)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var profileEncryptionGroup: some View {
        AdvancedProfileEncryptionGroup(draft: $draft)
    }

    private var dnsGroup: some View {
        GroupBox("DNS") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("启动时设置系统 DNS", isOn: $draft.autoSetSystemDNS)
                    TextField("1.1.1.1, 8.8.8.8", text: listBinding(\.systemDNSServers))
                }
                GridRow {
                    Text("Enhanced Mode")
                    Picker("Enhanced Mode", selection: $draft.dnsEnhancedMode) {
                        Text("fake-ip").tag("fake-ip")
                        Text("redir-host").tag("redir-host")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                GridRow {
                    Text("Nameserver")
                    TextField("https://1.1.1.1/dns-query", text: listBinding(\.dnsNameservers))
                }
                GridRow {
                    Text("Fallback")
                    TextField("可选", text: listBinding(\.dnsFallbacks))
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var snifferGroup: some View {
        GroupBox("Sniffer") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("启用 Sniffer", isOn: $draft.snifferEnabled)
                    TextField("端口", text: $draft.snifferPorts)
                }
                GridRow {
                    Text("Force Domain")
                    TextField("逗号或换行分隔", text: $draft.snifferForceDomains)
                }
                GridRow {
                    Text("Skip Domain")
                    TextField("逗号或换行分隔", text: $draft.snifferSkipDomains)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var externalUIGroup: some View {
        AdvancedExternalUIGroup(draft: $draft)
    }

    private var previewGroup: some View {
        AdvancedConfigPreviewGroup()
    }

    private var geoGroup: some View {
        AdvancedGeoGroup(draft: $draft)
    }

    private var backupGroup: some View {
        AdvancedBackupGroup(draft: $draft)
    }

    private var deepLinkGroup: some View {
        GroupBox("深链导入") {
            VStack(alignment: .leading, spacing: 8) {
                Text("mihomo://install-profile?url=https%3A%2F%2Fexample.com%2Fconfig.yaml&name=Work")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("mihomo://install-fragment?kind=yaml&name=Patch&url=https%3A%2F%2Fexample.com%2Fpatch.yaml")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }

    private func listBinding(_ keyPath: WritableKeyPath<AppSettings, [String]>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath].joined(separator: ", ") },
            set: { draft[keyPath: keyPath] = parseList($0) }
        )
    }

    private func parseList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

}
