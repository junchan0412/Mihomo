import AppKit
import SwiftUI

struct PolicyWorkspaceView: View {
    var providers: [ProviderItem]
    var groups: [ProxyGroup]
    var iconImages: [String: NSImage]
    var isOffline: Bool
    var providerHistory: (ProviderItem) -> ProviderUpdateRecord?
    var refreshProvider: (ProviderItem) -> Void
    var openProvider: (ProviderItem) -> Void
    var testGroup: (ProxyGroup) -> Void
    @Binding var expandedGroupIDs: Set<String>
    @Binding var selectedNodeID: String?
    var nodesForGroup: (ProxyGroup) -> [PolicyNodeRow]
    var toggleGroup: (ProxyGroup) -> Void
    var activateNode: (PolicyNodeRow) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if providers.isEmpty == false {
                    sectionHeader("代理节点", count: providers.count)
                    VStack(spacing: 10) {
                        ForEach(providers) { provider in
                            providerRow(provider)
                        }
                    }
                }

                sectionHeader("策略组", count: groups.count)
                VStack(spacing: 10) {
                    ForEach(groups) { group in
                        groupRow(group)
                    }
                }
            }
            .padding(.trailing, 6)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func providerRow(_ provider: ProviderItem) -> some View {
        Button { openProvider(provider) } label: { HStack(spacing: 14) {
            rowIcon("paperplane.fill", color: .cyan)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.name).font(.headline).lineLimit(1)
                    Text(provider.providerType.isEmpty ? "PROVIDER" : provider.providerType.uppercased())
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(providerSubtitle(provider)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let record = providerHistory(provider) {
                Text(record.succeeded ? "已更新" : "更新失败")
                    .font(.caption).foregroundStyle(record.succeeded ? Color.green : Color.red)
            }
            Button { refreshProvider(provider) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("刷新 Provider")
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }}
        .buttonStyle(.plain)
        .padding(.horizontal, 16).frame(minHeight: 74)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func groupRow(_ group: ProxyGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { toggleGroup(group) } label: {
                    HStack(spacing: 14) {
                        if let image = iconImages[group.name] {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 26, height: 26)
                                .padding(9).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                        } else {
                            rowIcon(group.type.lowercased().contains("url") ? "speedometer" : "switch.2", color: groupColor(group))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(group.name).font(.headline).lineLimit(1)
                                Text(group.type.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                if group.hidden {
                                    Text("HIDDEN")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text(group.now.isEmpty ? "尚未选择 · \(group.all.count) 个候选" : "\(group.now) · \(group.all.count) 个候选")
                                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { testGroup(group) } label: { Image(systemName: "speedometer") }
                    .buttonStyle(.borderless).disabled(isOffline).help("测速此组")

                Button { toggleGroup(group) } label: {
                    Image(systemName: expandedGroupIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 82)

            if expandedGroupIDs.contains(group.id) {
                Divider()
                    .padding(.horizontal, 16)

                PolicyNodeCardGrid(
                    rows: nodesForGroup(group),
                    isOffline: isOffline,
                    selectedNodeID: $selectedNodeID,
                    activate: activateNode
                )
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: expandedGroupIDs.contains(group.id))
    }

    private func rowIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name).font(.title3).foregroundStyle(color).frame(width: 26, height: 26)
            .padding(9).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
    }

    private func providerSubtitle(_ provider: ProviderItem) -> String {
        let count = provider.memberNames.count
        if count > 0 { return "\(count) 个缓存节点" }
        if provider.remoteURL != nil { return "远程 Provider · 尚无本地节点缓存" }
        return "本地 Provider · 尚未读取到节点文件"
    }

    private func groupColor(_ group: ProxyGroup) -> Color {
        let type = group.type.lowercased()
        if type.contains("url") { return .green }
        if type.contains("fallback") { return .orange }
        return .purple
    }
}
