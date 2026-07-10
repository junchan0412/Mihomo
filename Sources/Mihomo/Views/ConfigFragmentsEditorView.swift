import SwiftUI

struct ConfigFragmentsEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedFragmentID: UUID?
    @State private var fragmentName = ""
    @State private var fragmentKind: ConfigFragmentKind = .yaml
    @State private var fragmentEnabled = true
    @State private var fragmentContent = ""
    @State private var isCreating = false

    private var selectedFragment: ConfigFragment? {
        guard let selectedFragmentID else { return nil }
        return store.configFragments.first { $0.id == selectedFragmentID }
    }

    var body: some View {
        HSplitView {
            fragmentListPane
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)

            fragmentInformationPane
                .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { ensureSelection() }
        .onChange(of: store.configFragments) { ensureSelection() }
        .onChange(of: selectedFragmentID) { loadSelection() }
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
                List(selection: $selectedFragmentID) {
                    ForEach(store.configFragments) { fragment in
                        ConfigFragmentListRow(fragment: fragment)
                            .tag(fragment.id)
                            .contextMenu {
                                Button(fragment.enabled ? "停用" : "启用") {
                                    toggle(fragment)
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    store.deleteConfigFragment(fragment)
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
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MihomoUI.cardStroke, lineWidth: 1)
                    }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if selectedFragment != nil && isCreating == false {
                    Button("删除", role: .destructive) {
                        deleteSelection()
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
                .disabled(fragmentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        if let selectedFragmentID, store.configFragments.contains(where: { $0.id == selectedFragmentID }) {
            return
        }
        selectedFragmentID = store.configFragments.first?.id
        loadSelection()
    }

    private func loadSelection() {
        guard isCreating == false, let fragment = selectedFragment else {
            if isCreating == false {
                fragmentName = ""
                fragmentKind = .yaml
                fragmentEnabled = true
                fragmentContent = ""
            }
            return
        }
        fragmentName = fragment.name
        fragmentKind = fragment.kind
        fragmentEnabled = fragment.enabled
        fragmentContent = fragment.content
    }

    private func beginCreating() {
        isCreating = true
        selectedFragmentID = nil
        fragmentName = ""
        fragmentKind = .yaml
        fragmentEnabled = true
        fragmentContent = ""
    }

    private func save() {
        let normalizedName = fragmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCreating {
            store.addConfigFragment(
                name: normalizedName,
                kind: fragmentKind,
                content: fragmentContent
            )
            if var created = store.configFragments.last {
                created.enabled = fragmentEnabled
                store.updateConfigFragment(created)
                selectedFragmentID = created.id
            }
            isCreating = false
            return
        }
        guard var fragment = selectedFragment else { return }
        fragment.name = normalizedName.isEmpty ? fragment.name : normalizedName
        fragment.kind = fragmentKind
        fragment.enabled = fragmentEnabled
        fragment.content = fragmentContent
        store.updateConfigFragment(fragment)
    }

    private func deleteSelection() {
        guard let fragment = selectedFragment else { return }
        store.deleteConfigFragment(fragment)
        selectedFragmentID = nil
        ensureSelection()
    }

    private func toggle(_ fragment: ConfigFragment) {
        var updated = fragment
        updated.enabled.toggle()
        store.updateConfigFragment(updated)
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
                Text("\(fragment.kind.title) · \(fragment.enabled ? "已启用" : "已停用")")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
