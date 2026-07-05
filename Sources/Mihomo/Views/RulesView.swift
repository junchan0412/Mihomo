import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""

    private var filteredRules: [RuleItem] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return store.rules }
        return store.rules.filter { $0.content.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("规则")
                        .font(.largeTitle.bold())
                    Text("\(store.rules.count) 条规则，\(store.disabledRules.count) 条已禁用。")
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

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索规则", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            List(filteredRules) { rule in
                HStack(spacing: 12) {
                    Text("\(rule.index)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)

                    Toggle(isOn: Binding(
                        get: { rule.disabled == false },
                        set: { _ in store.toggleRuleDisabled(rule) }
                    )) {
                        Text(rule.content)
                            .font(.system(.body, design: .monospaced))
                            .strikethrough(rule.disabled)
                            .foregroundStyle(rule.disabled ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    Text("\(rule.hitCount)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(rule.hitCount > 0 ? .primary : .secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
            .overlay {
                if filteredRules.isEmpty {
                    ContentUnavailableView("没有规则", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .padding(24)
        .navigationTitle("规则")
        .onAppear {
            store.refreshConfigArtifacts()
        }
    }
}
