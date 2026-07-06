import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    @State private var selectedProfileID: UUID?
    @State private var isDropTargeted = false
    @State private var showingRemoteImport = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                storagePane
                ProfileRefreshQueueStrip()
                    .environmentObject(store)
                profileTablePane
                detailPane
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("配置")
        .overlay {
            DropTargetOverlay(isTargeted: isDropTargeted)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
        }
        .onChange(of: store.profiles) {
            if selectedProfileID == nil || store.profiles.contains(where: { $0.id == selectedProfileID }) == false {
                selectedProfileID = store.settings.activeProfileID ?? store.profiles.first?.id
            }
        }
        .sheet(isPresented: $showingRemoteImport) {
            RemoteProfileImportSheet()
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置")
                    .font(.title2.bold())
                Text("管理本地配置、远程订阅与运行时覆写。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var storagePane: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("配置存储路径")
                .font(.headline)
                .frame(width: 110, alignment: .trailing)

            Text(store.profileStorageDirectory.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button {
                store.revealProfileStorageDirectory()
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }

            Button {
                chooseProfileStorageDirectory()
            } label: {
                Label("修改路径", systemImage: "folder.badge.gearshape")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }

    private var profileTablePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置列表")
                    .font(.headline)
                Spacer()
                Text("\(store.profiles.count) 个配置")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AppKitTable(
                rows: store.profiles,
                selection: $selectedProfileID,
                columns: profileColumns,
                hasHorizontalScroller: false
            )
            .overlay {
                if store.profiles.isEmpty {
                    ContentUnavailableView("没有配置", systemImage: "doc.text")
                }
            }
            .frame(minHeight: 280, maxHeight: .infinity)

            HStack(spacing: 10) {
                Button {
                    if let selectedProfile {
                        Task { await store.setActiveProfile(selectedProfile) }
                    }
                } label: {
                    Label("启用", systemImage: "checkmark.circle")
                }
                .disabled(selectedProfile == nil)

                Button {
                    openProfileEditor()
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(selectedProfile == nil)

                Button {
                    if let selectedProfile {
                        Task { await store.refreshProfile(selectedProfile) }
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(selectedProfile?.isRemote != true)

                Button {
                    Task { await store.refreshAllRemoteProfiles() }
                } label: {
                    Label("刷新订阅", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    importLocal()
                } label: {
                    Label("导入...", systemImage: "square.and.arrow.down")
                }

                Button {
                    showingRemoteImport = true
                } label: {
                    Label("从 URL 安装配置...", systemImage: "link.badge.plus")
                }

                Spacer()

                Button {
                    openWindow(id: "fragments-editor")
                } label: {
                    Label("覆写", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    deleteSelectedProfile()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedProfile == nil || store.profiles.count <= 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ProfileSummaryPane(
                    profile: selectedProfile,
                    stats: selectedProfile.map { store.profileStats(for: $0) },
                    editProfile: openProfileEditor
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                ConfigFragmentsSummaryView {
                    openWindow(id: "fragments-editor")
                }
                .environmentObject(store)
                .frame(width: 340, alignment: .topLeading)
            }

            ProfileQualityPane(report: store.profileQualityReport(for: selectedProfile))
        }
        .frame(minHeight: 330, alignment: .topLeading)
    }

    private var selectedProfile: ProfileItem? {
        guard let selectedProfileID else { return nil }
        return store.profiles.first { $0.id == selectedProfileID }
    }

    private var profileColumns: [AppKitTableColumn<ProfileItem>] {
        [
            .init(title: "状态", width: 72) { profile in
                profile.id == store.settings.activeProfileID ? "启用" : "-"
            },
            .init(title: "名称", width: 260) { $0.name },
            .init(title: "类型", width: 80) { $0.source == .remote ? "远程" : "本地" },
            .init(title: "来源", width: 320) { profile in
                profile.source == .remote ? profile.location : profile.fileName
            },
            .init(title: "更新", width: 140) { Formatters.shortDate.string(from: $0.updatedAt) }
        ]
    }

    private func openProfileEditor() {
        guard let selectedProfileID else { return }
        store.profileEditorProfileID = selectedProfileID
        openWindow(id: "profile-editor")
    }

    private func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        Task { await store.deleteProfile(selectedProfile) }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importLocalProfile(url: url) }
        }
    }

    private func chooseProfileStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择配置存储路径"
        panel.message = "选择用于保存配置 YAML 文件的目录。现有配置会复制到新目录。"
        panel.prompt = "使用此目录"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.profileStorageDirectory

        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.changeProfileStorageDirectory(to: url) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { await store.importLocalProfile(url: url) }
            }
        }
        return accepted
    }
}

private struct RemoteProfileImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("从 URL 导入配置")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("名称")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                    TextField("可选", text: $store.newRemoteName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("URL")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                    TextField("https://example.com/profile.yaml", text: $store.newRemoteURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button {
                    Task {
                        await store.addRemoteProfile()
                        dismiss()
                    }
                } label: {
                    Label("导入", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private struct ProfileRefreshQueueStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Label(store.profileAutoRefreshStatus, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if store.profileRefreshFailureCount > 0 {
                Label("\(store.profileRefreshFailureCount) 个失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            if let job = store.profileRefreshQueue.first {
                Text("\(job.profileName)：\(job.state.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProfileSummaryPane: View {
    var profile: ProfileItem?
    var stats: ProfileStats?
    var editProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(profile?.name ?? "未选择配置", systemImage: "doc.text")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    editProfile()
                } label: {
                    Label("打开编辑器", systemImage: "square.and.pencil")
                }
                .disabled(profile == nil)
            }

            if profile == nil {
                Text("选择一个配置后查看规则、策略组、节点和 Provider 统计。")
                    .foregroundStyle(.secondary)
            } else if let error = stats?.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ProfileMetric(title: "规则", value: "\(stats?.ruleCount ?? 0)")
                    ProfileMetric(title: "策略组", value: "\(stats?.policyGroupCount ?? 0)")
                    ProfileMetric(title: "节点", value: "\(stats?.proxyCount ?? 0)")
                    ProfileMetric(title: "Provider", value: "\(statsProviderCount)")
                }

                HStack(spacing: 14) {
                    ProfileSmallFact(title: "类型", value: profile?.source == .remote ? "远程" : "本地")
                    ProfileSmallFact(title: "行数", value: "\(stats?.lineCount ?? 0)")
                    ProfileSmallFact(title: "大小", value: Formatters.bytes(Int64(stats?.fileSize ?? 0)))
                    ProfileSmallFact(title: "更新", value: profile.map { Formatters.shortDate.string(from: $0.updatedAt) } ?? "-")
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statsProviderCount: Int {
        (stats?.proxyProviderCount ?? 0) + (stats?.ruleProviderCount ?? 0)
    }
}

private struct ProfileMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct ProfileQualityPane: View {
    var report: ProfileQualityReport

    private var topIssues: [ProfileQualityIssue] {
        Array(report.issues.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("配置质量")
                    .font(.headline)
                Text("\(report.score)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(scoreColor)
                Text(report.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("问题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if topIssues.isEmpty {
                        Label("未发现阻断项", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(topIssues) { issue in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: icon(for: issue.severity))
                                    .foregroundStyle(color(for: issue.severity))
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.title)
                                        .lineLimit(1)
                                    Text(issue.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Runtime Inspector")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(report.runtimeItems.prefix(8)) { item in
                            RuntimeInspectorCell(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("分层 Diff")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(report.diffLayers) { layer in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(layer.changed ? Color.accentColor : Color.secondary.opacity(0.35))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(layer.name)
                                    .lineLimit(1)
                                Text(layer.summary.isEmpty ? "-" : layer.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if let migration = report.migrationLog.last {
                        Divider()
                        Text(migration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }

    private var scoreColor: Color {
        if report.score >= 90 { return .green }
        if report.score >= 70 { return .orange }
        return .red
    }

    private func icon(for severity: ProfileQualitySeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: ProfileQualitySeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private struct RuntimeInspectorCell: View {
    var item: RuntimeInspectorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(item.value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileSmallFact: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConfigFragmentsSummaryView: View {
    @EnvironmentObject private var store: AppStore
    var openEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("覆写")
                    .font(.headline)
                Spacer()
                Button {
                    openEditor()
                } label: {
                    Label("管理", systemImage: "slider.horizontal.3")
                }
            }

            Toggle("YAML 覆写", isOn: overrideBinding(\.yamlOverrideEnabled))
                .toggleStyle(.checkbox)
            Toggle("JS Transform", isOn: overrideBinding(\.jsOverrideEnabled))
                .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                ProfileSmallFact(title: "片段", value: "\(store.configFragments.count)")
                ProfileSmallFact(title: "已启用", value: "\(store.configFragments.filter(\.enabled).count)")
                ProfileSmallFact(title: "禁用规则", value: "\(store.disabledRules.count)")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func overrideBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { enabled in
                var updated = store.settings
                updated[keyPath: keyPath] = enabled
                Task { await store.saveSettings(updated) }
            }
        )
    }
}

private struct DropTargetOverlay: View {
    var isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                .padding(12)
        }
    }
}

private extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? .text
}
