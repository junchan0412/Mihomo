import SwiftUI

struct ConfigFragmentsEditorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var fragmentName = ""
    @State private var fragmentKind: ConfigFragmentKind = .yaml
    @State private var fragmentContent = ""
    @State private var editingFragmentID: UUID?

    var body: some View {
        GroupBox("覆写片段") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Toggle("YAML 覆写", isOn: overrideBinding(\.yamlOverrideEnabled))
                    Toggle("JS Transform", isOn: overrideBinding(\.jsOverrideEnabled))
                    Spacer()
                    Button {
                        resetEditor()
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                    Button {
                        saveFragmentEditor()
                    } label: {
                        Label(editingFragmentID == nil ? "添加" : "保存", systemImage: editingFragmentID == nil ? "plus" : "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(fragmentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("名称")
                            .foregroundStyle(.secondary)
                        TextField("片段名称", text: $fragmentName)
                        Picker("类型", selection: $fragmentKind) {
                            ForEach(ConfigFragmentKind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
                .textFieldStyle(.roundedBorder)

                TextEditor(text: $fragmentContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 72)
                    .border(.quaternary)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if store.configFragments.isEmpty {
                            ContentUnavailableView("没有覆写片段", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 96)
                        } else {
                            ForEach(store.configFragments) { fragment in
                                fragmentRow(fragment)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func fragmentRow(_ fragment: ConfigFragment) -> some View {
        HStack(spacing: 12) {
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
                        .font(.callout.weight(.semibold))
                    Text("\(fragment.kind.title) · \(Formatters.shortDate.string(from: fragment.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            Text(fragment.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 360, alignment: .leading)

            Button {
                load(fragment)
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button(role: .destructive) {
                store.deleteConfigFragment(fragment)
                if editingFragmentID == fragment.id {
                    resetEditor()
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .padding(.vertical, 6)
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

    private func load(_ fragment: ConfigFragment) {
        editingFragmentID = fragment.id
        fragmentName = fragment.name
        fragmentKind = fragment.kind
        fragmentContent = fragment.content
    }

    private func resetEditor() {
        editingFragmentID = nil
        fragmentName = ""
        fragmentKind = .yaml
        fragmentContent = ""
    }

    private func saveFragmentEditor() {
        if let editingFragmentID,
           var fragment = store.configFragments.first(where: { $0.id == editingFragmentID }) {
            fragment.name = fragmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fragment.name : fragmentName
            fragment.kind = fragmentKind
            fragment.content = fragmentContent
            store.updateConfigFragment(fragment)
        } else {
            store.addConfigFragment(name: fragmentName, kind: fragmentKind, content: fragmentContent)
        }
        resetEditor()
    }
}
