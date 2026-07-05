import SwiftUI

struct ConfigFragmentsWindowView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("覆写管理")
                        .font(.title3.bold())
                    Text("\(store.configFragments.count) 个片段，\(store.configFragments.filter(\.enabled).count) 个启用。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ConfigFragmentsEditorView()
                .environmentObject(store)
                .padding(16)
        }
        .navigationTitle("覆写管理")
    }
}
