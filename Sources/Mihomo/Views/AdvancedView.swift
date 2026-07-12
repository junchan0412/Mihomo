import SwiftUI

private enum AdvancedWorkspaceTab: String, CaseIterable, Identifiable {
    case runtime
    case data
    case backup
    case inspection

    var id: String { rawValue }
    var title: String {
        switch self {
        case .runtime: return "运行工具"
        case .data: return "数据与界面"
        case .backup: return "备份与安全"
        case .inspection: return "配置检查"
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
    @State private var tab: AdvancedWorkspaceTab = .runtime

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
                        AdvancedExternalUIGroup(draft: $draft)
                        AdvancedGeoGroup(draft: $draft)
                    case .backup:
                        AdvancedProfileEncryptionGroup(draft: $draft)
                        AdvancedBackupGroup(draft: $draft)
                    case .inspection:
                        diagnosticsGroup
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
        .onAppear {
            draft = store.settings
            store.refreshConfigArtifacts()
        }
        .onReceive(store.$settings) { draft = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("高级工具").font(MihomoUI.Fonts.pageTitle)
                    Text("安装、维护、备份与排障工具。日常网络与运行设置不在此重复。")
                        .font(MihomoUI.Fonts.pageSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.runDiagnostics() } } label: {
                    Label("运行诊断", systemImage: "stethoscope")
                }
            }
            Picker("工具分类", selection: $tab) {
                ForEach(AdvancedWorkspaceTab.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 650)
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, 14)
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
                    Button("卸载", role: .destructive) { Task { await store.unregisterHelper() } }
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
                    Button("卸载", role: .destructive) { Task { await store.uninstallLaunchDaemon() } }
                }
            }
        }
    }

    private var diagnosticsGroup: some View {
        SettingsSection(
            title: "诊断与导出",
            subtitle: "检查运行环境、配置与权限状态，必要时导出诊断包。",
            systemImage: "stethoscope"
        ) {
            SettingsRow("状态") {
                Text(store.advancedStatus).foregroundStyle(.secondary).textSelection(.enabled)
            }
            SettingsRow("操作") {
                HStack {
                    Button("运行诊断") { Task { await store.runDiagnostics() } }
                    Button("导出诊断包") { store.exportDiagnosticBundle() }
                    Button("刷新配置预览") { store.refreshConfigArtifacts() }
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
}
