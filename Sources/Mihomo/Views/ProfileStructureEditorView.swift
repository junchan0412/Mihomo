import SwiftUI

struct ProfileStructureEditorView: View {
    @Binding var content: String
    @State private var snapshot = ProfileStructureSnapshot(groups: [], rules: [], proxyNames: [])
    @State private var selectedGroupName: String?
    @State private var groupName = ""
    @State private var groupType = "select"
    @State private var groupProxies = ""
    @State private var groupUses = ""
    @State private var replacementTarget = "DIRECT"
    @State private var deleteReferencedRules = false
    @State private var pendingGroupDelete = false
    @State private var selectedRuleIndex: Int?
    @State private var ruleType = "MATCH"
    @State private var rulePayload = ""
    @State private var ruleTarget = "DIRECT"
    @State private var ruleOptions = ""
    @State private var errorMessage = ""

    private let editor = ProfileYAMLStructureEditor()
    private let qualityAnalyzer = ProfileQualityAnalyzer()
    private let fragmentStore = ConfigFragmentStore()
    private let ruleTypes = ["DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6", "GEOIP", "GEOSITE", "RULE-SET", "PROCESS-NAME", "MATCH"]
    private let groupTypes = ["select", "url-test", "fallback", "load-balance", "relay"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HSplitView {
                groupEditor
                    .frame(minWidth: 300, idealWidth: 360)
                ruleEditor
                    .frame(minWidth: 360, idealWidth: 460)
            }

            if errorMessage.isEmpty == false {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: content) {
            reload()
        }
        .confirmationDialog("删除策略组", isPresented: $pendingGroupDelete, titleVisibility: .visible) {
            Button(deleteReferencedRules ? "删除策略组和引用规则" : "删除并替换引用规则", role: .destructive) {
                deleteSelectedGroupConfirmed()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var groupEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("策略组")
                    .font(.headline)
                Spacer()
                Button {
                    resetGroupForm()
                } label: {
                    Label("新增", systemImage: "plus")
                }
            }

            List(snapshot.groups, selection: Binding(
                get: { selectedGroupName },
                set: { name in
                    selectedGroupName = name
                    if let name, let group = snapshot.groups.first(where: { $0.name == name }) {
                        load(group)
                    }
                }
            )) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                    Text("\(group.type) · 节点 \(group.proxies.count) · Provider \(group.uses.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(group.name as String?)
            }
            .frame(minHeight: 140)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("名称")
                    TextField("策略组名称", text: $groupName)
                }
                GridRow {
                    Text("类型")
                    Picker("类型", selection: $groupType) {
                        ForEach(groupTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("节点")
                    TextField("DIRECT, 节点名...", text: $groupProxies)
                }
                GridRow {
                    Text("Provider")
                    TextField("provider 名称，逗号分隔", text: $groupUses)
                }
                GridRow {
                    Text("引用处理")
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("删除引用该策略组的规则", isOn: $deleteReferencedRules)
                        Picker("替换为", selection: $replacementTarget) {
                            ForEach(deleteTargets, id: \.self) { target in
                                Text(target).tag(target)
                            }
                        }
                        .disabled(deleteReferencedRules)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    saveGroup()
                } label: {
                    Label(selectedGroupName == nil ? "添加策略组" : "保存策略组", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    requestDeleteGroup()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedGroupName == nil)
            }
        }
    }

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("规则")
                    .font(.headline)
                Spacer()
                Button {
                    resetRuleForm()
                } label: {
                    Label("新增", systemImage: "plus")
                }
            }

