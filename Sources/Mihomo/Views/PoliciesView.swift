import AppKit
import SwiftUI

struct PoliciesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedGroupID: String?
    @State private var selectedNodeID: String?
    @State private var searchText = ""
    @State private var pendingAutomaticOverride: PolicyNodeRow?
    @State private var showingGroupEditor = false
    @State private var groupEditorContent = ""

    private var displayGroups: [ProxyGroup] {
        store.proxyGroups.isEmpty ? store.offlineProxyGroups : store.proxyGroups
    }

    private var isOfflinePolicyMode: Bool {
        store.proxyGroups.isEmpty && store.offlineProxyGroups.isEmpty == false
    }

    private var visibleGroups: [ProxyGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return displayGroups }
        return displayGroups.filter { group in
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
            if displayGroups.isEmpty == false {
                toolbar
                PolicyStatusStrip(
                    groupCount: displayGroups.count,
                    nodeCount: displayGroups.reduce(0) { $0 + $1.all.count },
                    selectedGroup: selectedGroup,
                    delayStatus: store.delayTestStatus,
                    failureSummary: store.delayTestFailureSummary,
                    isOffline: isOfflinePolicyMode
                )
            }
            mainContent
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("策略")
        .onAppear {
            if store.offlineProxyGroups.isEmpty {
                store.refreshConfigArtifacts()
            }
            ensureSelection()
            Task { await store.preloadPolicyGroupIcons() }
        }
        .onChange(of: store.proxyGroups) {
            ensureSelection()
            Task { await store.preloadPolicyGroupIcons() }
        }
        .onChange(of: store.offlineProxyGroups) {
            ensureSelection()
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
            VStack(alignment: .leading, spacing: 4) {
                Text("策略")
                    .font(MihomoUI.Fonts.pageTitle)
                Text(headerSubtitle)
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                openPolicyGroupEditor()
            } label: {
                Label("编辑策略组", systemImage: "slider.horizontal.3")
            }
            .disabled(store.activeProfile == nil)

            if store.proxyGroups.isEmpty == false {
                Button {
                    Task { await store.testAllProxyDelays() }
                } label: {
                    Label("测速全部", systemImage: "speedometer")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                Task { await store.refreshController() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }

    private var headerSubtitle: String {
        if isOfflinePolicyMode {
            return selectedGroup.map { "\($0.name) · 离线配置预览" } ?? "离线配置预览"
        }
        return selectedGroup.map { "\($0.name) · 当前 \($0.now)" } ?? "启动 mihomo 并刷新 Controller"
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("搜索策略组、当前节点或代理", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)

            Spacer()

            Button {
                applySelectedNode()
            } label: {
                Label("使用节点", systemImage: "checkmark.circle")
            }
            .disabled(isOfflinePolicyMode || canApplySelectedNode == false)

            Button {
                if let selectedGroup, let selectedNodeRow {
                    Task { await store.testProxyDelay(group: selectedGroup.name, proxy: selectedNodeRow.node.name) }
                }
            } label: {
                Label("测速节点", systemImage: "speedometer")
            }
            .disabled(isOfflinePolicyMode || selectedGroup == nil || selectedNodeRow == nil)

            Button {
                if let selectedGroup {
                    Task { await store.testGroupDelay(selectedGroup) }
                }
            } label: {
                Label("测速此组", systemImage: "timer")
            }
            .disabled(isOfflinePolicyMode || selectedGroup == nil)

        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            PolicyGroupList(
                groups: visibleGroups,
                iconImages: store.policyGroupIconImages,
                selectedGroupID: $selectedGroupID
            )
            .frame(width: 300)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGroup?.name ?? "节点")
                            .font(.headline)
                        Text(selectedGroup.map { "\($0.type) · \($0.all.count) 个候选" } ?? "没有策略组")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let selectedGroup, selectedGroup.now.isEmpty == false {
                        Label(selectedGroup.now, systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }

                AppKitTable(
                    rows: nodeRows,
                    selection: $selectedNodeID,
                    columns: [
                        .init(title: "节点", width: 280, textColor: currentNodeColor) { $0.displayName },
                        .init(title: "类型", width: 110, textColor: currentNodeColor) { $0.node.type },
                        .init(title: "延迟", width: 90, textColor: currentNodeColor) { $0.delayText }
                    ],
                    onDoubleClick: handleNodeDoubleClick,
                    hasHorizontalScroller: false
                )
                .overlay {
                    if nodeRows.isEmpty {
                        ContentUnavailableView("没有候选节点", systemImage: "switch.2")
                    }
                }
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 420, maxHeight: .infinity)
        .overlay {
            if visibleGroups.isEmpty {
                ContentUnavailableView("没有策略组", systemImage: "switch.2", description: Text("当前配置没有可显示的策略组。"))
            }
        }
    }

    private func nodes(for group: ProxyGroup) -> [PolicyNodeRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodes = query.isEmpty ? group.all : group.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.type.localizedCaseInsensitiveContains(query)
                || group.name.localizedCaseInsensitiveContains(query)
        }
        let visibleNodes = nodes.isEmpty && query.isEmpty == false ? group.all : nodes
        return visibleNodes.map { PolicyNodeRow(group: group, node: $0) }
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

    private func currentNodeColor(_ row: PolicyNodeRow) -> NSColor? {
        row.isCurrent ? .systemGreen : nil
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
            await store.saveProfileEditor(profileID: profile.id, name: profile.name, content: groupEditorContent)
            showingGroupEditor = false
        }
    }
}
