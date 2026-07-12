import SwiftUI

struct OverridesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("覆写")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("集中管理运行时 YAML 与 JavaScript 覆写；列表顺序即应用顺序，后项可覆盖前项。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }

            ConfigFragmentsEditorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, MihomoUI.pageVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("覆写")
    }
}
