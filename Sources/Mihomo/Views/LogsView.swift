import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading) {
                Text("Logs")
                    .font(.largeTitle.bold())
                Text("High-volume log rendering uses AppKit NSTextView embedded in SwiftUI.")
                    .foregroundStyle(.secondary)
            }

            AppKitLogView(entries: store.logs)
                .frame(minHeight: 560)
        }
        .padding(24)
        .navigationTitle("Logs")
    }
}
