import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: DiagnosticWorkspaceTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("诊断").font(MihomoUI.Fonts.pageTitle)
                        Text("先定位问题，再执行对应修复；诊断包自动脱敏，可快速分享给支持方。")
                            .font(MihomoUI.Fonts.pageSubtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.exportDiagnosticBundle() } label: {
                        Label("导出诊断包", systemImage: "square.and.arrow.up")
                    }
                    if let url = store.lastDiagnosticBundleURL {
                        ShareLink(item: url) {
                            Label("分享", systemImage: "square.and.arrow.up.on.square")
                        }
                        Button {
                            QuickLookPreviewer.shared.present([url])
                        } label: {
                            Label("快速查看", systemImage: "eye")
                        }
                    }
                    Button { Task { await store.runDiagnostics() } } label: {
                        Label("运行诊断", systemImage: "stethoscope")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Picker("诊断分类", selection: $tab) {
                    ForEach(DiagnosticWorkspaceTab.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.segmented).frame(maxWidth: 560)
            }
            .padding(.horizontal, MihomoUI.pageHorizontalPadding).padding(.vertical, 14)
            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .overview: overview
                    case .results: results
                    }
                }
                .frame(maxWidth: 900, alignment: .topLeading)
                .padding(MihomoUI.pageHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("诊断")
        .background(MihomoUI.pageBackground)
        .focusedSceneValue(
            \.workspaceCommands,
            WorkspaceCommandContext(
                refresh: { Task { await store.runDiagnostics() } },
                previewSelection: store.lastDiagnosticBundleURL.map { url in
                    { QuickLookPreviewer.shared.present([url]) }
                }
            )
        )
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                diagnosticMetric("通过", count: store.diagnostics.filter { $0.state == .ok }.count, color: .green, icon: "checkmark.circle.fill")
                diagnosticMetric("警告", count: store.diagnostics.filter { $0.state == .warning }.count, color: .orange, icon: "exclamationmark.triangle.fill")
                diagnosticMetric("失败", count: store.diagnostics.filter { $0.state == .failed }.count, color: .red, icon: "xmark.octagon.fill")
            }
            SettingsSection(title: "推荐流程", subtitle: "诊断不会直接修改系统状态。", systemImage: "list.number") {
                SettingsRow("1") { Text("运行诊断并查看检查结果").foregroundStyle(.secondary) }
                SettingsRow("2") { Text("仅对异常项目执行对应修复").foregroundStyle(.secondary) }
                SettingsRow("3") { Text("仍无法解决时导出脱敏诊断包").foregroundStyle(.secondary) }
            }
            Text(store.diagnosticExportStatus).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.diagnostics.isEmpty {
                ContentUnavailableView("尚未运行诊断", systemImage: "stethoscope", description: Text("点击“运行诊断”检查核心、配置、网络接管与 Helper。"))
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ForEach(store.diagnostics) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: item.state)).foregroundStyle(color(for: item.state)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text(item.detail).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func diagnosticMetric(_ title: String, count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading) { Text("\(count)").font(.title2.bold()); Text(title).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(16).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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

enum DiagnosticWorkspaceTab: String, CaseIterable, Identifiable {
    case overview, results
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .results: return "检查结果"
        }
    }
    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .results: return "list.bullet.clipboard"
        }
    }
}

struct NetworkRepairCenterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmsSnapshotClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("网络修复中心", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
                Spacer()
                Button {
                    store.refreshNetworkTakeoverStates()
                } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(store.networkTakeoverStates) { state in
                    NetworkRepairStateCard(state: state)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.repairSystemProxy() }
                } label: {
                    Label("恢复代理", systemImage: "network.badge.shield.half.filled")
                }

                Button {
                    Task { await store.restoreSystemDNS() }
                } label: {
                    Label("恢复 DNS", systemImage: "globe.badge.chevron.backward")
                }

                Button {
                    Task { await store.restoreTunRecovery() }
                } label: {
                    Label("恢复 TUN 路由", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    confirmsSnapshotClear = true
                } label: {
                    Label("清理快照", systemImage: "trash")
                }

                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog("清理所有网络恢复快照？", isPresented: $confirmsSnapshotClear, titleVisibility: .visible) {
            Button("清理快照", role: .destructive) {
                store.clearNetworkRecoverySnapshots()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清理后将无法使用现有快照恢复系统代理、DNS 与 TUN 路由状态。")
        }
    }
}

struct NetworkRepairStateCard: View {
    var state: NetworkTakeoverState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: state.kind.systemImage)
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(state.kind.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }

            Text(state.desiredState)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(state.actualState)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Text(state.recoveryAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch state.health {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        case .inactive: return .secondary
        }
    }
}
