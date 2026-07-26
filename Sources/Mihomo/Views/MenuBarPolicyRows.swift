import AppKit
import SwiftUI

struct MenuBarPolicyGroupRow: View {
    var group: ProxyGroup
    var image: NSImage?
    var searchText: String
    @Binding var isExpanded: Bool
    var isFavorite: Bool
    var selectNode: (ProxyNode) -> Void
    var testGroup: () -> Void
    var toggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DisclosureGroup(isExpanded: $isExpanded) {
                LazyVStack(spacing: 2) {
                    ForEach(filteredNodes) { node in
                        MenuBarProxyNodeRow(node: node, isCurrent: node.name == group.now) { selectNode(node) }
                    }
                }
                .padding(.top, 6).padding(.leading, 2)
            } label: {
                HStack(spacing: 9) {
                    groupIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formatters.trimmedMenuText(group.name, limit: 28)).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(currentNodeTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    MenuBarGroupLatencySummary(group: group, currentNode: currentNode)
                }
                .padding(.vertical, 8)
            }
            policyAction(systemImage: "speedometer", help: "测试 \(group.name) 的节点延迟", action: testGroup)
            policyAction(systemImage: isFavorite ? "star.fill" : "star", help: isFavorite ? "取消收藏 \(group.name)" : "收藏 \(group.name)", tint: isFavorite ? .yellow : .secondary, action: toggleFavorite)
        }
        .padding(.leading, 14).padding(.trailing, 12)
    }

    private var currentNode: ProxyNode? { group.all.first { $0.name == group.now } }
    private var filteredNodes: [ProxyNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || group.name.localizedCaseInsensitiveContains(query) ? group.all : group.all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var currentNodeTitle: String {
        let current = group.now.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? group.type : "\(current) · \(group.type)"
    }
    @ViewBuilder private var groupIcon: some View {
        if let image { Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16) }
        else { Image(systemName: group.type.lowercased().contains("url") ? "speedometer" : group.type.lowercased().contains("fallback") ? "arrow.triangle.2.circlepath" : "switch.2").foregroundStyle(.secondary).frame(width: 16, height: 16) }
    }
    private func policyAction(systemImage: String, help: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage).foregroundStyle(tint).frame(width: 18, height: 18) }
            .buttonStyle(.borderless).help(help).accessibilityLabel(help).padding(.top, 7)
    }
}

private struct MenuBarProxyNodeRow: View {
    var node: ProxyNode
    var isCurrent: Bool
    var select: () -> Void
    init(node: ProxyNode, isCurrent: Bool, select: @escaping () -> Void) { self.node = node; self.isCurrent = isCurrent; self.select = select }
    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle").foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.45)).imageScale(.small).frame(width: 14)
                Text(Formatters.trimmedMenuText(node.name, limit: 34)).font(.callout).lineLimit(1)
                Spacer(minLength: 8)
                MenuBarDelayBadge(node: node)
            }
            .padding(.horizontal, 8).padding(.vertical, 6).background(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(node.name)
    }
}

struct MenuBarDelayBadge: View {
    var node: ProxyNode?
    var body: some View { Text(title).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(color).lineLimit(1).frame(minWidth: 44, alignment: .trailing).accessibilityLabel("延迟").accessibilityValue(title) }
    private var title: String { MenuBarDelayBadgeTitle(node: node) }
    private var color: Color { node?.available == false ? .red : (node?.delay ?? 0) < 1 ? .secondary : (node?.delay ?? 0) < 150 ? .green : (node?.delay ?? 0) < 350 ? .orange : .red }
}

private struct MenuBarGroupLatencySummary: View {
    var group: ProxyGroup
    var currentNode: ProxyNode?
    private var coverageTitle: String { "\(group.all.filter { ($0.delay ?? 0) > 0 }.count)/\(group.all.count) 已测速" }
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) { MenuBarDelayBadge(node: currentNode); Text(coverageTitle).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
            .accessibilityElement(children: .combine).accessibilityLabel("\(group.name) 延迟状态").accessibilityValue("\(MenuBarDelayBadgeTitle(node: currentNode))，\(coverageTitle)")
    }
}

func MenuBarDelayBadgeTitle(node: ProxyNode?) -> String {
    if node?.available == false { return "不可用" }
    guard let delay = node?.delay, delay > 0 else { return "未测试" }
    return "\(delay) ms"
}
