import SwiftUI

struct PolicyGroupEditorSheet: View {
    var profileName: String
    @Binding var content: String
    var cancel: () -> Void
    var save: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("编辑策略组").font(.title2.weight(.semibold))
                    Text("\(profileName) · 通过 GUI 管理策略组、候选节点与规则引用。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: cancel)
                Button("保存到配置", action: save)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            Divider()
            ProfileStructureEditorView(content: $content)
                .padding(16)
        }
    }
}
