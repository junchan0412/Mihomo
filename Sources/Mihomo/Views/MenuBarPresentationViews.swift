import AppKit
import SwiftUI

struct MenuBarStatusGlyph: View {
    let mode: String
    let isRunning: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
            MihomoMarkShape()
                .stroke(
                    foreground,
                    style: StrokeStyle(
                        lineWidth: 1.8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(3.2)

            Text(MenuBarPresentation.modeLetter(for: mode))
                .font(.system(size: 5.8, weight: .bold, design: .rounded))
                .foregroundStyle(MenuBarPresentation.modeTint(for: mode))
                .frame(width: 9, height: 9)
                .background(
                    Circle().fill(Color(nsColor: .controlBackgroundColor))
                )
                .offset(x: 1.5, y: 1.5)

            if isRunning == false {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4.5, height: 4.5)
                    .offset(x: -1, y: -1)
            }
        }
        .frame(width: 19, height: 19)
    }

    private var background: LinearGradient {
        LinearGradient(
            colors: isRunning
                ? MenuBarPresentation.modeGradient(for: mode)
                : [Color(nsColor: .quaternaryLabelColor).opacity(0.25), Color(nsColor: .tertiaryLabelColor).opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var foreground: LinearGradient {
        LinearGradient(
            colors: isRunning
                ? [Color.white.opacity(0.98), Color.white.opacity(0.78)]
                : [Color.secondary.opacity(0.9), Color.secondary.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MenuBarSectionHeader: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct MenuBarRowLabel: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var tint: Color = .primary
    var detail: String? = nil
    var rightBadge: String? = nil
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 132, alignment: .trailing)
            }

            if let rightBadge {
                MenuBarValueBadge(text: rightBadge)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct MenuBarValueBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.35), in: Capsule())
    }
}
