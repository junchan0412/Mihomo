import AppKit
import SwiftUI

struct RulesHeader: View {
    var ruleCount: Int
    var disabledCount: Int
    var hitTotal: Int
    var canApply: Bool
    var refresh: () -> Void
    var apply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("规则")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("\(ruleCount) 条规则 · \(disabledCount) 条已禁用 · 命中 \(hitTotal)")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: refresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Button(action: apply) {
                Label("应用", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct RuleTableActions {
    var toggleEnabled: (RuleTableEntry) -> Void
    var add: () -> Void
    var edit: (RuleTableEntry) -> Void
    var delete: ([RuleTableEntry]) -> Void
    var toggleDisabled: ([RuleTableEntry]) -> Void
    var setDisabled: ([RuleTableEntry], Bool) -> Void
    var resetHitStatistics: () -> Void
}

struct RuleTablePane: View {
    var presentation: RuleTablePresentation
    var sourceIsEmpty: Bool
    @Binding var selectedRuleIDs: Set<String>
    @Binding var selectedCategory: RuleTypeCategory?
    var selectedEntries: [RuleTableEntry]
    var selectedEntry: RuleTableEntry?
    var actions: RuleTableActions
    @State private var selectionAnchor: String?

    var body: some View {
        VStack(spacing: 10) {
            categoryStrip
            ruleTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
    }

    private var ruleTable: some View {
        Group {
            if presentation.filteredEntries.isEmpty {
                ContentUnavailableView(
                    sourceIsEmpty ? "没有规则" : "没有匹配的规则",
                    systemImage: sourceIsEmpty ? "list.bullet.rectangle" : "magnifyingglass",
                    description: Text(sourceIsEmpty ? "当前配置没有可显示的规则。" : "请调整分类或尝试其他搜索词。")
                )
            } else {
                MihomoListSurface(minHeight: 360) {
                    ForEach(presentation.filteredEntries) { entry in
                        ruleRow(entry)
                    }
                }
            }
        }
    }

    private func ruleRow(_ entry: RuleTableEntry) -> some View {
        MihomoSelectableRow(
            isSelected: selectedRuleIDs.contains(entry.id),
            select: { select(entry) },
            activate: { actions.edit(entry) }
        ) {
            HStack(spacing: 12) {
                Toggle(
                    "启用规则",
                    isOn: Binding(
                        get: { entry.rule.disabled == false },
                        set: { _ in
                            selectedRuleIDs = [entry.id]
                            selectionAnchor = entry.id
                            actions.toggleEnabled(entry)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)

                Image(systemName: entry.typeSystemImage)
                    .foregroundStyle(entry.rule.disabled ? Color.secondary : entry.typeBadgeColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.type)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(entry.rule.disabled ? .secondary : .primary)
                        MihomoRowBadge(title: entry.typeCategory.title, color: entry.typeBadgeColor)
                        if entry.rule.disabled {
                            MihomoRowBadge(title: "已停用")
                        }
                    }

                    Text(entry.value.isEmpty ? "匹配所有剩余流量" : entry.value)
                        .font(.callout)
                        .foregroundStyle(entry.rule.disabled ? .tertiary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Label(entry.policy, systemImage: "arrow.triangle.branch")
                        if entry.optionsText.isEmpty == false {
                            Text(entry.optionsText)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                MihomoRowMetadata(
                    primary: entry.rule.hitCount > 0 ? "命中 \(entry.rule.hitCount)" : "未命中",
                    secondary: "#\(entry.rule.index)",
                    primaryColor: entry.rule.hitCount > 0 && entry.rule.disabled == false ? .green : .secondary
                )

                MihomoRowActions {
                    Button {
                        selectedRuleIDs = [entry.id]
                        selectionAnchor = entry.id
                        actions.edit(entry)
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("编辑规则")

                    Menu {
                        Button(entry.rule.disabled ? "启用" : "停用") {
                            actions.setDisabled([entry], entry.rule.disabled == false)
                        }
                        Button("复制规则") { copyRules([entry]) }
                        Divider()
                        Button("删除", role: .destructive) { actions.delete([entry]) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .help("更多操作")
                }
            }
        }
        .contextMenu {
            Button(entry.rule.disabled ? "启用" : "停用") {
                actions.setDisabled([entry], entry.rule.disabled == false)
            }
            Button("编辑") { actions.edit(entry) }
            Button("复制规则") { copyRules([entry]) }
            Divider()
            Button("删除", role: .destructive) { actions.delete([entry]) }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(
                    title: "全部",
                    count: presentation.entries.count,
                    selected: selectedCategory == nil,
                    color: .accentColor
                ) {
                    selectedCategory = nil
                }
                ForEach(presentation.categoryCounts, id: \.0) { item in
                    categoryChip(
                        title: item.0.title,
                        count: item.1,
                        selected: selectedCategory == item.0,
                        color: item.0.color
                    ) {
                        selectedCategory = item.0
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button(action: actions.add) {
                Image(systemName: "plus")
                    .frame(width: 18)
            }
            .help("添加规则")

            Button {
                actions.delete(selectedEntries)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 18)
            }
            .help("删除选中规则")
            .disabled(selectedEntries.isEmpty)

            Button {
                guard let selectedEntry else { return }
                actions.edit(selectedEntry)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 18)
            }
            .help("编辑选中规则")
            .disabled(selectedEntry == nil)

            Button {
                actions.toggleDisabled(selectedEntries)
            } label: {
                Image(systemName: selectedEntries.allSatisfy(\.rule.disabled) ? "checkmark.circle" : "slash.circle")
                    .frame(width: 18)
            }
            .help(selectedEntries.allSatisfy(\.rule.disabled) ? "启用选中规则" : "禁用选中规则")
            .disabled(selectedEntries.isEmpty)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Button(action: actions.resetHitStatistics) {
                Label("重置计数", systemImage: "arrow.counterclockwise")
            }

            Spacer()

            Text("\(presentation.filteredEntries.count) / \(presentation.entries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
    }

    private func categoryChip(
        title: String,
        count: Int,
        selected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background((selected ? Color.white.opacity(0.2) : color.opacity(0.12)), in: Capsule())
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? color.opacity(0.18) : MihomoUI.cardFill, in: Capsule())
            .overlay {
                Capsule().stroke(selected ? color.opacity(0.8) : MihomoUI.cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func select(_ entry: RuleTableEntry) {
        let update = TableSelection.updated(
            selectedRuleIDs,
            clicking: entry.id,
            visibleIDs: presentation.filteredEntries.map(\.id),
            anchor: selectionAnchor,
            modifiers: NSEvent.modifierFlags
        )
        selectedRuleIDs = update.selection
        selectionAnchor = update.anchor
    }

    private func copyRules(_ entries: [RuleTableEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries.map(\.rule.content).joined(separator: "\n"), forType: .string)
    }

}
