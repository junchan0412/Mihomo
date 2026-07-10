import SwiftUI

struct RuleInspectorPane: View {
    var entry: RuleTableEntry?
    var add: () -> Void
    var edit: (RuleTableEntry) -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("规则信息").font(.headline)

            if let entry {
                inspectorRow("状态", entry.rule.disabled ? "已禁用" : "已启用")
                inspectorRow("类型", entry.type)
                inspectorRow("值", entry.value.isEmpty ? "-" : entry.value)
                inspectorRow("策略", entry.policy)
                inspectorRow("命中", "\(entry.rule.hitCount)")
                inspectorRow("选项", entry.note.isEmpty ? "-" : entry.note)
                Spacer()
                Button { edit(entry) } label: {
                    Label("通过 GUI 编辑", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive, action: delete) {
                    Label("删除规则", systemImage: "trash").frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "选择一条规则",
                    systemImage: "list.bullet.rectangle",
                    description: Text("双击规则也可以打开 GUI 编辑器。")
                )
                Spacer()
                Button(action: add) {
                    Label("新建规则", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.12))
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
