import AppKit
import SwiftUI

struct ConfigFragmentsEditorView: View {
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore
    @State private var selectedFragmentIDs: Set<UUID> = []
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var fragmentName = ""
    @State private var fragmentKind: ConfigFragmentKind = .yaml
    @State private var fragmentEnabled = true
    @State private var fragmentContent = ""
    @State private var fragmentAppliesGlobally = true
    @State private var fragmentProfileIDs: Set<UUID> = []
    @State private var isCreating = false
    @State private var confirmsDeletion = false

    private var selectedFragment: ConfigFragment? {
        guard selectedFragmentIDs.count == 1, let selectedFragmentID = selectedFragmentIDs.first else { return nil }
        return store.configFragments.first { $0.id == selectedFragmentID }
    }

    private var selectedFragments: [ConfigFragment] {
        store.configFragments.filter { selectedFragmentIDs.contains($0.id) }
    }

    private var visibleFragments: [ConfigFragment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.configFragments }
        return store.configFragments.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HSplitView {
            fragmentListPane
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)

            fragmentInformationPane
                .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索覆写")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .onAppear { ensureSelection() }
        .onChange(of: store.configFragments) { ensureSelection() }
        .onChange(of: selectedFragmentIDs) { loadSelection() }
        .confirmationDialog("删除所选覆写？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(selectedFragments.count) 个覆写", role: .destructive) {
                let fragments = selectedFragments
                selectedFragmentIDs.removeAll()
                store.deleteConfigFragments(fragments, undoManager: undoManager)
                ensureSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("覆写会从运行时配置链中移除。完成后可使用 Command-Z 撤销。")
        }
    }

    private var fragmentListPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("覆写列表")
                        .font(.headline)
                    Text("按顺序管理 YAML 与 JavaScript 覆写。")
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    beginCreating()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增覆写")
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("启用 YAML 覆写", isOn: overrideBinding(\.yamlOverrideEnabled))
                Toggle("启用 JS Transform", isOn: overrideBinding(\.jsOverrideEnabled))
            }
            .toggleStyle(.checkbox)
            .font(MihomoUI.Fonts.body)

            Divider()

            if store.configFragments.isEmpty {
                ContentUnavailableView("没有覆写", systemImage: "doc.badge.plus", description: Text("新增一个 YAML 或 JavaScript 覆写。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedFragmentIDs) {
                    ForEach(visibleFragments) { fragment in
                        ConfigFragmentListRow(fragment: fragment)
                            .tag(fragment.id)
                            .contextMenu {
                                Button(fragment.enabled ? "停用" : "启用") {
                                    toggle(fragment)
                                }
                                Button("复制内容") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(fragment.content, forType: .string)
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    selectedFragmentIDs = [fragment.id]
                                    requestDeleteSelection()
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Text("\(store.configFragments.count) 个覆写")
                Spacer()
                Text("\(store.configFragments.filter(\.enabled).count) 个启用")
            }
            .font(MihomoUI.Fonts.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var fragmentInformationPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("覆写信息")
                        .font(.headline)
                    Text(isCreating ? "创建新的覆写片段。" : "编辑选中覆写的状态、类型与内容。")
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let fragment = selectedFragment, isCreating == false {
                    Text(Formatters.shortDate.string(from: fragment.updatedAt))
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("名称")
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                    TextField("覆写名称", text: $fragmentName)
                }
                GridRow {
                    Text("类型")
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                    Picker("类型", selection: $fragmentKind) {
                        ForEach(ConfigFragmentKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                GridRow {
                    Text("状态")
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                    Toggle("启用此覆写", isOn: $fragmentEnabled)
                        .toggleStyle(.checkbox)
                }
            }
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 10) {
                Label("作用范围", systemImage: "scope")
                    .font(MihomoUI.Fonts.bodyMedium)
                Picker("作用范围", selection: $fragmentAppliesGlobally) {
                    Text("全部配置").tag(true)
                    Text("指定配置").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                if fragmentAppliesGlobally == false {
                    VStack(spacing: 0) {
                        ForEach(store.profiles) { profile in
                            Button {
                                if fragmentProfileIDs.contains(profile.id) {
                                    fragmentProfileIDs.remove(profile.id)
                                } else {
                                    fragmentProfileIDs.insert(profile.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: fragmentProfileIDs.contains(profile.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(fragmentProfileIDs.contains(profile.id) ? Color.accentColor : Color.secondary)
                                    Text(profile.name).lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            if profile.id != store.profiles.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 10)
                    .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("内容")
                        .font(MihomoUI.Fonts.bodyMedium)
                    Spacer()
                    Text(fragmentKind == .yaml ? "YAML 顶层映射" : "JavaScript transform(config)")
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $fragmentContent)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MihomoUI.cardStroke, lineWidth: 1)
                    }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if selectedFragment != nil && isCreating == false {
                    Button("删除", role: .destructive) {
                        requestDeleteSelection()
                    }
                }

                Spacer()

                Button("还原") {
                    loadSelection()
                }
                .disabled(selectedFragment == nil && isCreating == false)

                Button(isCreating ? "添加覆写" : "保存覆写") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
            }
        }
        .padding(18)
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

    private func ensureSelection() {
        if isCreating { return }
        selectedFragmentIDs.formIntersection(Set(store.configFragments.map(\.id)))
        if selectedFragmentIDs.isEmpty == false {
            return
        }
        if let firstID = visibleFragments.first?.id ?? store.configFragments.first?.id {
            selectedFragmentIDs = [firstID]
        }
        loadSelection()
    }

    private func loadSelection() {
        guard isCreating == false, let fragment = selectedFragment else {
            if isCreating == false {
                fragmentName = ""
                fragmentKind = .yaml
                fragmentEnabled = true
                fragmentContent = ""
                fragmentAppliesGlobally = true
                fragmentProfileIDs = []
            }
            return
        }
        fragmentName = fragment.name
        fragmentKind = fragment.kind
        fragmentEnabled = fragment.enabled
        fragmentContent = fragment.content
        fragmentAppliesGlobally = fragment.appliesGlobally
        fragmentProfileIDs = Set(fragment.profileIDs)
    }

    private func beginCreating() {
        isCreating = true
        selectedFragmentIDs.removeAll()
        fragmentName = ""
        fragmentKind = .yaml
        fragmentEnabled = true
        fragmentContent = ""
        fragmentAppliesGlobally = true
        fragmentProfileIDs = []
    }

    private func save() {
        let normalizedName = fragmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCreating {
            let created = ConfigFragment(
                name: normalizedName.isEmpty ? "YAML 片段" : normalizedName,
                kind: fragmentKind,
                enabled: fragmentEnabled,
                content: fragmentContent,
                appliesGlobally: fragmentAppliesGlobally,
                profileIDs: Array(fragmentProfileIDs)
            )
            store.addConfigFragment(created, undoManager: undoManager)
            selectedFragmentIDs = [created.id]
            isCreating = false
            return
        }
        guard var fragment = selectedFragment else { return }
        fragment.name = normalizedName.isEmpty ? fragment.name : normalizedName
        fragment.kind = fragmentKind
        fragment.enabled = fragmentEnabled
        fragment.content = fragmentContent
        fragment.appliesGlobally = fragmentAppliesGlobally
        fragment.profileIDs = Array(fragmentProfileIDs)
        store.updateConfigFragment(fragment, undoManager: undoManager)
    }

    private var saveDisabled: Bool {
        fragmentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (fragmentAppliesGlobally == false && fragmentProfileIDs.isEmpty)
    }

    private func requestDeleteSelection() {
        guard selectedFragments.isEmpty == false else { return }
        confirmsDeletion = true
    }

    private func toggle(_ fragment: ConfigFragment) {
        var updated = fragment
        updated.enabled.toggle()
        store.updateConfigFragment(updated, undoManager: undoManager)
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: store.refreshConfigArtifacts,
            activateSelection: searchIsFocused || selectedFragment == nil ? nil : loadSelection,
            previewSelection: searchIsFocused || selectedFragment == nil ? nil : loadSelection,
            deleteSelection: searchIsFocused || selectedFragments.isEmpty ? nil : requestDeleteSelection
        )
    }
}

private struct ConfigFragmentListRow: View {
    var fragment: ConfigFragment

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: fragment.kind == .yaml ? "doc.text" : "curlybraces")
                .foregroundStyle(fragment.enabled ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(fragment.name)
                    .lineLimit(1)
                Text("\(fragment.kind.title) · \(fragment.enabled ? "已启用" : "已停用") · \(scopeText)")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var scopeText: String {
        fragment.appliesGlobally ? "全局" : "\(fragment.profileIDs.count) 个配置"
    }
}
