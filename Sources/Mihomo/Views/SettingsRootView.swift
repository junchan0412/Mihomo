import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default
    @State private var tab: SettingsTab = .general
    @AppStorage("menuBar.showTrafficRates") private var showsMenuBarTrafficRates = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .general: generalPane
                    case .remoteAccess: SettingsRemoteAccessPane(draft: $draft)
                    case .advanced: SettingsAdvancedPane(draft: $draft)
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, MihomoUI.pageHorizontalPadding)
                .padding(.vertical, MihomoUI.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .frame(minWidth: 760, minHeight: 600)
        .navigationTitle("设置")
        .onAppear { draft = store.settings }
        .onReceive(store.$settings) { draft = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置").font(MihomoUI.Fonts.pageTitle)
                    Text("常用选项保持清晰可见，维护与排障操作集中在高级工具。")
                        .font(MihomoUI.Fonts.pageSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Picker("设置分类", selection: $tab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
            HStack(spacing: 16) {
                Label(store.settings.autoStartCore ? "自动启动" : "手动启动", systemImage: "power")
                Label(store.settings.autoRefreshProfiles ? "订阅自动刷新" : "订阅手动刷新", systemImage: "clock.arrow.circlepath")
                Label(store.settings.launchAtLogin ? "登录项已启用" : "登录项未启用", systemImage: "person.crop.circle.badge.clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, 14)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "核心", subtitle: "选择 mihomo 来源，并控制应用启动与异常恢复。", systemImage: "cpu") {
                SettingsRow("核心来源") {
                    Picker("核心来源", selection: $draft.coreSource) {
                        ForEach(CoreSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }
                SettingsRow("本地可执行文件") {
                    HStack {
                        TextField("路径", text: $draft.mihomoPath)
                        Button("选择") { chooseMihomoBinary() }
                    }
                }
                .disabled(draft.coreSource != .local)
                SettingsRow("有效路径") {
                    Text(effectiveDraftCorePath.isEmpty ? "未设置" : effectiveDraftCorePath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                SettingsToggleRow("打开后自动启动核心", isOn: $draft.autoStartCore)
                SettingsToggleRow("异常退出后自动恢复", isOn: $draft.restartCoreOnCrash)
                SettingsRow("恢复次数上限") {
                    TextField("3", value: $draft.maxCrashRestarts, format: .number).frame(width: 140)
                }
            }

            SettingsSection(title: "订阅与常驻", subtitle: "控制远程配置刷新、登录项与轻量启动。", systemImage: "clock.arrow.circlepath") {
                SettingsToggleRow("自动刷新远程订阅", isOn: $draft.autoRefreshProfiles)
                SettingsRow("刷新间隔（小时）") {
                    TextField("24", value: $draft.profileRefreshIntervalHours, format: .number).frame(width: 140)
                }
                SettingsRow("刷新并发数") {
                    TextField("2", value: $draft.profileRefreshMaxConcurrent, format: .number).frame(width: 140)
                }
                SettingsRow("资源更新并发数") {
                    Stepper(value: $draft.resourceUpdateMaxConcurrent, in: 1...12) {
                        Text("\(draft.resourceUpdateMaxConcurrent)").monospacedDigit().frame(width: 32)
                    }
                }
                SettingsToggleRow("登录后自动打开 Mihomo", isOn: $draft.launchAtLogin)
                SettingsToggleRow("轻量模式启动", isOn: $draft.lightweightMode)
                SettingsToggleRow("菜单栏显示上传下载速率", isOn: $showsMenuBarTrafficRates)
                SettingsRow("登录项状态") { Text(store.loginItemStatus).foregroundStyle(.secondary) }
            }

            SettingsSection(title: "日志", subtitle: "限制本地日志体积，减少长期运行时的磁盘与内存压力。", systemImage: "text.alignleft") {
                SettingsRow("日志等级") {
                    Picker("日志等级", selection: $draft.logLevel) {
                        Text("调试").tag("debug")
                        Text("信息").tag("info")
                        Text("警告").tag("warning")
                        Text("错误").tag("error")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                SettingsRow("保留天数") {
                    TextField("7", value: $draft.logRetentionDays, format: .number).frame(width: 140)
                }
                SettingsRow("单文件大小（MB）") {
                    TextField("8", value: $draft.logMaxFileSizeMB, format: .number).frame(width: 140)
                }
            }

            SettingsSoftwareUpdatePane { openWindow(id: "software-update") }
        }
    }

    private var footer: some View {
        HStack {
            Text(draft == store.settings ? "所有更改已应用" : "有尚未应用的更改")
                .foregroundStyle(.secondary)
            Spacer()
            Button("取消") { draft = store.settings }
                .keyboardShortcut(.cancelAction)
                .disabled(draft == store.settings)
            Button("应用") { Task { await store.saveSettings(draft) } }
                .keyboardShortcut(.defaultAction)
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
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.mihomoPath = url.path
            draft.coreSource = .local
        }
    }

    private var effectiveDraftCorePath: String {
        let localPath = draft.mihomoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.coreSource {
        case .managed:
            if FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path) { return AppPaths.managedCoreFile.path }
            if let bundled = ManagedCoreManager.bundledCorePath,
               FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
            return localPath.isEmpty ? AppPaths.managedCoreFile.path : localPath
        case .bundled: return ManagedCoreManager.bundledCorePath ?? ""
        case .local: return localPath
        }
    }
}
