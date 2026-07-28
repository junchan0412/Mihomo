import SwiftUI

struct ProfilesHeader: View {
    var profileCount: Int
    var activeProfileName: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("管理本地配置、远程订阅与运行时覆写。当前 \(profileCount) 个配置，活跃 \(activeProfileName ?? "无")。")
                    .font(MihomoUI.Fonts.pageSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct ProfileStoragePane: View {
    var directory: URL
    var reveal: () -> Void
    var choose: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("配置存储路径")
                .font(.headline)
                .frame(width: 110, alignment: .trailing)

            Text(directory.path)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button(action: reveal) {
                Label("在 Finder 中显示", systemImage: "folder")
            }

            Button(action: choose) {
                Label("修改路径", systemImage: "folder.badge.gearshape")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }
}

struct ProfilesDetailPane: View {
    var profile: ProfileItem?
    var stats: ProfileStats?
    var report: ProfileQualityReport
    var editProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSummaryPane(
                profile: profile,
                stats: stats,
                editProfile: editProfile
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ProfileQualityPane(report: report)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct ProfileDropTargetOverlay: View {
    var isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                .padding(12)
        }
    }
}
