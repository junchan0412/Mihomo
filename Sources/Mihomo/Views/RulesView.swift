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
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return entries }
        return entries.filter { $0.searchText.localizedCaseInsensitiveContains(text) }
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
                Text("\(store.rules.count) 条规则，\(store.disabledRules.count) 条已禁用。")
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
                    .init(title: "ID", width: 52, textColor: ruleTextColor) { "\($0.rule.index)" },
                    .init(title: "类型", width: 124, textColor: ruleTextColor) { $0.type },
                    .init(title: "值", width: 280, textColor: ruleTextColor) { $0.displayValue.isEmpty ? "-" : $0.displayValue },
                    .init(title: "策略", width: 130, textColor: ruleTextColor) { $0.policy },
                    .init(title: "计数", width: 68, textColor: ruleTextColor) { "\($0.rule.hitCount)" },
                    .init(title: "注释", width: 140, textColor: ruleTextColor) { $0.note.isEmpty ? "-" : $0.note }
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
        ruleTable
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(MihomoUI.cardStroke, lineWidth: 1) }
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
