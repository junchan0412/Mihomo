import SwiftUI

enum AdvancedWorkspaceTab: String, CaseIterable, Identifiable {
    case runtime
    case data
    case backup
    case inspection

    var id: String { rawValue }
    var title: String {
        switch self {
        case .runtime: return "运行工具"
        case .data: return "Geo 数据"
        case .backup: return "备份与安全"
        case .inspection: return "配置预览"
        }
    }
    var systemImage: String {
        switch self {
        case .runtime: return "wrench.and.screwdriver"
        case .data: return "shippingbox"
        case .backup: return "lock.shield"
        case .inspection: return "doc.text.magnifyingglass"
        }
    }
}

struct AdvancedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default
    @State private var lastSavedSettings = AppSettings.default
    @State private var tab: AdvancedWorkspaceTab = .runtime
    @State private var confirmsHelperUninstall = false
    @State private var confirmsLaunchDaemonUninstall = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .runtime:
                        helperGroup
                        deepLinkGroup
                    case .data:
                        AdvancedGeoGroup(draft: $draft)
                    case .backup:
                        AdvancedProfileEncryptionGroup(draft: $draft)
                        AdvancedBackupGroup(draft: $draft)
                    case .inspection:
                        AdvancedConfigPreviewGroup()
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, MihomoUI.pageHorizontalPadding)
                .padding(.vertical, MihomoUI.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("高级工具")
        .background(MihomoUI.pageBackground)
        .onAppear {
            synchronizeDraft(with: store.settings, force: true)
            store.refreshConfigArtifacts()
        }
        .onReceive(store.$settings) { synchronizeDraft(with: $0, force: false) }
        .confirmationDialog("卸载 XPC Helper？", isPresented: $confirmsHelperUninstall, titleVisibility: .visible) {
            Button("卸载 Helper", role: .destructive) { Task { await store.unregisterHelper() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("卸载后，需要管理员权限的系统代理、DNS、TUN 与核心托管操作将不可用，直到重新注册。")
        }
        .confirmationDialog("卸载 LaunchDaemon？", isPresented: $confirmsLaunchDaemonUninstall, titleVisibility: .visible) {
            Button("卸载 LaunchDaemon", role: .destructive) { Task { await store.uninstallLaunchDaemon() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("后台托管的核心进程会停止，登录后也不会自动由 LaunchDaemon 启动。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("高级工具").font(MihomoUI.Fonts.pageTitle)
                    Text("管理系统级组件、数据工件、加密与备份；诊断和网络恢复使用各自专页。")
                        .font(MihomoUI.Fonts.pageSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(store.helperStatus.localizedCaseInsensitiveContains("正常") ? "Helper 正常" : "检查 Helper", systemImage: "person.badge.key")
                    .font(.callout)
                    .foregroundStyle(store.helperStatus.localizedCaseInsensitiveContains("正常") ? Color.green : Color.secondary)
            }
            Picker("工具分类", selection: $tab) {
                ForEach(AdvancedWorkspaceTab.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 650)
            Text(tabDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, 14)
    }

    private var tabDescription: String {
        switch tab {
        case .runtime: return "管理 Helper、LaunchDaemon 与自动化入口。"
        case .data: return "维护 GeoIP、GeoSite、Country MMDB 与 ASN MMDB 数据。"
        case .backup: return "配置加密、备份和跨设备恢复。"
        case .inspection: return "查看最终运行配置与配置来源，不执行诊断或网络修复。"
        }
    }

    private var helperGroup: some View {
        SettingsSection(
            title: "Helper 与 LaunchDaemon",
            subtitle: "需要管理员权限的系统操作集中由 Helper 执行。出现权限或恢复问题时再使用修复操作。",
            systemImage: "person.badge.key"
        ) {
            SettingsRow("XPC Helper") {
                Text(store.helperStatus).foregroundStyle(.secondary).textSelection(.enabled)
            }
            SettingsRow("Helper 操作") {
                HStack {
                    Button("注册") { Task { await store.registerHelper() } }
                    Button("检查") { Task { await store.refreshHelperStatus() } }
                    Button("审计") { Task { await store.auditHelper() } }
                    Button("修复") { Task { await store.repairHelperRegistration() } }
                    Button("卸载", role: .destructive) { confirmsHelperUninstall = true }
                }
            }
            SettingsRow("核心路径") {
                Text(store.effectiveMihomoPath.isEmpty ? "未设置" : store.effectiveMihomoPath)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            SettingsToggleRow("LaunchDaemon 托管核心", isOn: $draft.launchDaemonEnabled)
            SettingsRow("LaunchDaemon") {
                HStack {
                    Text(store.launchDaemonStatus).foregroundStyle(.secondary)
                    Spacer()
                    Button("安装") {
                        Task {
                            await store.saveSettings(draft)
                            await store.installLaunchDaemon()
                        }
                    }
                    Button("卸载", role: .destructive) { confirmsLaunchDaemonUninstall = true }
                }
            }
        }
    }

    private var deepLinkGroup: some View {
        SettingsSection(
            title: "深链导入",
            subtitle: "用于自动化安装 Profile 或覆写片段。调用前应确认来源可信。",
            systemImage: "link"
        ) {
            SettingsRow("Profile") {
                Text("mihomo://install-profile?url=https%3A%2F%2Fexample.com%2Fconfig.yaml&name=Work")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            SettingsRow("覆写") {
                Text("mihomo://install-fragment?kind=yaml&name=Patch&url=https%3A%2F%2Fexample.com%2Fpatch.yaml")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(store.advancedStatus).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("取消") { draft = store.settings }.disabled(draft == store.settings)
            Button("应用") { Task { await store.saveSettings(draft) } }
                .buttonStyle(.borderedProminent)
                .disabled(draft == store.settings)
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func synchronizeDraft(with settings: AppSettings, force: Bool) {
        if force || draft == lastSavedSettings {
            draft = settings
        }
        lastSavedSettings = settings
    }
}
