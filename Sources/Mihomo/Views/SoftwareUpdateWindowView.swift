import SwiftUI

struct SoftwareUpdateWindowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    updateActivity
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
                    .font(.title.weight(.bold))
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
            .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(MihomoUI.cardStroke) }
        } else {
            ContentUnavailableView(title, systemImage: statusIcon, description: Text(store.softwareUpdateStatus))
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var updateActivity: some View {
        switch store.softwareUpdatePhase {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 10) {
                if let fractionCompleted = progress.fractionCompleted {
                    ProgressView(value: fractionCompleted)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                HStack {
                    Text(progress.transferDescription)
                    Spacer()
                    Text(Formatters.rate(progress.bytesPerSecond))
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("更新下载进度")
            .accessibilityValue(progress.transferDescription)

        case .checking, .verifying, .preparingNetwork, .preparingHelper, .installing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(store.softwareUpdatePhase.title)
                    .foregroundStyle(.secondary)
            }

        case .readyToRestart:
            Label("更新包已通过完整性与签名验证。重新启动后将完成替换。", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)

        case .failed, .cancelled:
            Label(store.softwareUpdateStatus, systemImage: statusIcon)
                .foregroundStyle(store.softwareUpdatePhase == .failed ? .red : .secondary)

        case .idle:
            EmptyView()
        }
    }

    private func releaseNotesText(_ notes: String?) -> String {
        let value = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "此版本包含稳定性、交互与安全更新。" : value
    }

    private var footer: some View {
        HStack {
            if store.softwareUpdatePhase == .readyToRestart {
                Button("丢弃更新") {
                    store.discardPreparedSoftwareUpdate()
                }
                .accessibilityLabel("丢弃已下载的更新")
            } else if store.availableUpdate == nil {
                Button("打开发布页") { openURL(store.softwareUpdateSourceURL) }
            }
            Spacer()
            switch store.softwareUpdatePhase {
            case .checking, .downloading, .verifying:
                Button(store.softwareUpdatePhase.cancellationTitle ?? "取消更新") {
                    store.cancelSoftwareUpdate()
                }
                .accessibilityLabel(store.softwareUpdatePhase.cancellationTitle ?? "取消更新")

            case .preparingNetwork, .preparingHelper, .installing:
                Button("正在完成") {}
                    .disabled(true)

            case .readyToRestart:
                Button("稍后") {
                    store.discardPreparedSoftwareUpdate()
                    dismiss()
                }
                Button("重新启动并安装") {
                    Task { await store.restartForPreparedSoftwareUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("重新启动 Mihomo 并安装更新")

            case .idle, .failed, .cancelled:
                Button(store.availableUpdate == nil ? "关闭" : "稍后") { dismiss() }
                Button(store.availableUpdate == nil ? "重新检查" : "下载更新") {
                    if store.availableUpdate == nil {
                        store.startSoftwareUpdateCheck()
                    } else {
                        store.startSoftwareUpdateDownload()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(store.availableUpdate == nil ? "重新检查软件更新" : "下载软件更新")
            }
        }
    }

    private func versionBadge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var title: String {
        if store.softwareUpdatePhase != .idle { return store.softwareUpdatePhase.title }
        if store.availableUpdate != nil { return "Mihomo 有新版本可用" }
        if store.softwareUpdateStatus.contains("失败") { return "无法检查更新" }
        if store.softwareUpdateStatus.contains("最新") { return "Mihomo 已是最新版本" }
        return "正在检查更新"
    }

    private var summary: String {
        if store.softwareUpdatePhase == .readyToRestart {
            return "更新已验证。请在方便时重新启动 Mihomo 完成安装。"
        }
        guard let update = store.availableUpdate else { return "当前版本 \(store.currentAppVersion)（\(store.currentAppBuild)）" }
        return "Mihomo \(update.version) 可下载。下载完成后会验证更新签名与文件完整性。"
    }

    private var statusIcon: String {
        switch store.softwareUpdatePhase {
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "xmark.circle"
        default:
            return "checkmark.circle"
        }
    }

}
