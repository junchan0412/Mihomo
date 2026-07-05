import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedConnectionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Activity")
                        .font(.largeTitle.bold())
                    Text("\(store.connections.count) connections  ·  ↓ \(Formatters.rate(store.downloadRate))  ·  ↑ \(Formatters.rate(store.uploadRate))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await store.refreshController() }
                }
                Button("Close All") {
                    Task { await store.closeAllConnections() }
                }
            }

            HStack(spacing: 12) {
                StatusCard(title: "Connections", value: "\(store.connections.count)", systemImage: "link", isGood: true)
                StatusCard(title: "Download", value: Formatters.rate(store.downloadRate), systemImage: "arrow.down", isGood: true)
                StatusCard(title: "Upload", value: Formatters.rate(store.uploadRate), systemImage: "arrow.up", isGood: true)
            }

            AppKitTable(
                rows: store.connections,
                selection: $selectedConnectionID,
                columns: [
                    .init(title: "Host", width: 230) { $0.host },
                    .init(title: "Process", width: 170) { $0.process },
                    .init(title: "Rule", width: 170) { $0.rule },
                    .init(title: "Chain", width: 280) { $0.chain.isEmpty ? "-" : $0.chain },
                    .init(title: "Traffic", width: 190) { "\($0.download.byteString) ↓  \($0.upload.byteString) ↑" }
                ]
            )
            .overlay {
                if store.connections.isEmpty {
                    ContentUnavailableView("No Connections", systemImage: "waveform.path.ecg")
                }
            }
        }
        .padding(24)
        .navigationTitle("Activity")
    }
}

private extension Int64 {
    var byteString: String { Formatters.bytes(self) }
}