            List(snapshot.rules, selection: Binding(
                get: { selectedRuleIndex },
                set: { index in
                    selectedRuleIndex = index
                    if let index, let rule = snapshot.rules.first(where: { $0.index == index }) {
                        load(rule)
                    }
                }
            )) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.content)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    Text("#\(rule.index) · \(rule.target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(rule.index as Int?)
            }
            .frame(minHeight: 140)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("类型")
                    Picker("类型", selection: $ruleType) {
                        ForEach(ruleTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("匹配")
                    TextField(ruleType == "MATCH" ? "MATCH 可为空" : "域名/IP/Provider", text: $rulePayload)
                }
                GridRow {
                    Text("策略")
                    Picker("策略", selection: $ruleTarget) {
                        ForEach(ruleTargets, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("附加")
                    TextField("no-resolve 等，逗号分隔", text: $ruleOptions)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    saveRule()
                } label: {
                    Label(selectedRuleIndex == nil ? "添加规则" : "保存规则", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    deleteSelectedRule()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedRuleIndex == nil)
            }
        }
    }

    private var deleteTargets: [String] {
        ruleTargets.filter { $0 != selectedGroupName }
    }

    private var ruleTargets: [String] {
        var values = ["DIRECT", "REJECT"]
        values.append(contentsOf: snapshot.groups.map(\.name))
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private var affectedRuleCount: Int {
        guard let selectedGroupName else { return 0 }
        return snapshot.rules.filter { $0.target == selectedGroupName }.count
    }

    private var deleteMessage: String {
        guard let selectedGroupName else { return "" }
        if affectedRuleCount == 0 {
            return "确定删除策略组 \(selectedGroupName)？"
        }
        if deleteReferencedRules {
            return "\(affectedRuleCount) 条规则正在使用 \(selectedGroupName)，确认同时删除这些规则？"
        }
        return "\(affectedRuleCount) 条规则正在使用 \(selectedGroupName)，确认将它们替换为 \(replacementTarget)？"
    }

    private func reload() {
        do {
            snapshot = try editor.snapshot(content: content)
            errorMessage = ""
            if selectedGroupName == nil, let first = snapshot.groups.first {
                selectedGroupName = first.name
                load(first)
            }
            if selectedRuleIndex == nil, let first = snapshot.rules.first {
                selectedRuleIndex = first.index
                load(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ group: EditablePolicyGroup) {
        groupName = group.name
        groupType = group.type
        groupProxies = group.proxies.joined(separator: ", ")
        groupUses = group.uses.joined(separator: ", ")
        if replacementTarget == group.name {
            replacementTarget = deleteTargets.first ?? "DIRECT"
        }
    }

    private func load(_ rule: EditableProfileRule) {
        ruleType = rule.type
        rulePayload = rule.payload
        ruleTarget = rule.target
        ruleOptions = rule.options.joined(separator: ", ")
    }

    private func resetGroupForm() {
        selectedGroupName = nil
        groupName = ""
        groupType = "select"
        groupProxies = "DIRECT"
        groupUses = ""
        replacementTarget = deleteTargets.first ?? "DIRECT"
        deleteReferencedRules = false
    }

    private func resetRuleForm() {
        selectedRuleIndex = nil
        ruleType = "MATCH"
        rulePayload = ""
        ruleTarget = ruleTargets.first ?? "DIRECT"
        ruleOptions = ""
    }

    private func saveGroup() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            errorMessage = "策略组名称不能为空。"
            return
        }
        do {
            content = try editor.upsertGroup(
                content: content,
                originalName: selectedGroupName,
                group: EditablePolicyGroup(
                    name: trimmedName,
                    type: groupType,
                    proxies: parseList(groupProxies),
                    uses: parseList(groupUses)
                )
            )
            selectedGroupName = trimmedName
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestDeleteGroup() {
        guard selectedGroupName != nil else { return }
        if affectedRuleCount > 0 {
            pendingGroupDelete = true
        } else {
            deleteSelectedGroupConfirmed()
        }
    }

    private func deleteSelectedGroupConfirmed() {
        guard let selectedGroupName else { return }
        do {
            content = try editor.deleteGroup(
                content: content,
                name: selectedGroupName,
                replacement: deleteReferencedRules ? nil : replacementTarget,
                deleteRules: deleteReferencedRules
            )
            resetGroupForm()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRule() {
        let normalizedTarget = ruleTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTarget.isEmpty == false else {
            errorMessage = "规则策略不能为空。"
            return
        }
        let rule = EditableProfileRule(
            index: selectedRuleIndex ?? snapshot.rules.count + 1,
            type: ruleType,
            payload: ruleType == "MATCH" ? "" : rulePayload.trimmingCharacters(in: .whitespacesAndNewlines),
            target: normalizedTarget,
            options: parseList(ruleOptions)
        )
        let providers = fragmentStore.parseProviders(profileContent: content)
        let issues = qualityAnalyzer.validateRule(rule, snapshot: snapshot, providers: providers)
        if let blockingIssue = issues.first(where: { $0.severity == .error }) {
            errorMessage = "\(blockingIssue.title)：\(blockingIssue.detail)"
            return
        }
        do {
            content = try editor.upsertRule(
                content: content,
                originalIndex: selectedRuleIndex,
                rule: rule
            )
            reload()
            if let warning = issues.first {
                errorMessage = "\(warning.title)：\(warning.detail)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedRule() {
        guard let selectedRuleIndex else { return }
        do {
            content = try editor.deleteRule(content: content, index: selectedRuleIndex)
            resetRuleForm()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}
