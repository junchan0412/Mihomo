import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("诊断")
                        .font(.largeTitle.bold())
                    Text("检查核心、运行配置、系统代理快照、TUN 状态、Controller 和日志。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("运行诊断") {
                    Task { await store.runDiagnostics() }
                }
                .buttonStyle(.borderedProminent)

                Button("修复系统代理") {
                    Task { await store.repairSystemProxy() }
                }

                Button("验证 TUN 权限") {
                    Task { await store.verifyTunPrivileges() }
                }

                Button("回滚 TUN") {
                    Task { await store.restoreTunRecovery() }
                }
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
                    ContentUnavailableView("尚未运行诊断", systemImage: "stethoscope", description: Text("运行诊断以验证第三个 MVP 的运行状态。"))
                }
            }
        }
        .padding(24)
        .navigationTitle("诊断")
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
