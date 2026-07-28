import SwiftUI

struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var isEditing: Bool
    var ruleTypes: [String]
    @Binding var draft: RuleEditorDraft
    var save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "编辑规则" : "添加规则")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("类型")
                        .foregroundStyle(.secondary)
                    Picker("类型", selection: $draft.type) {
                        ForEach(ruleTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                GridRow {
                    Text("值")
                        .foregroundStyle(.secondary)
                    TextField(draft.type == "MATCH" ? "MATCH 可为空" : "域名、IP、Provider 或进程名", text: $draft.value)
                        .disabled(draft.type == "MATCH")
                }
                GridRow {
                    Text("策略")
                        .foregroundStyle(.secondary)
                    TextField("DIRECT / REJECT / 策略组", text: $draft.policy)
                }
                GridRow {
                    Text("参数")
                        .foregroundStyle(.secondary)
                    TextField("no-resolve 等附加参数，逗号分隔", text: $draft.optionsText)
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
                .disabled(draft.policy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onChange(of: draft.type) {
            if draft.type == "MATCH" {
                draft.value = ""
            }
        }
    }
}
