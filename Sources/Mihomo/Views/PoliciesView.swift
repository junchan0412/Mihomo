import AppKit
import SwiftUI

struct PoliciesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedGroupID: String?
    @State private var selectedNodeID: String?
    @State private var searchText = ""
    @State private var pendingAutomaticOverride: PolicyNodeRow?

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
        .padding(24)
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
                    .font(.largeTitle.bold())
                Text(headerSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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
            .frame(width: 310)

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
}

private struct PolicyNodeRow: Identifiable, Hashable {
    var group: ProxyGroup
    var node: ProxyNode

    var id: String { "\(group.name)\u{1f}\(node.name)" }
    var isCurrent: Bool { group.now == node.name }
    var displayName: String { isCurrent ? "✓ \(node.name)" : node.name }

    var delayText: String {
        guard let delay = node.delay, delay > 0 else { return "-" }
        return "\(delay) ms"
    }
}

private struct PolicyGroupList: View {
    var groups: [ProxyGroup]
    var iconImages: [String: NSImage]
    @Binding var selectedGroupID: String?

    var body: some View {
        AppKitTable(
            rows: groups,
            selection: $selectedGroupID,
            columns: [
                .init(title: "策略组", width: 170) { $0.name },
                .init(title: "当前", width: 120) { $0.now.isEmpty ? "-" : $0.now },
                .init(title: "数", width: 44) { "\($0.all.count)" }
            ],
            hasHorizontalScroller: false
        )
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("没有策略组", systemImage: "switch.2")
            }
        }
    }
}

private struct PolicyGroupRow: View {
    var group: ProxyGroup
    var image: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            PolicyGroupIcon(group: group, image: image)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(group.all.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(group.now.isEmpty ? "-" : group.now)
                        .font(.caption)
                        .foregroundStyle(group.now.isEmpty ? Color.secondary : Color.green)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(currentDelayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(currentDelayColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var currentDelayText: String {
        guard let node = group.all.first(where: { $0.name == group.now }),
              let delay = node.delay,
              delay > 0
        else { return "-" }
        return "\(delay) ms"
    }

    private var currentDelayColor: Color {
        currentDelayText == "-" ? .secondary : .green
    }
}

private struct PolicyGroupIcon: View {
    var group: ProxyGroup
    var image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(.secondary)
    }

    private var iconName: String {
        let type = group.type.lowercased()
        if type.contains("url") { return "speedometer" }
        if type.contains("fallback") { return "arrow.triangle.2.circlepath" }
        return "switch.2"
    }
}

private extension ProxyGroup {
    var isAutomaticURLTestGroup: Bool {
        type.lowercased().replacingOccurrences(of: "-", with: "").contains("urltest")
    }
}

private struct PolicyStatusStrip: View {
    var groupCount: Int
    var nodeCount: Int
    var selectedGroup: ProxyGroup?
    var delayStatus: String
    var failureSummary: String
    var isOffline: Bool

    var body: some View {
        HStack(spacing: 16) {
            Label("\(groupCount) 组", systemImage: "switch.2")
            Label("\(nodeCount) 个候选", systemImage: "circle.grid.3x3")

            if let selectedGroup {
                Label("\(selectedGroup.name)：\(selectedGroup.now.isEmpty ? "-" : selectedGroup.now)", systemImage: "checkmark.circle")
                    .lineLimit(1)
            }

            Spacer()

            if isOffline {
                Label("离线配置预览，启动核心后可切换节点与测速", systemImage: "eye")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(delayStatus)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            if isOffline == false && failureSummary.isEmpty == false {
                Label(failureSummary, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PolicyStartupEmptyState: View {
    var isCoreRunning: Bool
    var coreStatus: String
    var activeProfileName: String?
    var tunEnabled: Bool
    var startOrRestartCore: () -> Void
    var refreshController: () -> Void
    var openProfiles: () -> Void
    var toggleTun: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: isCoreRunning ? "point.3.connected.trianglepath.dotted" : "power.circle")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    startOrRestartCore()
                } label: {
                    Label(isCoreRunning ? "重启核心" : "启动核心", systemImage: isCoreRunning ? "arrow.clockwise" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(activeProfileName == nil)

                Button {
                    refreshController()
                } label: {
                    Label("刷新 Controller", systemImage: "arrow.clockwise")
                }

                Button {
                    openProfiles()
                } label: {
                    Label("配置", systemImage: "doc.text")
                }

                Button {
                    toggleTun()
                } label: {
                    Label(tunEnabled ? "关闭 TUN" : "开启 TUN", systemImage: "lock.shield")
                }
            }

            Divider()
                .frame(maxWidth: 520)

            HStack(spacing: 22) {
                PolicyStartupFact(title: "核心", value: coreStatus)
                PolicyStartupFact(title: "配置", value: activeProfileName ?? "未选择")
                PolicyStartupFact(title: "TUN", value: tunEnabled ? "将随核心启用" : "关闭")
            }
            .frame(maxWidth: 620)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        isCoreRunning ? "Controller 暂无策略组" : "mihomo 未启动"
    }

    private var message: String {
        if activeProfileName == nil {
            return "请选择或导入配置后启动核心。"
        }
        if isCoreRunning {
            return "当前运行状态没有返回可用策略组。"
        }
        return "启动核心后将在这里显示策略组和候选节点。"
    }
}

private struct PolicyStartupFact: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PolicySearchEmptyState: View {
    var query: String
    var resetSearch: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text("没有匹配的策略")
                    .font(.title3.weight(.semibold))
                Text("未找到包含“\(query)”的策略组或节点。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                resetSearch()
            } label: {
                Label("清除搜索", systemImage: "xmark.circle")
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}
