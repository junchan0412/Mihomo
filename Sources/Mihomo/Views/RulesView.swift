import AppKit
import SwiftUI

struct RulesView: View {
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var selectedRuleIDs: Set<String> = []
    @State private var confirmsDeletion = false
    @State private var editorPresentation: RuleEditorPresentation?
    @State private var editorOriginalIndex: Int?
    @State private var editorType = "MATCH"
    @State private var editorValue = ""
    @State private var editorPolicy = "DIRECT"
    @State private var editorNote = ""
    @State private var selectedCategory: RuleTypeCategory?

    private let ruleTypes = [
        "DOMAIN-SUFFIX",
        "DOMAIN",
        "DOMAIN-KEYWORD",
        "IP-CIDR",
        "IP-CIDR6",
        "GEOIP",
        "GEOSITE",
        "RULE-SET",
        "PROCESS-NAME",
        "MATCH"
    ]

    private var entries: [RuleTableEntry] {
        store.rules.map(RuleTableEntry.init)
    }

    private var filteredEntries: [RuleTableEntry] {
        var result = entries
        if let selectedCategory {
            result = result.filter { $0.typeCategory == selectedCategory }
        }
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return result }
        return result.filter { $0.searchText.localizedCaseInsensitiveContains(text) }
    }

    private var hitTotal: Int {
        store.rules.reduce(0) { $0 + $1.hitCount }
    }

    private var categoryCounts: [(RuleTypeCategory, Int)] {
        let grouped = Dictionary(grouping: entries, by: \.typeCategory)
        return RuleTypeCategory.allCases.compactMap { category in
            guard let count = grouped[category]?.count, count > 0 else { return nil }
            return (category, count)
        }
    }

    private var selectedEntry: RuleTableEntry? {
        guard selectedRuleIDs.count == 1, let selectedRuleID = selectedRuleIDs.first else { return nil }
        return entries.first { $0.id == selectedRuleID }
    }

    private var selectedEntries: [RuleTableEntry] {
        entries.filter { selectedRuleIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 10) {
                ruleWorkspace
                bottomBar
            }
            .padding(16)
        }
        .navigationTitle("规则")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索规则类型、值或策略")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(\.workspaceCommands, commandContext)
        .onAppear {
            store.refreshConfigArtifacts()
            applyRuleFocusQuery()
        }
        .onChange(of: store.ruleFocusQuery) {
            applyRuleFocusQuery()
        }
        .onChange(of: store.rules) {
            selectedRuleIDs.formIntersection(Set(entries.map(\.id)))
        }
        .confirmationDialog("删除所选规则？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(selectedEntries.count) 条规则", role: .destructive) {
                let indices = selectedEntries.map(\.rule.index)
                selectedRuleIDs.removeAll()
                Task { await store.deleteActiveProfileRules(indices: indices, undoManager: undoManager) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("规则会从当前配置文件中移除。完成后可使用 Command-Z 撤销。")
        }
        .sheet(item: $editorPresentation) { presentation in
            RuleEditorSheet(
                isEditing: presentation.isEditing,
                ruleTypes: ruleTypes,
                ruleType: $editorType,
                ruleValue: $editorValue,
                rulePolicy: $editorPolicy,
                ruleNote: $editorNote,
                save: saveRuleEditor
            )
            .frame(width: 520)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("规则")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("\(store.rules.count) 条规则 · \(store.disabledRules.count) 条已禁用 · 命中 \(hitTotal)")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refreshConfigArtifacts()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            Button {
                Task { await store.restartCore() }
            } label: {
                Label("应用", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.activeProfile == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func applyRuleFocusQuery() {
        let query = store.ruleFocusQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return }
        searchText = query
        if let entry = entries.first(where: { $0.searchText.localizedCaseInsensitiveContains(query) }) {
            selectedRuleIDs = [entry.id]
        }
    }

    private var ruleTable: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: filteredEntries,
                selection: $selectedRuleIDs,
                columns: [
                    .init(title: "启用", width: 48, checked: { !$0.rule.disabled }) { entry in
                        selectedRuleIDs = [entry.id]
                        store.toggleRuleDisabled(entry.rule, undoManager: undoManager)
                    },
                    .init(title: "ID", width: 48, textColor: ruleTextColor) { "\($0.rule.index)" },
                    .init(title: "类型", width: 140, textColor: ruleTypeColor) { $0.type },
                    .init(title: "分类", width: 72, textColor: ruleTypeColor) { $0.typeCategory.title },
                    .init(title: "值", width: 260, textColor: ruleTextColor) { $0.displayValue.isEmpty ? "-" : $0.displayValue },
                    .init(title: "策略", width: 120, textColor: ruleTextColor) { $0.policy },
                    .init(title: "命中", width: 64, textColor: ruleHitColor) { $0.hitDisplay },
                    .init(title: "选项", width: 120, textColor: ruleTextColor) { $0.optionsText.isEmpty ? "-" : $0.optionsText },
                ],
                allowsMultipleSelection: true,
                onDoubleClick: beginEdit,
                onActivate: { selected in
                    guard let entry = selected.first else { return }
                    selectedRuleIDs = [entry.id]
                    beginEdit(entry)
                },
                onPreview: { selected in
                    guard let entry = selected.first else { return }
                    selectedRuleIDs = [entry.id]
                    beginEdit(entry)
                },
                onDelete: { _ in requestDeleteSelectedRules() },
                hasHorizontalScroller: false,
                contextMenuActions: ruleContextMenuActions
            )
        }
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if filteredEntries.isEmpty {
                ContentUnavailableView("没有规则", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private var ruleWorkspace: some View {
        VStack(spacing: 10) {
            categoryStrip
            ruleTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(MihomoUI.cardStroke, lineWidth: 1) }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "全部", count: entries.count, selected: selectedCategory == nil, color: .accentColor) {
                    selectedCategory = nil
                }
                ForEach(categoryCounts, id: \.0) { item in
                    categoryChip(title: item.0.title, count: item.1, selected: selectedCategory == item.0, color: item.0.color) {
                        selectedCategory = item.0
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(title: String, count: Int, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
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

    private func ruleTypeColor(_ entry: RuleTableEntry) -> NSColor? {
        if entry.rule.disabled { return .secondaryLabelColor }
        return NSColor(entry.typeBadgeColor)
    }

    private func ruleHitColor(_ entry: RuleTableEntry) -> NSColor? {
        if entry.rule.disabled { return .secondaryLabelColor }
        return entry.rule.hitCount > 0 ? .systemGreen : .secondaryLabelColor
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button {
                beginAddRule()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 18)
            }
            .help("添加规则")

            Button {
                deleteSelectedRule()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 18)
            }
            .help("删除选中规则")
            .disabled(selectedEntries.isEmpty)

            Button {
                if let selectedEntry {
                    beginEdit(selectedEntry)
                }
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 18)
            }
            .help("编辑选中规则")
            .disabled(selectedEntry == nil)

            Button {
                toggleSelectedRule()
            } label: {
                Image(systemName: selectedEntries.allSatisfy(\.rule.disabled) ? "checkmark.circle" : "slash.circle")
                    .frame(width: 18)
            }
            .help(selectedEntries.allSatisfy(\.rule.disabled) ? "启用选中规则" : "禁用选中规则")
            .disabled(selectedEntries.isEmpty)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Button {
                store.resetRuleHitStatistics()
            } label: {
                Label("重置计数", systemImage: "arrow.counterclockwise")
            }

            Spacer()

            Text("\(filteredEntries.count) / \(store.rules.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
    }

    private func ruleTextColor(_ entry: RuleTableEntry) -> NSColor? {
        entry.rule.disabled ? .secondaryLabelColor : nil
    }

    private func beginAddRule() {
        editorOriginalIndex = nil
        editorType = "MATCH"
        editorValue = ""
        editorPolicy = "DIRECT"
        editorNote = ""
        editorPresentation = .add
    }

    private func beginEdit(_ entry: RuleTableEntry) {
        selectedRuleIDs = [entry.id]
        editorOriginalIndex = entry.rule.index
        editorType = entry.type
        editorValue = entry.value
        editorPolicy = entry.policy
        editorNote = entry.optionsText
        editorPresentation = .edit(entry.rule.index)
    }

    private func saveRuleEditor() {
        let normalizedPolicy = editorPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedPolicy.isEmpty == false else { return }
        let rule = EditableProfileRule(
            index: editorOriginalIndex ?? store.rules.count + 1,
            type: editorType,
            payload: editorType == "MATCH" ? "" : editorValue.trimmingCharacters(in: .whitespacesAndNewlines),
            target: normalizedPolicy,
            options: parseOptions(editorNote)
        )
        Task {
            await store.upsertActiveProfileRule(originalIndex: editorOriginalIndex, rule: rule, undoManager: undoManager)
            if let entry = store.rules.map(RuleTableEntry.init).first(where: { $0.rule.index == rule.index }) {
                selectedRuleIDs = [entry.id]
            }
        }
    }

    private func deleteSelectedRule() {
        requestDeleteSelectedRules()
    }

    private func toggleSelectedRule() {
        guard selectedEntries.isEmpty == false else { return }
        let shouldDisable = selectedEntries.allSatisfy { $0.rule.disabled } == false
        store.setRulesDisabled(selectedEntries.map(\.rule), disabled: shouldDisable, undoManager: undoManager)
    }

    private func requestDeleteSelectedRules() {
        guard selectedEntries.isEmpty == false else { return }
        confirmsDeletion = true
    }

    private var ruleContextMenuActions: [AppKitTableContextAction<RuleTableEntry>] {
        [
            .init("启用") { entries in
                store.setRulesDisabled(entries.map(\.rule), disabled: false, undoManager: undoManager)
            },
            .init("停用") { entries in
                store.setRulesDisabled(entries.map(\.rule), disabled: true, undoManager: undoManager)
            },
            .init("编辑", isEnabled: { $0.count == 1 }) { entries in
                guard let entry = entries.first else { return }
                beginEdit(entry)
            },
            .init("复制规则") { entries in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entries.map(\.rule.content).joined(separator: "\n"), forType: .string)
            },
            .init("删除", isDestructive: true) { entries in
                selectedRuleIDs = Set(entries.map(\.id))
                requestDeleteSelectedRules()
            }
        ]
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: store.refreshConfigArtifacts,
            activateSelection: searchIsFocused || selectedEntry == nil ? nil : { if let selectedEntry { beginEdit(selectedEntry) } },
            previewSelection: searchIsFocused || selectedEntry == nil ? nil : { if let selectedEntry { beginEdit(selectedEntry) } },
            deleteSelection: searchIsFocused || selectedEntries.isEmpty ? nil : requestDeleteSelectedRules
        )
    }

    private func parseOptions(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}
