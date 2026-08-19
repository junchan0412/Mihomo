import AppKit
import SwiftUI

struct MenuBarStatusGlyph: View {
    let mode: String
    let isRunning: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBrandIcon(size: 19)
                .saturation(isRunning ? 1 : 0)
                .opacity(isRunning ? 1 : 0.52)

            Text(MenuBarPresentation.modeLetter(for: mode))
                .font(.system(size: 5.8, weight: .bold, design: .rounded))
                .foregroundStyle(MenuBarPresentation.modeTint(for: mode))
                .frame(width: 9, height: 9)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))
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
}

struct MenuBarGlassContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content
            }
        } else {
            content
        }
    }
}

struct MenuBarGlassSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.7)
                }
        }
    }
}

struct MenuBarStatusHeader: View {
    let mode: String
    let isRunning: Bool
    let title: String
    let uploadRate: String
    let downloadRate: String

    var body: some View {
        HStack(spacing: 12) {
            MenuBarStatusGlyph(mode: mode, isRunning: isRunning)
                .frame(width: 34, height: 34)
                .scaleEffect(1.15)
            VStack(alignment: .leading, spacing: 3) {
                Text("Mihomo")
                    .font(.headline.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(uploadRate)
                Text(downloadRate)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    @State private var isHovering = false

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
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.09) : .clear)
                .padding(.horizontal, 6)
        )
        .onHover { isHovering = $0 }
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
