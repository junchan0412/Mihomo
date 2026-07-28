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

    var body: some View {
        VStack(spacing: 10) {
            categoryStrip
            ruleTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(MihomoUI.cardStroke, lineWidth: 1)
                }
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
                AppKitTable(
                    rows: presentation.filteredEntries,
                    selection: $selectedRuleIDs,
                    columns: columns,
                    allowsMultipleSelection: true,
                    onDoubleClick: actions.edit,
                    onActivate: activateFirst,
                    onPreview: activateFirst,
                    onDelete: actions.delete,
                    hasHorizontalScroller: false,
                    contextMenuActions: contextMenuActions
                )
            }
        }
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
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

    private var columns: [AppKitTableColumn<RuleTableEntry>] {
        [
            .init(title: "启用", width: 48, checked: { !$0.rule.disabled }) { entry in
                selectedRuleIDs = [entry.id]
                actions.toggleEnabled(entry)
            },
            .init(title: "ID", width: 48, textColor: ruleTextColor) { "\($0.rule.index)" },
            .init(title: "类型", width: 140, textColor: ruleTypeColor) { $0.type },
            .init(title: "分类", width: 72, textColor: ruleTypeColor) { $0.typeCategory.title },
            .init(title: "值", width: 260, textColor: ruleTextColor) { $0.displayValue.isEmpty ? "-" : $0.displayValue },
            .init(title: "策略", width: 120, textColor: ruleTextColor) { $0.policy },
            .init(title: "命中", width: 64, textColor: ruleHitColor) { $0.hitDisplay },
            .init(title: "选项", width: 120, textColor: ruleTextColor) { $0.optionsText.isEmpty ? "-" : $0.optionsText }
        ]
    }

    private var contextMenuActions: [AppKitTableContextAction<RuleTableEntry>] {
        [
            .init("启用") { actions.setDisabled($0, false) },
            .init("停用") { actions.setDisabled($0, true) },
            .init("编辑", isEnabled: { $0.count == 1 }) { entries in
                guard let entry = entries.first else { return }
                actions.edit(entry)
            },
            .init("复制规则") { copyRules($0) },
            .init("删除", isDestructive: true, action: actions.delete)
        ]
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

    private func activateFirst(_ entries: [RuleTableEntry]) {
        guard let entry = entries.first else { return }
        selectedRuleIDs = [entry.id]
        actions.edit(entry)
    }

    private func copyRules(_ entries: [RuleTableEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries.map(\.rule.content).joined(separator: "\n"), forType: .string)
    }

    private func ruleTextColor(_ entry: RuleTableEntry) -> NSColor? {
        entry.rule.disabled ? .secondaryLabelColor : nil
    }

    private func ruleTypeColor(_ entry: RuleTableEntry) -> NSColor? {
        if entry.rule.disabled { return .secondaryLabelColor }
        return NSColor(entry.typeBadgeColor)
    }

    private func ruleHitColor(_ entry: RuleTableEntry) -> NSColor? {
        if entry.rule.disabled { return .secondaryLabelColor }
        return entry.rule.hitCount > 0 ? .systemGreen : .secondaryLabelColor
    }
}
