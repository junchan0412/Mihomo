import SwiftUI

struct ConfigFragmentEditorWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore

    let route: ConfigFragmentEditorRoute

    @State private var fragmentName = ""
    @State private var fragmentKind: ConfigFragmentKind = .yaml
    @State private var fragmentEnabled = true
    @State private var fragmentContent = ""
    @State private var fragmentAppliesGlobally = true
    @State private var fragmentProfileIDs: Set<UUID> = []
    @State private var hasLoaded = false

    private var selectedFragment: ConfigFragment? {
        guard let fragmentID = route.fragmentID else { return nil }
        return store.configFragments.first { $0.id == fragmentID }
    }

    private var isCreating: Bool { route.fragmentID == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metadataGrid
            scopePane
            contentPane
            validationPane
            actionBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(isCreating ? "新增覆写" : (selectedFragment?.name ?? "覆写编辑器"))
        .onAppear { loadSelectionIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isCreating ? "新增覆写" : "编辑覆写")
                    .font(.title3.bold())
                Text(isCreating ? "创建一个本地 YAML 或 JavaScript 覆写。" : "修改覆写内容、状态和生效范围。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let fragment = selectedFragment {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(fragment.source.title)
                        .font(.callout.weight(.medium))
                    Text(fragment.location.isEmpty ? "手动创建" : fragment.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 360, alignment: .trailing)
            }
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                fieldLabel("名称")
                TextField("覆写名称", text: $fragmentName)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                fieldLabel("类型")
                Picker("类型", selection: $fragmentKind) {
                    ForEach(ConfigFragmentKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
            }
            GridRow {
                fieldLabel("状态")
                Toggle("启用此覆写", isOn: $fragmentEnabled)
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var scopePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("作用范围", systemImage: "scope")
                .font(.headline)
            Picker("作用范围", selection: $fragmentAppliesGlobally) {
                Text("全部配置").tag(true)
                Text("指定配置").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            if fragmentAppliesGlobally == false {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.profiles) { profile in
                            Button {
                                toggleProfile(profile.id)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: fragmentProfileIDs.contains(profile.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(fragmentProfileIDs.contains(profile.id) ? Color.accentColor : Color.secondary)
                                    Text(profile.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(fragmentProfileIDs.contains(profile.id) ? "已选择" : "未选择")
                            if profile.id != store.profiles.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MihomoUI.cardStroke, lineWidth: 1)
                }
            }
        }
    }

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("内容")
                    .font(.headline)
                Spacer()
                Text(fragmentKind == .yaml ? "YAML 顶层映射" : "JavaScript transform(config)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lineCountLabel(fragmentContent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            YAMLHighlightTextEditor(text: $fragmentContent, showsLineNumbers: true)
                .frame(minHeight: 280)
                .accessibilityLabel("覆写内容")
        }
        .frame(maxHeight: .infinity)
    }

    private func lineCountLabel(_ content: String) -> String {
        let lines = max(content.components(separatedBy: .newlines).count, content.isEmpty ? 0 : 1)
        let chars = content.count
        return "\(lines) 行 · \(chars) 字符"
    }

    @ViewBuilder
    private var validationPane: some View {
        if let validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if selectedFragment?.isRemote == true {
            Label("这是远程覆写；手动保存的内容会在下次刷新 URL 时被替换。", systemImage: "arrow.clockwise.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("还原") { loadSelection() }
                .disabled(isCreating)
            Button(isCreating ? "添加覆写" : "保存覆写") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(saveDisabled)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .trailing)
    }

    private func loadSelectionIfNeeded() {
        guard hasLoaded == false else { return }
        hasLoaded = true
        loadSelection()
    }

    private func loadSelection() {
        guard let fragment = selectedFragment else {
            fragmentName = ""
            fragmentKind = .yaml
            fragmentEnabled = true
            fragmentContent = ""
            fragmentAppliesGlobally = true
            fragmentProfileIDs = []
            return
        }
        fragmentName = fragment.name
        fragmentKind = fragment.kind
        fragmentEnabled = fragment.enabled
        fragmentContent = fragment.content
        fragmentAppliesGlobally = fragment.appliesGlobally
        fragmentProfileIDs = Set(fragment.profileIDs)
    }

    private func toggleProfile(_ profileID: UUID) {
        if fragmentProfileIDs.contains(profileID) {
            fragmentProfileIDs.remove(profileID)
        } else {
            fragmentProfileIDs.insert(profileID)
        }
    }

    private func save() {
        guard validationMessage == nil else { return }
        let normalizedName = fragmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCreating {
            let fragment = ConfigFragment(
                name: normalizedName.isEmpty ? (fragmentKind == .yaml ? "YAML 片段" : "JS 片段") : normalizedName,
                kind: fragmentKind,
                enabled: fragmentEnabled,
                content: fragmentContent,
                appliesGlobally: fragmentAppliesGlobally,
                profileIDs: Array(fragmentProfileIDs),
                source: .local
            )
            store.addConfigFragment(fragment, undoManager: undoManager)
        } else if var fragment = selectedFragment {
            fragment.name = normalizedName.isEmpty ? fragment.name : normalizedName
            fragment.kind = fragmentKind
            fragment.enabled = fragmentEnabled
            fragment.content = fragmentContent
            fragment.appliesGlobally = fragmentAppliesGlobally
            fragment.profileIDs = Array(fragmentProfileIDs)
            store.updateConfigFragment(fragment, undoManager: undoManager)
        }
        dismiss()
    }

    private var validationMessage: String? {
        if fragmentAppliesGlobally == false && fragmentProfileIDs.isEmpty {
            return "指定配置模式下至少选择一个配置"
        }
        do {
            try store.configFragmentStore.validateFragmentContent(fragmentContent, kind: fragmentKind)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var saveDisabled: Bool {
        validationMessage != nil || (isCreating == false && selectedFragment == nil)
    }
}
