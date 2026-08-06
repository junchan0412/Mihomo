import SwiftUI

struct NetworkSecurityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings.default
    @State private var lastSavedSettings = AppSettings.default
    @State private var selectedSnapshotKind: NetworkSecuritySnapshotKind? = .systemProxy

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch store.networkWorkspaceTab {
                    case .overview:
                        NetworkSecurityOverviewPane()
                            .environmentObject(store)
                    case .dns:
                        NetworkSecurityDNSPane(draft: $draft)
                            .environmentObject(store)
                    case .domainSniffing:
                        DomainSniffingSettingsView(draft: $draft)
                            .environmentObject(store)
                    case .recovery:
                        NetworkSecurityRecoveryPane(
                            draft: $draft,
                            selectedSnapshotKind: $selectedSnapshotKind
                        )
                        .environmentObject(store)
                    }
                }
                .frame(maxWidth: 900, alignment: .topLeading)
                .padding(.horizontal, MihomoUI.pageHorizontalPadding)
                .padding(.vertical, MihomoUI.pageVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("网络")
        .background(MihomoUI.pageBackground)
        .focusedSceneValue(
            \.workspaceCommands,
            WorkspaceCommandContext(refresh: { store.refreshNetworkTakeoverStates(force: true) })
        )
        .onAppear {
            synchronizeDraft(with: store.settings, force: true)
            store.refreshNetworkTakeoverStates()
        }
        .onReceive(store.$settings) { synchronizeDraft(with: $0, force: false) }
        .confirmationDialog(
            "TUN 路由恢复失败，仍要关闭 TUN？",
            isPresented: forceTunDisableDialog,
            titleVisibility: .visible
        ) {
            Button("强制关闭 TUN", role: .destructive) {
                Task { await store.setTunEnabled(false, force: true) }
            }
            Button("取消", role: .cancel) {
                store.pendingTunDisableRecoveryError = nil
            }
        } message: {
            Text(store.pendingTunDisableRecoveryError ?? "系统路由快照尚未恢复，强制继续可能造成暂时断网。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("网络").font(MihomoUI.Fonts.pageTitle)
                    Text("管理系统代理 / TUN 接管、DNS、域名嗅探与异常恢复。")
                        .font(MihomoUI.Fonts.pageSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NetworkHealthBadge(health: store.networkSecurityOverallHealth)
            }

            HStack {
                Picker("网络分类", selection: $store.networkWorkspaceTab) {
                    ForEach(NetworkWorkspaceTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 680)
                Spacer()
                Button { store.refreshNetworkTakeoverStates(force: true) } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(.horizontal, MihomoUI.pageHorizontalPadding)
        .padding(.vertical, 14)
    }

    private func synchronizeDraft(with settings: AppSettings, force: Bool) {
        if force || draft == lastSavedSettings {
            draft = settings
        }
        lastSavedSettings = settings
    }

    private var forceTunDisableDialog: Binding<Bool> {
        Binding(
            get: { store.pendingTunDisableRecoveryError != nil },
            set: { isPresented in
                if isPresented == false {
                    store.pendingTunDisableRecoveryError = nil
                }
            }
        )
    }
}
