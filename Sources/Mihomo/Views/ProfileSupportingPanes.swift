import SwiftUI

struct RemoteProfileImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("从 URL 导入配置")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("名称")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                    TextField("可选", text: $store.newRemoteName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("URL")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                    TextField("https://example.com/profile.yaml", text: $store.newRemoteURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 420)
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button {
                    Task {
                        await store.addRemoteProfile()
                        dismiss()
                    }
                } label: {
                    Label("导入", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

struct ProfileRefreshQueueStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Label(store.profileAutoRefreshStatus, systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if store.profileRefreshFailureCount > 0 {
                Label("\(store.profileRefreshFailureCount) 个失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Spacer()

            if let job = store.profileRefreshQueue.first {
                Text("\(job.profileName)：\(job.state.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ProfileSummaryPane: View {
    var profile: ProfileItem?
    var stats: ProfileStats?
    var editProfile: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Label(profile?.name ?? "未选择配置", systemImage: "doc.text")
                    .font(.headline)
                    .lineLimit(1)
                Button {
                    editProfile()
                } label: {
                    Label("打开编辑器", systemImage: "square.and.pencil")
                }
                .disabled(profile == nil)
            }
            .frame(width: 140, alignment: .leading)

            if profile == nil {
                Text("选择一个配置后查看规则、策略组、节点和 Provider 统计。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = stats?.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Divider().frame(height: 64)

                HStack(spacing: 22) {
                    ProfileMetric(title: "规则", value: "\(stats?.ruleCount ?? 0)")
                    ProfileMetric(title: "策略组", value: "\(stats?.policyGroupCount ?? 0)")
                    ProfileMetric(title: "节点", value: "\(stats?.proxyCount ?? 0)")
                    ProfileMetric(title: "Provider", value: "\(statsProviderCount)")
                }
                .frame(width: 270)

                Divider().frame(height: 64)

                HStack(spacing: 18) {
                    ProfileSmallFact(title: "类型", value: profile?.source == .remote ? "远程" : "本地")
                    ProfileSmallFact(title: "行数", value: "\(stats?.lineCount ?? 0)")
                    ProfileSmallFact(title: "大小", value: Formatters.bytes(Int64(stats?.fileSize ?? 0)))
                    ProfileSmallFact(title: "更新", value: profile.map { Formatters.shortDate.string(from: $0.updatedAt) } ?? "-")
                }
                .frame(width: 280)
            }
        }
        .padding(14)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var statsProviderCount: Int {
        (stats?.proxyProviderCount ?? 0) + (stats?.ruleProviderCount ?? 0)
    }
}

/* 覆写编辑器已迁移到独立主导航页面。 */
private struct RemovedConfigFragmentsSummaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedFragmentID: UUID?
    var openEditor: () -> Void

    private var selectedFragment: ConfigFragment? {
        guard let selectedFragmentID else { return store.configFragments.first }
        return store.configFragments.first { $0.id == selectedFragmentID } ?? store.configFragments.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("覆写列表", systemImage: "square.stack.3d.up")
                    .font(.headline)

                HStack(spacing: 12) {
                    Toggle("YAML", isOn: overrideBinding(\.yamlOverrideEnabled))
                    Toggle("JS Transform", isOn: overrideBinding(\.jsOverrideEnabled))
                }
                .toggleStyle(.checkbox)

                Spacer()
                Button {
                    openEditor()
                } label: {
                    Label("管理", systemImage: "slider.horizontal.3")
                }
            }

            HStack(alignment: .top, spacing: 0) {
                fragmentList
                    .frame(width: 300, alignment: .topLeading)
                    .frame(minHeight: 150, alignment: .topLeading)

                Divider()
                    .padding(.horizontal, 14)

                fragmentDetail
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            }
        }
        .padding(12)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
        .onAppear { ensureSelection() }
        .onChange(of: store.configFragments) { ensureSelection() }
    }

    private var fragmentList: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("覆写片段")
                    .font(MihomoUI.Fonts.bodyMedium)
                Spacer()
                Text("\(store.configFragments.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if store.configFragments.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("没有覆写")
                        .font(.callout.weight(.medium))
                    Text("点击“管理”添加 YAML 或 JS Transform。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
            } else {
                ForEach(store.configFragments.prefix(5)) { fragment in
                    Button {
                        selectedFragmentID = fragment.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(fragment.enabled ? Color.green : Color.secondary.opacity(0.45))
                                .frame(width: 7, height: 7)
                            Text(fragment.name)
                                .font(MihomoUI.Fonts.bodyMedium)
                                .lineLimit(1)
                            Spacer()
                            Text(fragment.kind.title)
                                .font(MihomoUI.Fonts.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedFragment?.id == fragment.id ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var fragmentDetail: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("覆写信息", systemImage: "info.circle")
                    .font(MihomoUI.Fonts.bodyMedium)
                Spacer()
                Text("已启用 \(store.configFragments.filter(\.enabled).count) · 禁用规则 \(store.disabledRules.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let fragment = selectedFragment {
                HStack {
                    Text(fragment.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(fragment.kind.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                    Spacer()
                    Text(fragment.enabled ? "已启用" : "已停用")
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(fragment.enabled ? .green : .secondary)
                }
                Text("更新于 \(Formatters.shortDate.string(from: fragment.updatedAt))")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                Text(fragment.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                    .padding(9)
                    .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 7))
            } else {
                Text("选择或新增覆写后，可在这里查看类型、状态与内容摘要。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .center)
            }
        }
    }

    private func overrideBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { enabled in
                var updated = store.settings
                updated[keyPath: keyPath] = enabled
                Task { await store.saveSettings(updated) }
            }
        )
    }

    private func ensureSelection() {
        guard store.configFragments.isEmpty == false else {
            selectedFragmentID = nil
            return
        }
        if let selectedFragmentID, store.configFragments.contains(where: { $0.id == selectedFragmentID }) {
            return
        }
        selectedFragmentID = store.configFragments.first?.id
    }
}
