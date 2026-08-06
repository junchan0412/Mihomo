import SwiftUI

struct RulesView: View {
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @FocusState private var searchIsFocused: Bool
    @State private var selectedRuleIDs: Set<String> = []
    @State private var confirmsDeletion = false
    @State private var editorPresentation: RuleEditorPresentation?
    @State private var editorDraft = RuleEditorDraft()
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

    private func rulePresentation() -> RuleTablePresentation {
        RuleTablePresentation.make(
            rules: store.rules,
            selectedCategory: selectedCategory,
            searchText: searchText
        )
    }

    var body: some View {
        let presentation = rulePresentation()
        let selectedEntries = presentation.selectedEntries(for: selectedRuleIDs)
        let selectedEntry = presentation.selectedEntry(for: selectedRuleIDs)

        return VStack(spacing: 0) {
            RulesHeader(
                ruleCount: presentation.entries.count,
                disabledCount: store.disabledRules.count,
                hitTotal: presentation.hitTotal,
                canApply: store.activeProfile != nil,
                refresh: store.refreshConfigArtifacts,
                apply: { Task { await store.restartCore() } }
            )

            RuleTablePane(
                presentation: presentation,
                sourceIsEmpty: store.rules.isEmpty,
                selectedRuleIDs: $selectedRuleIDs,
                selectedCategory: $selectedCategory,
                selectedEntries: selectedEntries,
                selectedEntry: selectedEntry,
                actions: ruleTableActions
            )
            .padding(16)
        }
        .navigationTitle("规则")
        .background(MihomoUI.pageBackground)
        .searchable(text: $searchText, placement: .toolbar, prompt: "搜索规则类型、值或策略")
        .compatibleSearchFocused($searchIsFocused)
        .focusedSceneValue(
            \.workspaceCommands,
            commandContext(selectedEntries: selectedEntries, selectedEntry: selectedEntry)
        )
        .onAppear {
            store.refreshConfigArtifacts()
            applyRuleFocusQuery()
        }
        .onChange(of: store.ruleFocusQuery) {
            applyRuleFocusQuery()
        }
        .onChange(of: store.rules) {
            reconcileFilteredSelection()
        }
        .onChange(of: searchText) { reconcileFilteredSelection() }
        .onChange(of: selectedCategory) { reconcileFilteredSelection() }
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
                draft: $editorDraft,
                save: saveRuleEditor
            )
            .frame(width: 520)
        }
    }

    private func applyRuleFocusQuery() {
        let query = store.ruleFocusQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return }
        searchText = query
        let presentation = RuleTablePresentation.make(
            rules: store.rules,
            selectedCategory: nil,
            searchText: query
        )
        if let entry = presentation.filteredEntries.first {
            selectedRuleIDs = [entry.id]
        }
    }

    private func reconcileFilteredSelection() {
        let presentation = rulePresentation()
        selectedRuleIDs = TableSelection.reconciled(
            selectedRuleIDs,
            visibleIDs: presentation.filteredEntries.map(\.id)
        )
    }

    private func beginAddRule() {
        editorDraft = RuleEditorDraft()
        editorPresentation = .add
    }

    private func beginEdit(_ entry: RuleTableEntry) {
        selectedRuleIDs = [entry.id]
        editorDraft = RuleEditorDraft(entry: entry)
        editorPresentation = .edit(entry.rule.index)
    }

    private func saveRuleEditor() {
        let originalIndex = editorPresentation?.originalIndex
        guard let rule = editorDraft.makeRule(index: originalIndex ?? store.rules.count + 1) else { return }
        Task {
            await store.upsertActiveProfileRule(originalIndex: originalIndex, rule: rule, undoManager: undoManager)
            if let entry = store.rules.map(RuleTableEntry.init).first(where: { $0.rule.index == rule.index }) {
                selectedRuleIDs = [entry.id]
            }
        }
    }

    private func toggleSelectedRules(_ entries: [RuleTableEntry]) {
        guard entries.isEmpty == false else { return }
        let shouldDisable = entries.allSatisfy { $0.rule.disabled } == false
        store.setRulesDisabled(entries.map(\.rule), disabled: shouldDisable, undoManager: undoManager)
    }

    private func requestDeleteSelectedRules(_ entries: [RuleTableEntry]) {
        guard entries.isEmpty == false else { return }
        selectedRuleIDs = Set(entries.map(\.id))
        confirmsDeletion = true
    }

    private var ruleTableActions: RuleTableActions {
        RuleTableActions(
            toggleEnabled: { entry in
                store.toggleRuleDisabled(entry.rule, undoManager: undoManager)
            },
            add: beginAddRule,
            edit: beginEdit,
            delete: requestDeleteSelectedRules,
            toggleDisabled: toggleSelectedRules,
            setDisabled: { entries, disabled in
                store.setRulesDisabled(entries.map(\.rule), disabled: disabled, undoManager: undoManager)
            },
            resetHitStatistics: store.resetRuleHitStatistics
        )
    }

    private func commandContext(
        selectedEntries: [RuleTableEntry],
        selectedEntry: RuleTableEntry?
    ) -> WorkspaceCommandContext {
        WorkspaceCommandContext(
            search: {
                searchIsFocused = true
                MihomoSearchFocus.request()
            },
            refresh: store.refreshConfigArtifacts,
            activateSelection: searchIsFocused || selectedEntry == nil ? nil : { if let selectedEntry { beginEdit(selectedEntry) } },
            previewSelection: searchIsFocused || selectedEntry == nil ? nil : { if let selectedEntry { beginEdit(selectedEntry) } },
            deleteSelection: searchIsFocused || selectedEntries.isEmpty
                ? nil
                : { requestDeleteSelectedRules(selectedEntries) }
        )
    }

}
