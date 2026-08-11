import SwiftUI

struct ProfileListRow: View {
    var profile: ProfileItem
    var isActive: Bool
    var isSelected: Bool
    var select: () -> Void
    var activate: () -> Void
    var setActive: () -> Void
    var edit: () -> Void
    var refresh: () -> Void
    var preview: () -> Void
    var reveal: () -> Void
    var delete: () -> Void

    var body: some View {
        MihomoSelectableRow(
            isSelected: isSelected,
            select: select,
            activate: activate
        ) {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "doc.text")
                    .foregroundStyle(isActive ? Color.green : Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        MihomoRowBadge(title: profile.isRemote ? "远程" : "本地", color: profile.isRemote ? .blue : .secondary)
                        if isActive { MihomoRowBadge(title: "当前", color: .green) }
                    }
                    Text(profile.isRemote
                         ? URLDisplayText.redactingSensitiveComponents(profile.location)
                         : profile.fileName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(profile.location.isEmpty ? "未记录来源" : profile.location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                MihomoRowMetadata(
                    primary: Formatters.shortDate.string(from: profile.updatedAt),
                    secondary: profile.source == .remote ? "订阅配置" : "本地配置"
                )

                MihomoRowActions {
                    Button(action: setActive) {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(isActive ? "当前配置" : "启用配置")

                    Menu {
                        Button("编辑", action: edit)
                        if profile.isRemote { Button("刷新", action: refresh) }
                        Button("快速查看", action: preview)
                        Button("在 Finder 中显示", action: reveal)
                        Divider()
                        Button("删除", role: .destructive, action: delete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .help("更多操作")
                }
            }
        }
        .contextMenu {
            Button("启用", action: setActive)
            Button("编辑", action: edit)
            if profile.isRemote { Button("刷新", action: refresh) }
            Button("快速查看", action: preview)
            Divider()
            Button("删除", role: .destructive, action: delete)
        }
    }
}
