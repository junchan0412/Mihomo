import SwiftUI

extension ProfileStructureEditorView {
    var ruleEditor: some View {
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
}
