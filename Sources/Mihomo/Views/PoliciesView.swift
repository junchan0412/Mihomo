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
    @State private var sortsByDelay = true
    @State private var delayFilter: PolicyDelayFilter = .all

    private var presentationSnapshot: PolicyPresentationSnapshot {
        PolicyPresentation.make(
            liveGroups: store.proxyGroups,
            offlineGroups: store.offlineProxyGroups,
            providers: store.providers,
            searchText: searchText,
            showHiddenGroups: showHiddenGroups,
            hideUnavailableNodes: hideUnavailableNodes,
            sortsByDelay: sortsByDelay,
            delayFilter: delayFilter
        )
    }

    var body: some View {
        let presentation = presentationSnapshot
        VStack(alignment: .leading, spacing: 14) {
            header(presentation)
            mainContent(presentation)
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("策略")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索策略组或节点")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext(in: presentation))
        .onAppear {
            ensureSelection(in: presentation)
            Task { await store.preloadPolicyGroupIcons(for: presentation.displayGroups) }
        }
        .onChange(of: store.proxyGroups) {
            let groups = store.proxyGroups.isEmpty ? store.offlineProxyGroups : store.proxyGroups
            Task { await store.preloadPolicyGroupIcons(for: groups) }
        }
        .onChange(of: store.offlineProxyGroups) {
            let groups = store.proxyGroups.isEmpty ? store.offlineProxyGroups : store.proxyGroups
            Task { await store.preloadPolicyGroupIcons(for: groups) }
        }
        .onChange(of: presentation.selectionIDs) {
            ensureSelection(in: presentation)
        }
        .onChange(of: selectedGroupID) {
            guard let selectedGroup = presentation.selectedGroup(id: selectedGroupID) else {
                selectedNodeID = nil
                return
            }
            ensureNodeSelection(in: selectedGroup, presentation: presentation)
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
            if let selectedGroup = presentation.selectedGroup(id: selectedGroupID) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selectedGroup.name).font(.title2.weight(.semibold))
                    Text("\(selectedGroup.type) · \(selectedGroup.all.count) 个候选").foregroundStyle(.secondary)
                    PolicyDelayHistoryPane(entries: store.delayHistory(for: selectedGroup))
                    ScrollView {
                        PolicyNodeCardGrid(
                            rows: presentation.rows(for: selectedGroup),
                            isOffline: presentation.isOffline,
                            selectedNodeID: $selectedNodeID,
                            activate: handleNodeDoubleClick
                        )
                    }
                }
                .padding(24).frame(minWidth: 620, minHeight: 480, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func mainContent(_ presentation: PolicyPresentationSnapshot) -> some View {
        if presentation.displayGroups.isEmpty {
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
        } else if presentation.visibleGroups.isEmpty {
            PolicySearchEmptyState(query: searchText) {
                searchText = ""
                delayFilter = .all
                hideUnavailableNodes = false
            }
        } else {
            content(presentation)
        }
    }

    private func header(_ presentation: PolicyPresentationSnapshot) -> some View {
        PolicyHeaderView(
            groupCount: presentation.visibleGroups.count,
            nodeCount: presentation.visibleNodeCount,
            providerCount: presentation.proxyProviders.count,
            isOffline: presentation.isOffline,
            isCoreRunning: store.isCoreRunning,
            allGroupsExpanded: allGroupsExpanded(in: presentation),
            canExpandGroups: presentation.visibleGroups.isEmpty == false,
            canTestAll: store.proxyGroups.isEmpty == false,
            sortsByDelay: $sortsByDelay,
            delayFilter: $delayFilter,
            hideUnavailableNodes: $hideUnavailableNodes,
            showHiddenGroups: $showHiddenGroups,
            toggleAllGroups: { toggleAllGroups(in: presentation) },
            testAllDelays: { Task { await store.testAllProxyDelays() } }
        )
    }

    private func content(_ presentation: PolicyPresentationSnapshot) -> some View {
        PolicyWorkspaceView(
            providers: presentation.proxyProviders,
            groups: presentation.visibleGroups,
            iconImages: store.policyGroupIconImages,
            isOffline: presentation.isOffline,
            providerHistory: { store.providerUpdateHistory(for: $0).first },
            refreshProvider: { provider in Task { await store.refreshProviderResource(provider) } },
            testGroup: { group in Task { await store.testGroupDelay(group) } },
            expandedProviderIDs: $expandedProviderIDs,
            expandedGroupIDs: $expandedGroupIDs,
            selectedNodeID: $selectedNodeID,
            nodesForGroup: presentation.rows(for:),
            toggleGroup: { group in
                selectedGroupID = group.id
                ensureNodeSelection(in: group, presentation: presentation)
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

    private func allGroupsExpanded(in presentation: PolicyPresentationSnapshot) -> Bool {
        presentation.visibleGroups.isEmpty == false
            && presentation.visibleGroups.allSatisfy { expandedGroupIDs.contains($0.id) }
    }

    private func toggleAllGroups(in presentation: PolicyPresentationSnapshot) {
        let ids = Set(presentation.visibleGroups.map(\.id))
        if allGroupsExpanded(in: presentation) {
            expandedGroupIDs.subtract(ids)
        } else {
            expandedGroupIDs.formUnion(ids)
        }
    }

    private func ensureSelection(in presentation: PolicyPresentationSnapshot) {
        let groups = presentation.visibleGroups
        guard groups.isEmpty == false else {
            selectedGroupID = nil
            selectedNodeID = nil
            return
        }

        let group = groups.first(where: { $0.id == selectedGroupID }) ?? groups.first!
        selectedGroupID = group.id
        ensureNodeSelection(in: group, presentation: presentation)
    }

    private func ensureNodeSelection(in group: ProxyGroup, presentation: PolicyPresentationSnapshot) {
        let rows = presentation.rows(for: group)
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
        guard presentationSnapshot.isOffline == false else { return }
        if row.isCurrent { return }
        if row.group.isAutomaticURLTestGroup {
            pendingAutomaticOverride = row
        } else {
            selectNode(row)
        }
    }

    private func selectedNodeRow(in presentation: PolicyPresentationSnapshot) -> PolicyNodeRow? {
        guard let selectedGroup = presentation.selectedGroup(id: selectedGroupID),
              let selectedNodeID else { return nil }
        return presentation.rows(for: selectedGroup).first { $0.id == selectedNodeID }
    }

    private func canApplySelectedNode(in presentation: PolicyPresentationSnapshot) -> Bool {
        guard let selectedNodeRow = selectedNodeRow(in: presentation) else { return false }
        return selectedNodeRow.isCurrent == false
    }

    private func applySelectedNode() {
        let presentation = presentationSnapshot
        guard let selectedNodeRow = selectedNodeRow(in: presentation),
              canApplySelectedNode(in: presentation) else { return }
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

    private func commandContext(in presentation: PolicyPresentationSnapshot) -> WorkspaceCommandContext {
        let selectedGroup = presentation.selectedGroup(id: selectedGroupID)
        return WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: { Task { await store.refreshController() } },
            activateSelection: searchIsFocused == false && canApplySelectedNode(in: presentation) ? applySelectedNode : nil,
            previewSelection: searchIsFocused || selectedGroup == nil ? nil : { showingGroupDetail = true },
            collapseSelection: searchIsFocused || selectedGroup == nil ? nil : collapseSelectedGroup,
            expandSelection: searchIsFocused || selectedGroup == nil ? nil : expandSelectedGroup
        )
    }
}
