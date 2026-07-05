import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedKind = "全部"

    private var visibleProviders: [ProviderItem] {
        selectedKind == "全部" ? store.providers : store.providers.filter { $0.kind == selectedKind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("资源")
                        .font(.largeTitle.bold())
                    Text("管理 Proxy Provider 与 Rule Provider。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("类型", selection: $selectedKind) {
                    Text("全部").tag("全部")
                    Text("Proxy").tag("Proxy")
                    Text("Rule").tag("Rule")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button {
                    store.refreshConfigArtifacts()
                } label: {
                    Label("本地解析", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    Task { await store.refreshProvidersFromController() }
                } label: {
                    Label("读取 Controller", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
            }

            List(visibleProviders) { provider in
                HStack(spacing: 14) {
                    Image(systemName: provider.kind == "Proxy" ? "point.3.connected.trianglepath.dotted" : "list.bullet.clipboard")
                        .foregroundStyle(provider.kind == "Proxy" ? .blue : .green)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(provider.name)
                                .font(.headline)
                            Text(provider.kind)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(provider.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        Task { await store.updateProvider(provider) }
                    } label: {
                        Label("更新", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isCoreRunning == false)
                }
                .padding(.vertical, 6)
            }
            .overlay {
                if visibleProviders.isEmpty {
                    ContentUnavailableView("没有 Provider", systemImage: "shippingbox", description: Text("本地配置未声明 Provider，或 Controller 当前不可用。"))
                }
            }
        }
        .padding(24)
        .navigationTitle("资源")
        .onAppear {
            store.refreshConfigArtifacts()
        }
    }
}
