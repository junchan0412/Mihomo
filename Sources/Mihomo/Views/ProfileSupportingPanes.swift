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
        .frame(maxWidth: .infinity, alignment: .leading)
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
