import SwiftUI

struct RuleEditorSheet: View {
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
                    Text("参数")
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
