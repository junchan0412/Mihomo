import SwiftUI

struct NodeProviderWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var searchText: String
    @State private var nodeProviderEditor: NodeProviderEditorRoute?
    @State private var showingNodeProviderBatchImport = false
    @State private var nodeProviderGroupFilter = "全部"
    @State private var nodeProviderChangePreview: NodeProviderChangePreview?
    @State private var nodeProviderPreviewError = ""

    var body: some View {
        VStack(spacing: 0) {
            if let activeProfile = store.activeProfile {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("独立节点提供商")
                            .font(.headline)
                        Text("新增或关联后会同步到 \(activeProfile.name) 的 proxy-providers；远程刷新不会清空本地已关联的 Provider。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        nodeProviderEditor = .creating
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingNodeProviderBatchImport = true
                    } label: {
                        Label("批量导入", systemImage: "text.badge.plus")
                    }
                }
                .padding(14)

                HStack {
                    Text("筛选分组")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("筛选分组", selection: $nodeProviderGroupFilter) {
                        Text("全部").tag("全部")
                        ForEach(nodeProviderGroups, id: \.self) { group in
                            Text(group).tag(group)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer()
                    Text("\(filteredNodeProviders.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if let undoTitle = store.nodeProviderUndoTitle {
                    HStack(spacing: 8) {
                        Label("已应用\(undoTitle)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("撤销", systemImage: "arrow.uturn.backward") {
                            store.undoLastNodeProviderChange()
                        }
                        .help("撤销最近一次节点提供商变更")
                    }
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }

                if filteredNodeProviders.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "还没有节点提供商" : "没有匹配的节点提供商",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(searchText.isEmpty ? "添加订阅后，可为当前配置复选多个节点来源。" : "调整搜索条件后再试。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredNodeProviders) { provider in
                                NodeProviderRow(
                                    provider: provider,
                                    isSelected: provider.applies(to: activeProfile.id),
                                    toggleSelection: { selected in
                                        guard let updated = store.proposedNodeProviderSelection(provider, enabledFor: activeProfile, isSelected: selected) else { return }
                                        presentNodeProviderPreview(updated, title: selected ? "关联节点提供商" : "取消关联节点提供商")
                                    },
                                    refresh: { Task { await store.refreshNodeProvider(provider) } },
                                    edit: { nodeProviderEditor = .editing(provider) },
                                    delete: {
                                        presentNodeProviderPreview(store.nodeProviders.filter { $0.id != provider.id }, title: "删除节点提供商")
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 360, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("先选择配置", systemImage: "doc.badge.plus", description: Text("节点提供商可以独立保存，接入时需要指定一个 Profile。"))
                    .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ResourceWorkspaceLayoutMetrics.contentMinHeight, alignment: .topLeading)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(MihomoUI.cardStroke, lineWidth: 1) }
        .sheet(item: $nodeProviderEditor) { route in
            NodeProviderEditorSheet(
                provider: route.provider,
                save: { provider in
                    var provider = provider
                    if provider.profileIDs.isEmpty, let profileID = store.activeProfile?.id {
                        provider.profileIDs = [profileID]
                    }
                    var updated = store.nodeProviders
                    if let index = updated.firstIndex(where: { $0.id == provider.id }) {
                        updated[index] = provider
                    } else {
                        updated.append(provider)
                    }
                    presentNodeProviderPreview(updated, title: route.provider == nil ? "添加节点提供商" : "编辑节点提供商")
                    nodeProviderEditor = nil
                },
                cancel: { nodeProviderEditor = nil }
            )
        }
        .sheet(isPresented: $showingNodeProviderBatchImport) {
            if let profileID = store.activeProfile?.id {
                NodeProviderBatchImportSheet(profileID: profileID) { imported in
                    mergeImportedNodeProviders(imported)
                }
            }
        }
        .sheet(item: $nodeProviderChangePreview) { preview in
            NodeProviderChangePreviewSheet(
                preview: preview,
                apply: { applyNodeProviderPreview(preview) },
                cancel: { nodeProviderChangePreview = nil }
            )
        }
        .alert("无法生成节点提供商变更预览", isPresented: nodeProviderPreviewErrorBinding) {
            Button("好", role: .cancel) { nodeProviderPreviewError = "" }
        } message: {
            Text(nodeProviderPreviewError)
        }
    }

    private var filteredNodeProviders: [NodeProvider] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupFiltered = store.nodeProviders.filter {
            nodeProviderGroupFilter == "全部" || $0.group == nodeProviderGroupFilter
        }
        guard query.isEmpty == false else { return groupFiltered }
        return groupFiltered.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.url.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var nodeProviderGroups: [String] {
        Array(Set(store.nodeProviders.map(\.group))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func mergeImportedNodeProviders(_ imported: [NodeProvider]) {
        presentNodeProviderPreview(
            NodeProvider.canonicalized(store.nodeProviders + imported),
            title: "批量导入节点提供商"
        )
    }

    private var nodeProviderPreviewErrorBinding: Binding<Bool> {
        Binding(
            get: { nodeProviderPreviewError.isEmpty == false },
            set: { visible in
                if visible == false { nodeProviderPreviewError = "" }
            }
        )
    }

    private func presentNodeProviderPreview(_ updated: [NodeProvider], title: String) {
        do {
            nodeProviderChangePreview = try store.previewNodeProviderChange(updated, title: title)
        } catch {
            nodeProviderPreviewError = error.localizedDescription
        }
    }

    private func applyNodeProviderPreview(_ preview: NodeProviderChangePreview) -> Bool {
        do {
            try store.applyNodeProviderChange(preview)
            nodeProviderChangePreview = nil
            return true
        } catch {
            nodeProviderPreviewError = error.localizedDescription
            return false
        }
    }
}

private struct NodeProviderEditorRoute: Identifiable {
    var id: UUID
    var provider: NodeProvider?

    static var creating: Self { Self(id: UUID(), provider: nil) }
    static func editing(_ provider: NodeProvider) -> Self { Self(id: provider.id, provider: provider) }
}
