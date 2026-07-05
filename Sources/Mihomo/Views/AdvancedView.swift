import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default
    @State private var fragmentName = ""
    @State private var fragmentKind: ConfigFragmentKind = .yaml
    @State private var fragmentContent = ""
    @State private var editingFragment: ConfigFragment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                coreGroup
                profileEncryptionGroup
                softwareUpdateGroup
                controllerGroup
                dnsGroup
                snifferGroup
                externalUIGroup
                fragmentsGroup
                previewGroup
                geoGroup
                backupGroup
                deepLinkGroup
            }
            .padding(24)
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
            .padding([.horizontal, .bottom], 24)
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
                    .font(.largeTitle.bold())
                Text("Core、远程 API、DNS、Sniffer、覆写、备份与导入。")
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
        GroupBox("Core 与 LaunchDaemon") {
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

                Toggle("使用托管/内置 mihomo core", isOn: $draft.managedCoreEnabled)
                TextField("Core 下载 URL", text: $draft.managedCoreDownloadURL)
                LabeledContent("当前有效路径") {
                    Text(store.effectiveMihomoPath.isEmpty ? "未设置" : store.effectiveMihomoPath)
                        .textSelection(.enabled)
                }
                LabeledContent("托管状态") {
                    Text(store.managedCoreStatus)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.installManagedCore()
                        }
                    } label: {
                        Label("更新 Core", systemImage: "square.and.arrow.down")
                    }

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
        GroupBox("远程 HTTP API") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("显式启用远程访问", isOn: $draft.remoteAPIEnabled)
                    TextField("绑定地址", text: $draft.remoteAPIBindAddress)
                }
                GridRow {
                    Text("Controller Host")
                    TextField("127.0.0.1", text: $draft.controllerHost)
                }
                GridRow {
                    Text("Controller 端口")
                    TextField("9090", value: $draft.controllerPort, format: .number)
                }
                GridRow {
                    Text("Secret")
                    SecureField("Bearer token", text: $draft.controllerSecret)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var softwareUpdateGroup: some View {
        GroupBox("软件更新") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Manifest URL")
                    TextField("https://example.com/mihomo-update.json", text: $draft.softwareUpdateManifestURL)
                }
                GridRow {
                    Text("状态")
                    HStack {
                        Text(store.softwareUpdateStatus)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            Task {
                                await store.saveSettings(draft)
                                await store.checkForSoftwareUpdate()
                            }
                        } label: {
                            Label("检查", systemImage: "arrow.clockwise")
                        }

                        Button {
                            Task {
                                await store.saveSettings(draft)
                                await store.installSoftwareUpdate()
                            }
                        } label: {
                            Label("安装更新", systemImage: "square.and.arrow.down")
                        }
                        .disabled(store.availableUpdate == nil)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var profileEncryptionGroup: some View {
        GroupBox("Profile 加密") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("使用 Age 加密本地 Profile YAML", isOn: $draft.profileEncryptionEnabled)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Age 下载 URL")
                        TextField("age darwin arm64 tar.gz", text: $draft.ageDownloadURL)
                    }
                    GridRow {
                        Text("age")
                        TextField("age 可执行文件路径", text: $draft.ageBinaryPath)
                    }
                    GridRow {
                        Text("age-keygen")
                        TextField("age-keygen 可执行文件路径", text: $draft.ageKeygenPath)
                    }
                    GridRow {
                        Text("Identity")
                        TextField(AppPaths.ageIdentityFile.path, text: $draft.ageIdentityPath)
                    }
                    GridRow {
                        Text("Recipient")
                        TextField("age1...", text: $draft.ageRecipient)
                    }
                    GridRow {
                        Text("状态")
                        Text(store.ageStatus)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        Task {
                            await store.installAgeTools(downloadURL: draft.ageDownloadURL)
                            draft = store.settings
                        }
                    } label: {
                        Label("安装 Age", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        Task {
                            await store.generateAgeIdentity(draftSettings: draft)
                            draft = store.settings
                        }
                    } label: {
                        Label("生成身份", systemImage: "key")
                    }

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.migrateProfileEncryptionNow()
                        }
                    } label: {
                        Label(draft.profileEncryptionEnabled ? "加密现有 Profile" : "解密现有 Profile", systemImage: "lock.rotation")
                    }
                }
            }
            .padding(.vertical, 4)
        }
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
        GroupBox("外部 UI") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Toggle("写入 external-ui", isOn: $draft.externalUIEnabled)
                    TextField("名称", text: $draft.externalUIName)
                }
                GridRow {
                    Text("下载 URL")
                    TextField("zashboard/metacubexd zip", text: $draft.externalUIDownloadURL)
                }
                GridRow {
                    Text("状态")
                    HStack {
                        Text(store.externalUIStatus)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            Task {
                                await store.saveSettings(draft)
                                await store.installExternalUI()
                            }
                        } label: {
                            Label("安装 UI", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var fragmentsGroup: some View {
        GroupBox("覆写片段") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("YAML 覆写", isOn: $draft.yamlOverrideEnabled)
                    Toggle("JS Transform", isOn: $draft.jsOverrideEnabled)
                    Spacer()
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        TextField("片段名称", text: $fragmentName)
                        Picker("类型", selection: $fragmentKind) {
                            ForEach(ConfigFragmentKind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button {
                            saveFragmentEditor()
                        } label: {
                            Label(editingFragment == nil ? "添加" : "保存片段", systemImage: "plus")
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)

                TextEditor(text: $fragmentContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(.quaternary)

                ForEach(store.configFragments) { fragment in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { fragment.enabled },
                            set: { enabled in
                                var updated = fragment
                                updated.enabled = enabled
                                store.updateConfigFragment(updated)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fragment.name)
                                    .font(.headline)
                                Text("\(fragment.kind.title) · \(Formatters.shortDate.string(from: fragment.updatedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button {
                            editingFragment = fragment
                            fragmentName = fragment.name
                            fragmentKind = fragment.kind
                            fragmentContent = fragment.content
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            store.deleteConfigFragment(fragment)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var previewGroup: some View {
        GroupBox("配置预览 / Diff") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        store.refreshConfigArtifacts()
                    } label: {
                        Label("刷新预览", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Text("\(store.configPreview.split(separator: "\n").count) 行")
                        .foregroundStyle(.secondary)
                }

                HSplitView {
                    TextEditor(text: .constant(store.configPreview))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 260)
                    TextEditor(text: .constant(store.configDiff))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 260)
                }
                .frame(minHeight: 280)
            }
            .padding(.vertical, 4)
        }
    }

    private var geoGroup: some View {
        GroupBox("Geo 数据") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("GeoIP")
                    TextField("geoip.dat URL", text: $draft.geoIPURL)
                }
                GridRow {
                    Text("GeoSite")
                    TextField("geosite.dat URL", text: $draft.geoSiteURL)
                }
                GridRow {
                    Text("状态")
                    HStack {
                        Text(store.geoUpdateStatus)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task {
                                await store.saveSettings(draft)
                                await store.updateGeoData()
                            }
                        } label: {
                            Label("更新 Geo", systemImage: "globe")
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        }
    }

    private var backupGroup: some View {
        GroupBox("备份 / 同步") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("WebDAV URL")
                        TextField("https://dav.example.com/Mihomo.zip", text: $draft.backupWebDAVURL)
                    }
                    GridRow {
                        Text("WebDAV 用户")
                        TextField("username", text: $draft.backupWebDAVUsername)
                    }
                    GridRow {
                        Text("WebDAV 密码")
                        SecureField("password", text: $draft.backupWebDAVPassword)
                    }
                    GridRow {
                        Text("Gist Token")
                        SecureField("token", text: $draft.gistToken)
                    }
                    GridRow {
                        Text("Gist ID")
                        TextField("可为空", text: $draft.gistID)
                    }
                }
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        store.createLocalBackup()
                    } label: {
                        Label("本地备份", systemImage: "archivebox")
                    }

                    Button {
                        restoreLocalBackup()
                    } label: {
                        Label("本地恢复", systemImage: "arrow.down.doc")
                    }

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.uploadWebDAVBackup()
                        }
                    } label: {
                        Label("上传 WebDAV", systemImage: "icloud.and.arrow.up")
                    }

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.restoreWebDAVBackup()
                        }
                    } label: {
                        Label("恢复 WebDAV", systemImage: "icloud.and.arrow.down")
                    }

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.uploadGistBackup()
                        }
                    } label: {
                        Label("同步 Gist", systemImage: "curlybraces")
                    }

                    Button {
                        Task {
                            await store.saveSettings(draft)
                            await store.restoreGistBackup()
                        }
                    } label: {
                        Label("恢复 Gist", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Text(store.backupStatus)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
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

    private func saveFragmentEditor() {
        if var editingFragment {
            editingFragment.name = fragmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? editingFragment.name : fragmentName
            editingFragment.kind = fragmentKind
            editingFragment.content = fragmentContent
            store.updateConfigFragment(editingFragment)
            self.editingFragment = nil
        } else {
            store.addConfigFragment(name: fragmentName, kind: fragmentKind, content: fragmentContent)
        }
        fragmentName = ""
        fragmentContent = ""
        fragmentKind = .yaml
    }

    private func restoreLocalBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件"
        panel.allowedContentTypes = [.zipArchive]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.restoreLocalBackup(url: url) }
        }
    }
}

private extension UTType {
    static let zipArchive = UTType(filenameExtension: "zip") ?? .data
}
