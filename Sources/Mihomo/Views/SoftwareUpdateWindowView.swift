import SwiftUI

struct SoftwareUpdateWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: AppStore
    @AppStorage("softwareUpdate.autoDownload") private var autoDownloadUpdates = false
    @AppStorage("softwareUpdate.skippedVersion") private var skippedVersion = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    releaseNotes
                }
                .padding(28)
            }

            Divider()
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 700, minHeight: 560)
        .navigationTitle("软件更新")
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            AppBrandIcon(size: 96)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 25, weight: .bold))
                Text(summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    versionBadge("当前 \(store.currentAppVersion)", color: .secondary)
                    if let update = store.availableUpdate {
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        versionBadge("可用 \(update.version)", color: .blue)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var releaseNotes: some View {
        if let update = store.availableUpdate {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("版本 \(update.version)").font(.title2.bold())
                    Spacer()
                    if let publishedAt = update.publishedAt {
                        Text(Formatters.shortDate.string(from: publishedAt))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text(releaseNotesText(update.notes))
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                HStack(spacing: 24) {
                    Label("最低 macOS \(update.minimumSystemVersion ?? "14.0")", systemImage: "laptopcomputer")
                    Label("SHA-256", systemImage: "checkmark.shield")
                    Label("Ed25519", systemImage: "signature")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(MihomoUI.cardStroke) }
        } else {
            ContentUnavailableView(title, systemImage: statusIcon, description: Text(store.softwareUpdateStatus))
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func releaseNotesText(_ notes: String?) -> String {
        let value = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "此版本包含稳定性、交互与安全更新。" : value
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("以后自动下载可用更新", isOn: $autoDownloadUpdates)
                .toggleStyle(.checkbox)

            HStack {
                if let update = store.availableUpdate {
                    Button("跳过此版本") {
                        skippedVersion = update.version
                        dismiss()
                    }
                } else {
                    Button("打开发布页") { openURL(store.softwareUpdateSourceURL) }
                }
                Spacer()
                Button(store.availableUpdate == nil ? "关闭" : "稍后提醒") { dismiss() }
                Button(store.availableUpdate == nil ? "重新检查" : "安装更新") {
                    if store.availableUpdate == nil {
                        Task { await store.checkForSoftwareUpdate() }
                    } else {
                        Task { await store.installSoftwareUpdate() }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func versionBadge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var title: String {
        if store.availableUpdate != nil { return "Mihomo 有新版本可用" }
        if store.softwareUpdateStatus.contains("失败") { return "无法检查更新" }
        if store.softwareUpdateStatus.contains("最新") { return "Mihomo 已是最新版本" }
        return "正在检查更新"
    }

    private var summary: String {
        guard let update = store.availableUpdate else { return "当前版本 \(store.currentAppVersion)（\(store.currentAppBuild)）" }
        return "Mihomo \(update.version) 已可下载。安装前会验证更新签名与文件完整性。"
    }

    private var statusIcon: String {
        store.softwareUpdateStatus.contains("失败") ? "exclamationmark.triangle" : "checkmark.circle"
    }
}
