import SwiftUI

struct PoliciesView: View {
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore
    @State private var selectedGroupID: String?
    @State private var selectedNodeID: String?
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var pendingAutomaticOverride: PolicyNodeRow?
    @State private var showingGroupEditor = false
    @State private var showingGroupDetail = false
    @State private var expandedProviderIDs: Set<String> = []
    @State private var groupEditorContent = ""
    @State private var expandedGroupIDs: Set<String> = []
    @State private var hideUnavailableNodes = false
    @State private var showHiddenGroups = false

    private var displayGroups: [ProxyGroup] {
        store.proxyGroups.isEmpty ? store.offlineProxyGroups : store.proxyGroups
    }

    private var isOfflinePolicyMode: Bool {
        store.proxyGroups.isEmpty && store.offlineProxyGroups.isEmpty == false
    }

    private var visibleGroups: [ProxyGroup] {
        let groups = displayGroups.filter { showHiddenGroups || !$0.hidden }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return groups }
        return groups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || group.now.localizedCaseInsensitiveContains(query)
                || group.type.localizedCaseInsensitiveContains(query)
                || group.all.contains { node in
                    node.name.localizedCaseInsensitiveContains(query)
                        || node.type.localizedCaseInsensitiveContains(query)
                }
        }
    }

    private var selectedGroup: ProxyGroup? {
        if let selectedGroupID,
           let group = visibleGroups.first(where: { $0.id == selectedGroupID }) {
            return group
        }
        return visibleGroups.first
    }

    private var nodeRows: [PolicyNodeRow] {
        guard let selectedGroup else { return [] }
        return nodes(for: selectedGroup)
    }

    private var selectedNodeRow: PolicyNodeRow? {
        guard let selectedNodeID else { return nil }
        return nodeRows.first { $0.id == selectedNodeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            mainContent
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("策略")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索策略组或节点")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .onAppear {
            if store.offlineProxyGroups.isEmpty {
                store.refreshConfigArtifacts()
            }
            ensureSelection()
            Task { await store.preloadPolicyGroupIcons(for: displayGroups) }
        }
        .onChange(of: store.proxyGroups) {
            ensureSelection()
            Task { await store.preloadPolicyGroupIcons(for: displayGroups) }
        }
        .onChange(of: store.offlineProxyGroups) {
            ensureSelection()
            Task { await store.preloadPolicyGroupIcons(for: displayGroups) }
        }
        .onChange(of: searchText) {
            ensureSelection()
        }
        .onChange(of: selectedGroupID) {
            guard let selectedGroup else {
                selectedNodeID = nil
                return
            }
            ensureNodeSelection(in: selectedGroup)
        }
        .alert(
            "覆盖自动测速选择？",
            isPresented: automaticOverrideBinding,
            presenting: pendingAutomaticOverride
        ) { row in
            Button("取消", role: .cancel) {
                pendingAutomaticOverride = nil
            }
            Button("覆盖", role: .destructive) {
                selectNode(row)
                pendingAutomaticOverride = nil
            }
        } message: { row in
            Text("\(row.group.name) 是自动测速策略组。手动选择会覆盖当前自动测速结果，关闭代理或重启核心后恢复自动选择。")
        }
        .sheet(isPresented: $showingGroupEditor, onDismiss: {
            store.refreshConfigArtifacts()
        }) {
            PolicyGroupEditorSheet(
                profileName: store.activeProfile?.name ?? "当前配置",
                content: $groupEditorContent,
                cancel: { showingGroupEditor = false },
                save: savePolicyGroups
            )
            .environmentObject(store)
            .frame(minWidth: 900, minHeight: 620)
        }
        .sheet(isPresented: $showingGroupDetail) {
            if let selectedGroup {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selectedGroup.name).font(.title2.weight(.semibold))
                    Text("\(selectedGroup.type) · \(selectedGroup.all.count) 个候选").foregroundStyle(.secondary)
                    ScrollView {
                        PolicyNodeCardGrid(rows: nodeRows, isOffline: isOfflinePolicyMode, selectedNodeID: $selectedNodeID, activate: handleNodeDoubleClick)
                    }
                }
                .padding(24).frame(minWidth: 620, minHeight: 480, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if displayGroups.isEmpty {
            PolicyStartupEmptyState(
                isCoreRunning: store.isCoreRunning,
                coreStatus: store.coreStatus,
                activeProfileName: store.activeProfile?.name,
                tunEnabled: store.settings.tunEnabled,
                startOrRestartCore: {
                    Task {
                        if store.isCoreRunning {
                            await store.restartCore()
                        } else {
                            await store.startCore()
                        }
                    }
                },
                refreshController: {
                    Task { await store.refreshController() }
                },
                openProfiles: {
                    store.selectedSection = .profiles
                },
                toggleTun: {
                    Task { await store.setTunEnabled(!store.settings.tunEnabled) }
                }
            )
        } else if visibleGroups.isEmpty {
            PolicySearchEmptyState(query: searchText) {
                searchText = ""
            }
        } else {
            content
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("策略")
                    .font(MihomoUI.Fonts.pageTitle)
                Text(isOfflinePolicyMode ? "离线预览策略组结构；启动核心后可切换节点与测速。" : "管理 Proxy Provider、策略组与当前节点。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                policySummaryStrip
            }

            Spacer()

            Button {
                toggleAllGroups()
            } label: {
                Image(systemName: allGroupsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help(allGroupsExpanded ? "折叠全部策略组" : "展开全部策略组")
            .disabled(visibleGroups.isEmpty)

            Button {
                Task { await store.testAllProxyDelays() }
            } label: {
                Image(systemName: "speedometer")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help("一键延迟测试")
            .disabled(store.proxyGroups.isEmpty)

            Menu {
                Toggle("隐藏不可用的节点", isOn: $hideUnavailableNodes)
                Toggle("显示隐藏的策略组", isOn: $showHiddenGroups)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .fixedSize()
            .help("筛选策略和节点")
        }
    }

    private var policySummaryStrip: some View {
        HStack(spacing: 8) {
            summaryChip(title: "策略组", value: "\(visibleGroups.count)", tint: .blue)
            summaryChip(title: "节点", value: "\(visibleGroups.reduce(0) { $0 + $1.all.count })", tint: .purple)
            summaryChip(title: "Provider", value: "\(store.providers.filter { $0.kind.caseInsensitiveCompare("Proxy") == .orderedSame }.count)", tint: .cyan)
            if isOfflinePolicyMode {
                summaryChip(title: "模式", value: "离线", tint: .orange)
            } else if store.isCoreRunning {
                summaryChip(title: "核心", value: "运行中", tint: .green)
            } else {
                summaryChip(title: "核心", value: "未运行", tint: .secondary)
            }
        }
    }

    private func summaryChip(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private var headerSubtitle: String {
        if isOfflinePolicyMode {
            return selectedGroup.map { "\($0.name) · 离线配置预览" } ?? "离线配置预览"
        }
        return selectedGroup.map { "\($0.name) · 当前 \($0.now)" } ?? "启动 mihomo 并刷新核心状态"
    }

    private var content: some View {
        PolicyWorkspaceView(
            providers: store.providers.filter { $0.kind.caseInsensitiveCompare("Proxy") == .orderedSame },
            groups: visibleGroups,
            iconImages: store.policyGroupIconImages,
            isOffline: isOfflinePolicyMode,
            providerHistory: { store.providerUpdateHistory(for: $0).first },
            refreshProvider: { provider in Task { await store.refreshProviderResource(provider) } },
            testGroup: { group in Task { await store.testGroupDelay(group) } },
            expandedProviderIDs: $expandedProviderIDs,
            expandedGroupIDs: $expandedGroupIDs,
            selectedNodeID: $selectedNodeID,
            nodesForGroup: nodes(for:),
            toggleGroup: { group in
                selectedGroupID = group.id
                ensureNodeSelection(in: group)
                if expandedGroupIDs.contains(group.id) {
                    expandedGroupIDs.remove(group.id)
                } else {
                    expandedGroupIDs.insert(group.id)
                }
            },
            showGroupDetail: { group in
                selectedGroupID = group.id
                showingGroupDetail = true
            },
            activateNode: handleNodeDoubleClick
        )
    }

    private func nodes(for group: ProxyGroup) -> [PolicyNodeRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodes = query.isEmpty ? group.all : group.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.type.localizedCaseInsensitiveContains(query)
                || group.name.localizedCaseInsensitiveContains(query)
        }
        let visibleNodes = nodes.isEmpty && query.isEmpty == false ? group.all : nodes
        return visibleNodes
            .filter { !hideUnavailableNodes || $0.available != false }
            .map { PolicyNodeRow(group: group, node: $0) }
    }

    private var allGroupsExpanded: Bool {
        !visibleGroups.isEmpty && visibleGroups.allSatisfy { expandedGroupIDs.contains($0.id) }
    }

    private func toggleAllGroups() {
        let ids = Set(visibleGroups.map(\.id))
        if allGroupsExpanded {
            expandedGroupIDs.subtract(ids)
        } else {
            expandedGroupIDs.formUnion(ids)
        }
    }

    private func ensureSelection() {
        let groups = visibleGroups
        guard groups.isEmpty == false else {
            selectedGroupID = nil
            selectedNodeID = nil
            return
        }

        let group = groups.first(where: { $0.id == selectedGroupID }) ?? groups.first!
        selectedGroupID = group.id
        ensureNodeSelection(in: group)
    }

    private func ensureNodeSelection(in group: ProxyGroup) {
        let rows = nodes(for: group)
        guard rows.isEmpty == false else {
            selectedNodeID = nil
            return
        }
        if let selectedNodeID, rows.contains(where: { $0.id == selectedNodeID }) {
            return
        }
        selectedNodeID = nil
    }

    private var automaticOverrideBinding: Binding<Bool> {
        Binding(
            get: { pendingAutomaticOverride != nil },
            set: { visible in
                if visible == false {
                    pendingAutomaticOverride = nil
                }
            }
        )
    }

    private func handleNodeDoubleClick(_ row: PolicyNodeRow) {
        guard isOfflinePolicyMode == false else { return }
        if row.isCurrent { return }
        if row.group.isAutomaticURLTestGroup {
            pendingAutomaticOverride = row
        } else {
            selectNode(row)
        }
    }

    private var canApplySelectedNode: Bool {
        guard let selectedNodeRow else { return false }
        return selectedNodeRow.isCurrent == false
    }

    private func applySelectedNode() {
        guard let selectedNodeRow, canApplySelectedNode else { return }
        handleNodeDoubleClick(selectedNodeRow)
    }

    private func selectNode(_ row: PolicyNodeRow) {
        Task { await store.selectProxy(group: row.group.name, proxy: row.node.name) }
    }

    private func openPolicyGroupEditor() {
        guard let profile = store.activeProfile else { return }
        groupEditorContent = store.profileContent(for: profile)
        showingGroupEditor = true
    }

    private func savePolicyGroups() {
        guard let profile = store.activeProfile else { return }
        Task {
            await store.saveProfileEditor(
                profileID: profile.id,
                name: profile.name,
                content: groupEditorContent,
                undoManager: undoManager
            )
            showingGroupEditor = false
        }
    }

    private func collapseSelectedGroup() {
        guard let selectedGroupID else { return }
        expandedGroupIDs.remove(selectedGroupID)
    }

    private func expandSelectedGroup() {
        guard let selectedGroupID else { return }
        expandedGroupIDs.insert(selectedGroupID)
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshController() } },
            activateSelection: searchIsFocused == false && canApplySelectedNode ? applySelectedNode : nil,
            previewSelection: searchIsFocused || selectedGroup == nil ? nil : { showingGroupDetail = true },
            collapseSelection: searchIsFocused || selectedGroup == nil ? nil : collapseSelectedGroup,
            expandSelection: searchIsFocused || selectedGroup == nil ? nil : expandSelectedGroup
        )
    }
}
