import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(\.openWindow) private var openWindow
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
            SettingsRow("核心来源") {
                Picker("核心来源", selection: $draft.coreSource) {
                    ForEach(CoreSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }

            SettingsRow("来源说明") {
                Text(draft.coreSource.detail)
                    .foregroundStyle(.secondary)
            }

            SettingsRow("托管下载 URL") {
                HStack {
                    TextField("mihomo core 下载地址", text: $draft.managedCoreDownloadURL)
                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.installManagedCore()
                            draft = store.settings
                        }
                    } label: {
                        Label("更新", systemImage: "square.and.arrow.down")
                    }
                }
            }

            SettingsRow("托管下载 SHA-256") {
                TextField("必填；安装前校验下载包", text: $draft.managedCoreSHA256)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsRow("随包内置路径") {
                Text(ManagedCoreManager.bundledCorePath ?? "未随包提供")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            SettingsRow("本地可执行文件") {
                HStack {
                    TextField("路径", text: $draft.mihomoPath)
                    Button {
                        chooseMihomoBinary()
                    } label: {
                        Label("选择", systemImage: "folder")
                    }
                }
            }
            .disabled(draft.coreSource != .local)

            SettingsRow("保存后有效路径") {
                Text(effectiveDraftCorePath.isEmpty ? "未设置" : effectiveDraftCorePath)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            SettingsRow("托管状态") {
                HStack {
                    Text(store.managedCoreStatus)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        store.refreshManagedCoreStatus()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
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
        SettingsControllerPane(draft: $draft)
    }

    private var networkPane: some View {
        SettingsNetworkPane(draft: $draft)
    }

    private var routinePane: some View {
        SettingsRoutinePane(draft: $draft) {
            openWindow(id: "software-update")
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
            draft.coreSource = .local
        }
    }

    private var effectiveDraftCorePath: String {
        let localPath = draft.mihomoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.coreSource {
        case .managed:
            if FileManager.default.isExecutableFile(atPath: AppPaths.managedCoreFile.path) {
                return AppPaths.managedCoreFile.path
            }
            if let bundled = ManagedCoreManager.bundledCorePath,
               FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
            return localPath.isEmpty ? AppPaths.managedCoreFile.path : localPath
        case .bundled:
            return ManagedCoreManager.bundledCorePath ?? ""
        case .local:
            return localPath
        }
    }
}
