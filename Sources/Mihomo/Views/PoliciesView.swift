import AppKit
import SwiftUI

struct PoliciesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedGroupID: String?
    @State private var selectedNodeID: String?
    @State private var searchText = ""
    @State private var pendingAutomaticOverride: PolicyNodeRow?

    private var visibleGroups: [ProxyGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return store.proxyGroups }
        return store.proxyGroups.filter { group in
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
            toolbar
            PolicyStatusStrip(
                groupCount: store.proxyGroups.count,
                nodeCount: store.proxyGroups.reduce(0) { $0 + $1.all.count },
                selectedGroup: selectedGroup,
                delayStatus: store.delayTestStatus,
                failureSummary: store.delayTestFailureSummary
            )
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("策略")
        .onAppear {
            ensureSelection()
        }
        .onChange(of: store.proxyGroups) {
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("策略")
                    .font(.largeTitle.bold())
                Text(selectedGroup.map { "\($0.name) · 当前 \($0.now)" } ?? "启动 mihomo 并刷新 Controller")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await store.refreshController() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("搜索策略组、当前节点或代理", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)

            Spacer()

            Button {
                if let selectedGroup, let selectedNodeRow {
                    Task { await store.testProxyDelay(group: selectedGroup.name, proxy: selectedNodeRow.node.name) }
                }
            } label: {
                Label("测速节点", systemImage: "speedometer")
            }
            .disabled(selectedGroup == nil || selectedNodeRow == nil)

            Button {
                if let selectedGroup {
                    Task { await store.testGroupDelay(selectedGroup) }
                }
            } label: {
                Label("测速此组", systemImage: "timer")
            }
            .disabled(selectedGroup == nil)

            Button {
                Task { await store.testAllProxyDelays() }
            } label: {
                Label("测速全部", systemImage: "gauge.with.dots.needle.67percent")
            }
            .disabled(store.proxyGroups.isEmpty)
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            PolicyGroupList(
                groups: visibleGroups,
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
                        .init(title: "节点", width: 380, textColor: currentNodeColor) { $0.displayName },
                        .init(title: "类型", width: 130, textColor: currentNodeColor) { $0.node.type },
                        .init(title: "延迟", width: 110, textColor: currentNodeColor) { $0.delayText }
                    ],
                    onDoubleClick: handleNodeDoubleClick
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
                ContentUnavailableView("没有策略组", systemImage: "switch.2", description: Text("启动 mihomo 并刷新 Controller。"))
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
        if row.isCurrent { return }
        if row.group.isAutomaticURLTestGroup {
            pendingAutomaticOverride = row
        } else {
            selectNode(row)
        }
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
    @Binding var selectedGroupID: String?

    var body: some View {
        List(selection: $selectedGroupID) {
            ForEach(groups) { group in
                PolicyGroupRow(group: group)
                    .tag(group.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("没有策略组", systemImage: "switch.2")
            }
        }
    }
}

private struct PolicyGroupRow: View {
    var group: ProxyGroup

    var body: some View {
        HStack(spacing: 10) {
            PolicyGroupIcon(group: group)
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
                Text(group.now.isEmpty ? "-" : group.now)
                    .font(.caption)
                    .foregroundStyle(group.now.isEmpty ? Color.secondary : Color.green)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PolicyGroupIcon: View {
    var group: ProxyGroup

    var body: some View {
        if let icon = group.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
           icon.isEmpty == false {
            if let url = URL(string: icon), url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        fallbackIcon
                    }
                }
            } else if let image = NSImage(contentsOfFile: (icon as NSString).expandingTildeInPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackIcon
            }
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

    var body: some View {
        HStack(spacing: 16) {
            Label("\(groupCount) 组", systemImage: "switch.2")
            Label("\(nodeCount) 个候选", systemImage: "circle.grid.3x3")

            if let selectedGroup {
                Label("\(selectedGroup.name)：\(selectedGroup.now.isEmpty ? "-" : selectedGroup.now)", systemImage: "checkmark.circle")
                    .lineLimit(1)
            }

            Spacer()

            Text(delayStatus)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            if failureSummary.isEmpty == false {
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
