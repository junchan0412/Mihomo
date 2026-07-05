import AppKit
import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedRuleIndex: Int?
    @State private var showingRuleEditor = false
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
        guard let selectedRuleIndex else { return nil }
        return entries.first { $0.rule.index == selectedRuleIndex }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 10) {
                ruleTable
                bottomBar
            }
            .padding(16)
        }
        .navigationTitle("规则")
        .onAppear {
            store.refreshConfigArtifacts()
        }
        .onChange(of: store.rules) {
            guard let selectedRuleIndex else { return }
            if store.rules.contains(where: { $0.index == selectedRuleIndex }) == false {
                self.selectedRuleIndex = nil
            }
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorSheet(
                isEditing: editorOriginalIndex != nil,
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
                    .font(.title2.bold())
                Text("\(store.rules.count) 条规则，\(store.disabledRules.count) 条已禁用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            searchField

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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索规则", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: 260)
        .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
    }

    private var ruleTable: some View {
        VStack(spacing: 0) {
            AppKitTable(
                rows: filteredEntries,
                selection: ruleSelectionBinding,
                columns: [
                    .init(title: "状态", width: 62, textColor: ruleTextColor) { $0.rule.disabled ? "禁用" : "启用" },
                    .init(title: "ID", width: 52, textColor: ruleTextColor) { "\($0.rule.index)" },
                    .init(title: "类型", width: 124, textColor: ruleTextColor) { $0.type },
                    .init(title: "值", width: 250, textColor: ruleTextColor) { $0.value.isEmpty ? "-" : $0.value },
                    .init(title: "策略", width: 130, textColor: ruleTextColor) { $0.policy },
                    .init(title: "计数", width: 68, textColor: ruleTextColor) { "\($0.rule.hitCount)" },
                    .init(title: "注释", width: 140, textColor: ruleTextColor) { $0.note.isEmpty ? "-" : $0.note }
                ],
                onDoubleClick: beginEdit,
                hasHorizontalScroller: false
            )
        }
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if filteredEntries.isEmpty {
                ContentUnavailableView("没有规则", systemImage: "list.bullet.rectangle")
            }
        }
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
            .disabled(selectedRuleIndex == nil)

            Button {
                if let selectedEntry {
                    beginEdit(selectedEntry)
                }
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 18)
            }
            .help("编辑选中规则")
            .disabled(selectedRuleIndex == nil)

            Button {
                toggleSelectedRule()
            } label: {
                Label(selectedEntry?.rule.disabled == true ? "启用" : "禁用", systemImage: selectedEntry?.rule.disabled == true ? "checkmark.circle" : "slash.circle")
            }
            .disabled(selectedRuleIndex == nil)

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

    private var ruleSelectionBinding: Binding<RuleTableEntry.ID?> {
        Binding(
            get: { selectedEntry?.id },
            set: { id in
                guard let id,
                      let entry = filteredEntries.first(where: { $0.id == id })
                else {
                    selectedRuleIndex = nil
                    return
                }
                selectedRuleIndex = entry.rule.index
            }
        )
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
        showingRuleEditor = true
    }

    private func beginEdit(_ entry: RuleTableEntry) {
        selectedRuleIndex = entry.rule.index
        editorOriginalIndex = entry.rule.index
        editorType = entry.type
        editorValue = entry.value
        editorPolicy = entry.policy
        editorNote = entry.note
        showingRuleEditor = true
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
            await store.upsertActiveProfileRule(originalIndex: editorOriginalIndex, rule: rule)
            selectedRuleIndex = rule.index
        }
    }

    private func deleteSelectedRule() {
        guard let selectedRuleIndex else { return }
        Task {
            await store.deleteActiveProfileRule(index: selectedRuleIndex)
            self.selectedRuleIndex = nil
        }
    }

    private func toggleSelectedRule() {
        guard let selectedEntry else { return }
        store.toggleRuleDisabled(selectedEntry.rule)
    }

    private func parseOptions(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}

private struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var isEditing: Bool
    var ruleTypes: [String]
    @Binding var ruleType: String
    @Binding var ruleValue: String
    @Binding var rulePolicy: String
    @Binding var ruleNote: String
    var save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "编辑规则" : "添加规则")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("类型")
                        .foregroundStyle(.secondary)
                    Picker("类型", selection: $ruleType) {
                        ForEach(ruleTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("值")
                        .foregroundStyle(.secondary)
                    TextField(ruleType == "MATCH" ? "MATCH 可为空" : "域名、IP、Provider 或进程名", text: $ruleValue)
                        .disabled(ruleType == "MATCH")
                }
                GridRow {
                    Text("策略")
                        .foregroundStyle(.secondary)
                    TextField("DIRECT / REJECT / 策略组", text: $rulePolicy)
                }
                GridRow {
                    Text("注释")
                        .foregroundStyle(.secondary)
                    TextField("no-resolve 等附加参数，逗号分隔", text: $ruleNote)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(rulePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onChange(of: ruleType) {
            if ruleType == "MATCH" {
                ruleValue = ""
            }
        }
    }
}

private struct RuleTableEntry: Identifiable, Hashable {
    var rule: RuleItem
    var type: String
    var value: String
    var policy: String
    var options: [String]

    var id: String { rule.id }
    var note: String { options.joined(separator: ", ") }
    var searchText: String {
        [rule.content, type, value, policy, note, "\(rule.index)", "\(rule.hitCount)"].joined(separator: " ")
    }

    init(rule: RuleItem) {
        self.rule = rule
        let parts = rule.content.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 3 {
            type = parts[0]
            value = parts[1]
            policy = parts[2]
            options = Array(parts.dropFirst(3))
        } else if parts.count == 2 {
            type = parts[0]
            value = ""
            policy = parts[1]
            options = []
        } else {
            type = parts.first ?? "MATCH"
            value = ""
            policy = "DIRECT"
            options = []
        }
    }
}
