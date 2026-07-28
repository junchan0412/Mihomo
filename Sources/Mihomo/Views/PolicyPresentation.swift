import SwiftUI

struct PolicyPresentationSnapshot {
    var displayGroups: [ProxyGroup]
    var visibleGroups: [ProxyGroup]
    var proxyProviders: [ProviderItem]
    var nodeRowsByGroupID: [String: [PolicyNodeRow]]
    var visibleNodeCount: Int
    var selectionIDs: [String]
    var isOffline: Bool

    func selectedGroup(id: String?) -> ProxyGroup? {
        guard let id else { return visibleGroups.first }
        return visibleGroups.first(where: { $0.id == id }) ?? visibleGroups.first
    }

    func rows(for group: ProxyGroup) -> [PolicyNodeRow] {
        nodeRowsByGroupID[group.id] ?? []
    }
}

enum PolicyPresentation {
    static func make(
        liveGroups: [ProxyGroup],
        offlineGroups: [ProxyGroup],
        providers: [ProviderItem],
        searchText: String,
        showHiddenGroups: Bool,
        hideUnavailableNodes: Bool,
        sortsByDelay: Bool,
        delayFilter: PolicyDelayFilter
    ) -> PolicyPresentationSnapshot {
        let displayGroups = liveGroups.isEmpty ? offlineGroups : liveGroups
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var presentedGroups: [PresentedGroup] = []
        presentedGroups.reserveCapacity(displayGroups.count)

        for (index, group) in displayGroups.enumerated() {
            guard showHiddenGroups || group.hidden == false else { continue }
            let groupNameMatches = query.isEmpty || group.name.localizedCaseInsensitiveContains(query)
            let groupMetadataMatches = groupNameMatches
                || group.now.localizedCaseInsensitiveContains(query)
                || group.type.localizedCaseInsensitiveContains(query)
            var allRows: [PolicyNodeRow] = []
            var matchingRows: [PolicyNodeRow] = []
            allRows.reserveCapacity(group.all.count)
            var anyNodeMatches = false
            var minimumDelay = Int.max
            var currentDelay: Int?

            for node in group.all {
                let delay = positiveDelay(node.delay)
                minimumDelay = min(minimumDelay, delay)
                if node.name == group.now, delay != .max {
                    currentDelay = delay
                }

                let nodeMatches = query.isEmpty == false
                    && (node.name.localizedCaseInsensitiveContains(query)
                        || node.type.localizedCaseInsensitiveContains(query))
                anyNodeMatches = anyNodeMatches || nodeMatches
                guard hideUnavailableNodes == false || node.available != false else { continue }
                guard delayFilter.matches(node) else { continue }
                let row = PolicyNodeRow(group: group, node: node)
                allRows.append(row)
                if nodeMatches {
                    matchingRows.append(row)
                }
            }

            var rows: [PolicyNodeRow]
            if groupNameMatches {
                rows = allRows
            } else if anyNodeMatches {
                rows = matchingRows
            } else if groupMetadataMatches {
                rows = allRows
            } else {
                continue
            }
            guard rows.isEmpty == false || group.all.isEmpty else { continue }
            if sortsByDelay {
                rows.sort { nodeDelayOrder($0.node, $1.node) }
            }
            presentedGroups.append(
                PresentedGroup(
                    group: group,
                    rows: rows,
                    selectedDelay: currentDelay ?? minimumDelay,
                    originalIndex: index
                )
            )
        }

        if sortsByDelay {
            presentedGroups.sort { lhs, rhs in
                if lhs.selectedDelay == rhs.selectedDelay {
                    let order = lhs.group.name.localizedCaseInsensitiveCompare(rhs.group.name)
                    return order == .orderedSame ? lhs.originalIndex < rhs.originalIndex : order == .orderedAscending
                }
                return lhs.selectedDelay < rhs.selectedDelay
            }
        }

        var nodeRowsByGroupID: [String: [PolicyNodeRow]] = [:]
        nodeRowsByGroupID.reserveCapacity(presentedGroups.count)
        var selectionIDs: [String] = []
        var visibleNodeCount = 0
        for presented in presentedGroups {
            nodeRowsByGroupID[presented.group.id] = presented.rows
            selectionIDs.append("group:\(presented.group.id)")
            selectionIDs.append(contentsOf: presented.rows.map { "node:\($0.id)" })
            visibleNodeCount += presented.rows.count
        }

        return PolicyPresentationSnapshot(
            displayGroups: displayGroups,
            visibleGroups: presentedGroups.map(\.group),
            proxyProviders: providers.filter { $0.kind.caseInsensitiveCompare("Proxy") == .orderedSame },
            nodeRowsByGroupID: nodeRowsByGroupID,
            visibleNodeCount: visibleNodeCount,
            selectionIDs: selectionIDs,
            isOffline: liveGroups.isEmpty && offlineGroups.isEmpty == false
        )
    }

    private struct PresentedGroup {
        var group: ProxyGroup
        var rows: [PolicyNodeRow]
        var selectedDelay: Int
        var originalIndex: Int
    }

    private static func nodeDelayOrder(_ lhs: ProxyNode, _ rhs: ProxyNode) -> Bool {
        if lhs.available == false { return false }
        if rhs.available == false { return true }
        let lhsDelay = positiveDelay(lhs.delay)
        let rhsDelay = positiveDelay(rhs.delay)
        if lhsDelay == rhsDelay {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhsDelay < rhsDelay
    }

    private static func positiveDelay(_ delay: Int?) -> Int {
        guard let delay, delay > 0 else { return .max }
        return delay
    }
}

struct PolicyHeaderView: View {
    var groupCount: Int
    var nodeCount: Int
    var providerCount: Int
    var isOffline: Bool
    var isCoreRunning: Bool
    var allGroupsExpanded: Bool
    var canExpandGroups: Bool
    var canTestAll: Bool
    @Binding var sortsByDelay: Bool
    @Binding var delayFilter: PolicyDelayFilter
    @Binding var hideUnavailableNodes: Bool
    @Binding var showHiddenGroups: Bool
    var toggleAllGroups: () -> Void
    var testAllDelays: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("策略")
                    .font(MihomoUI.Fonts.pageTitle)
                Text(isOffline ? "离线预览策略组结构；启动核心后可切换节点与测速。" : "管理 Proxy Provider、策略组与当前节点。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                summaryStrip
            }

            Spacer()

            Button(action: toggleAllGroups) {
                Image(systemName: allGroupsExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help(allGroupsExpanded ? "折叠全部策略组" : "展开全部策略组")
            .disabled(canExpandGroups == false)

            Button(action: testAllDelays) {
                Image(systemName: "speedometer")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .help("一键延迟测试")
            .disabled(canTestAll == false)

            Menu {
                Toggle("按延迟排序", isOn: $sortsByDelay)
                Divider()
                Picker("延迟筛选", selection: $delayFilter) {
                    ForEach(PolicyDelayFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
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

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            summaryChip(title: "策略组", value: "\(groupCount)", tint: .blue)
            summaryChip(title: "节点", value: "\(nodeCount)", tint: .purple)
            summaryChip(title: "Provider", value: "\(providerCount)", tint: .cyan)
            if isOffline {
                summaryChip(title: "模式", value: "离线", tint: .orange)
            } else if isCoreRunning {
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
}
