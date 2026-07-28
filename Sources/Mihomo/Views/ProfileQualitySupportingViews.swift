import SwiftUI

extension ProfileQualityPane {
    enum ProfileQualitySection: String, CaseIterable, Identifiable {
        case overview
        case sources
        case layers

        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "质量总览"
            case .sources: return "字段来源"
            case .layers: return "合并层级"
            }
        }
        var systemImage: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .sources: return "point.3.connected.trianglepath.dotted"
            case .layers: return "square.stack.3d.up"
            }
        }
    }

    struct QualityPanel<Content: View>: View {
        var title: String
        var systemImage: String
        @ViewBuilder var content: () -> Content

        init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
            self.title = title
            self.systemImage = systemImage
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(MihomoUI.Fonts.bodyMedium)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    struct ProfileQualityIssueRow: View {
        var issue: ProfileQualityIssue

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(issue.title)
                            .font(MihomoUI.Fonts.bodyMedium)
                        Text(issue.source.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(sourceColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(sourceColor.opacity(0.12), in: Capsule())
                    }
                    Text(issue.detail)
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }

        private var icon: String {
            switch issue.severity {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        private var color: Color {
            switch issue.severity {
            case .info: return .secondary
            case .warning: return .orange
            case .error: return .red
            }
        }

        private var sourceColor: Color {
            switch issue.source {
            case .profile: return .blue
            case .appSettings: return .purple
            case .override: return .orange
            case .runtime: return .secondary
            }
        }
    }

    struct RuntimeInspectorCell: View {
        var item: RuntimeInspectorItem

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(item.value)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .lineLimit(1)
                }
                Text(item.detail)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(item.detail)
            }
        }
    }

    struct RuntimeSourceRow: View {
        var item: RuntimeConfigSourceItem

        var body: some View {
            ViewThatFits(in: .horizontal) {
                fullWidthRow
                compactRow
            }
            .padding(.vertical, 8)
        }

        private var fullWidthRow: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.path)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .frame(minWidth: 130, idealWidth: 150, maxWidth: 190, alignment: .leading)
                    .lineLimit(1)
                    .layoutPriority(1)

                Text(item.source)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(sourceColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sourceColor.opacity(0.12), in: Capsule())
                    .frame(width: 112, alignment: .leading)

                Text(item.value)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 160, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Text(shortDetail)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 140, idealWidth: 220, maxWidth: 360, alignment: .leading)
                    .help(item.detail)

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(item.detail)
                    .accessibilityLabel("字段说明")
                    .accessibilityValue(item.detail)
            }
        }

        private var compactRow: some View {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(item.path)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .lineLimit(1)

                    Text(item.source)
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(sourceColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(sourceColor.opacity(0.12), in: Capsule())

                    Spacer(minLength: 0)

                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(item.detail)
                        .accessibilityLabel("字段说明")
                        .accessibilityValue(item.detail)
                }

                Text(item.value)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(shortDetail)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(item.detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var shortDetail: String {
            item.detail.components(separatedBy: "；").first ?? item.detail
        }

        private var sourceColor: Color {
            switch item.source {
            case "YAML 覆写": return .purple
            case "JS Transform": return .orange
            case "Profile 配置": return .blue
            case "应用默认": return .secondary
            default: return .green
            }
        }
    }

    struct ConfigLayerCard: View {
        var layer: ConfigDiffLayer
        var priority: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(priority)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(layer.changed ? Color.accentColor : Color.secondary.opacity(0.18), in: Circle())
                        .foregroundStyle(layer.changed ? Color.white : Color.secondary)
                    Text(layer.name)
                        .font(MihomoUI.Fonts.bodyMedium)
                }
                Text(layer.summary.isEmpty ? "未参与" : layer.summary)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .padding(10)
            .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
