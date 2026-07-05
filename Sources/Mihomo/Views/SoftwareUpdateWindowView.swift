import SwiftUI

struct SoftwareUpdateWindowView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            content
            Spacer()
            footer
        }
        .padding(22)
        .navigationTitle("软件更新")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.largeTitle)
                .foregroundStyle(iconColor)
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text("当前版本 \(store.currentAppVersion) (\(store.currentAppBuild))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let update = store.availableUpdate {
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(title: "可用版本", value: "\(update.version)\(update.build.map { " (\($0))" } ?? "")")
                if let publishedAt = update.publishedAt {
                    InfoRow(title: "发布时间", value: Formatters.shortDate.string(from: publishedAt))
                }
                InfoRow(title: "最低系统", value: update.minimumSystemVersion ?? "未声明")
                InfoRow(title: "校验", value: "SHA-256 与 Ed25519 manifest 签名")

                if let notes = update.notes, notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Text(notes)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        } else {
            Text(store.softwareUpdateStatus)
                .foregroundStyle(statusColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openURL(store.softwareUpdateSourceURL)
            } label: {
                Label("打开发布页", systemImage: "safari")
            }

            Spacer()

            Button {
                Task { await store.checkForSoftwareUpdate() }
            } label: {
                Label("检查 GitHub", systemImage: "arrow.clockwise")
            }

            Button {
                Task { await store.installSoftwareUpdate() }
            } label: {
                Label("安装并重启", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.availableUpdate == nil)
        }
    }

    private var title: String {
        if store.availableUpdate != nil { return "发现新版本" }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("正在") { return "正在检查更新" }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("失败") { return "更新检查失败" }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("最新") { return "已是最新版本" }
        return "软件更新"
    }

    private var iconName: String {
        if store.availableUpdate != nil { return "arrow.down.circle.fill" }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("失败") { return "xmark.octagon.fill" }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("最新") { return "checkmark.circle.fill" }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var iconColor: Color {
        if store.availableUpdate != nil { return .blue }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("失败") { return .red }
        if store.softwareUpdateStatus.localizedCaseInsensitiveContains("最新") { return .green }
        return .secondary
    }

    private var statusColor: Color {
        store.softwareUpdateStatus.localizedCaseInsensitiveContains("失败") ? .red : .secondary
    }
}

private struct InfoRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
