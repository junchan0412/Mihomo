import AppKit
import SwiftUI

struct PolicyGroupCardGrid: View {
    var groups: [ProxyGroup]
    var iconImages: [String: NSImage]
    @Binding var selectedGroupID: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 12)], spacing: 12) {
            ForEach(groups) { group in
                Button { selectedGroupID = group.id } label: {
                    PolicyGroupCard(group: group, image: iconImages[group.name], isSelected: selectedGroupID == group.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PolicyGroupCard: View {
    var group: ProxyGroup
    var image: NSImage?
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PolicyGroupIcon(group: group, image: image)
                    .frame(width: 28, height: 28)
                    .padding(7)
                    .background(Color.accentColor.opacity(isSelected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.headline).lineLimit(1)
                    Text(group.type).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(group.all.count)").font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 7) {
                Image(systemName: group.now.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
                    .foregroundStyle(group.now.isEmpty ? Color.secondary : Color.green)
                Text(group.now.isEmpty ? "尚未选择" : group.now).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                Text(currentDelayText).font(.caption.monospacedDigit()).foregroundStyle(currentDelayColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : MihomoUI.cardStroke, lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var currentDelayText: String {
        guard let node = group.all.first(where: { $0.name == group.now }), let delay = node.delay, delay > 0 else { return "-" }
        return "\(delay) ms"
    }

    private var currentDelayColor: Color { currentDelayText == "-" ? .secondary : .green }
}

struct PolicyNodeCardGrid: View {
    var rows: [PolicyNodeRow]
    var isOffline: Bool
    @Binding var selectedNodeID: String?
    var activate: (PolicyNodeRow) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 10)], spacing: 10) {
            ForEach(rows) { row in
                Button { selectedNodeID = row.id } label: {
                    PolicyNodeCard(row: row, isSelected: selectedNodeID == row.id)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    guard !isOffline else { return }
                    selectedNodeID = row.id
                    activate(row)
                })
                .contextMenu {
                    Button("使用此节点") { activate(row) }.disabled(isOffline || row.isCurrent)
                }
            }
        }
    }
}

private struct PolicyNodeCard: View {
    var row: PolicyNodeRow
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: row.isCurrent ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(row.isCurrent ? .green : (isSelected ? Color.accentColor : Color.secondary))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.node.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(row.node.type).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(row.delayText).font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(delayColor)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(backgroundFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected || row.isCurrent ? 1.5 : 1)
        }
    }

    private var backgroundFill: Color {
        if row.isCurrent { return Color.green.opacity(0.08) }
        if isSelected { return Color.accentColor.opacity(0.08) }
        return MihomoUI.cardFill
    }

    private var borderColor: Color {
        if row.isCurrent { return .green.opacity(0.8) }
        if isSelected { return .accentColor }
        return MihomoUI.cardStroke
    }

    private var delayColor: Color {
        guard let delay = row.node.delay, delay > 0 else { return .secondary }
        if delay < 150 { return .green }
        if delay < 350 { return .orange }
        return .red
    }
}

private struct PolicyGroupIcon: View {
    var group: ProxyGroup
    var image: NSImage?

    var body: some View {
        if let image { Image(nsImage: image).resizable().scaledToFit() }
        else { Image(systemName: iconName).foregroundStyle(.secondary) }
    }

    private var iconName: String {
        let type = group.type.lowercased()
        if type.contains("url") { return "speedometer" }
        if type.contains("fallback") { return "arrow.triangle.2.circlepath" }
        return "switch.2"
    }
}
