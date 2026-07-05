import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Diagnostics")
                        .font(.largeTitle.bold())
                    Text("Check binary, runtime config, network services, and controller reachability.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Diagnostics") {
                    Task { await store.runDiagnostics() }
                }
                .buttonStyle(.borderedProminent)
            }

            List(store.diagnostics) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: item.state))
                        .foregroundStyle(color(for: item.state))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.detail)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            .overlay {
                if store.diagnostics.isEmpty {
                    ContentUnavailableView("No Diagnostics Yet", systemImage: "stethoscope", description: Text("Run diagnostics to verify the MVP setup."))
                }
            }
        }
        .padding(24)
        .navigationTitle("Diagnostics")
    }

    private func icon(for state: DiagnosticState) -> String {
        switch state {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for state: DiagnosticState) -> Color {
        switch state {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}
