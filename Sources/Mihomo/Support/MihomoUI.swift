import SwiftUI
import AppKit

enum MihomoUI {
    static let cornerRadius: CGFloat = 8
    static let pageHorizontalPadding: CGFloat = 26
    static let pageVerticalPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18

    enum Motion {
        static let quick: Animation = .easeOut(duration: 0.14)
        static let snappy: Animation = .snappy(duration: 0.22)
        static let soft: Animation = .easeInOut(duration: 0.18)
    }

    enum Fonts {
        static let pageTitle: Font = .title2.weight(.semibold)
        static let pageSubtitle: Font = .callout
        static let sectionTitle: Font = .headline
        static let body: Font = .body
        static let bodyMedium: Font = .body.weight(.medium)
        static let metric: Font = .title2.weight(.semibold)
        static let metricLarge: Font = .title.weight(.semibold)
        static let caption: Font = .caption
        static let sidebar: Font = .body
    }

    static var cardFill: Color {
        // Keep cards opaque so the same semantic surface renders identically
        // over every page and in both appearance modes. Translucent cards
        // composited over `.bar`, `.windowBackgroundColor`, and AppKit tables
        // were the source of the large light/dark color jumps.
        Color(nsColor: .controlBackgroundColor)
    }

    static var cardStroke: Color {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return Color(nsColor: .labelColor).opacity(0.48)
        }
        return Color(nsColor: .separatorColor).opacity(0.24)
    }

    static var pageBackground: Color {
        // Match the opaque card surface so the workspace and sidebar do not
        // introduce a separate gray plane behind the white content cards.
        cardFill
    }

    /// Keep the primary navigation column in the same visual plane as the workspace.
    /// Using the text background avoids the large material contrast of the system sidebar.
    static var sidebarBackground: Color {
        pageBackground
    }

    static var mutedFill: Color {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
        return Color(nsColor: .quaternaryLabelColor).opacity(0.18)
    }
}

extension View {
    func mihomoCard(padding: CGFloat = MihomoUI.cardPadding) -> some View {
        self
            .padding(padding)
            .background(
                MihomoUI.cardFill,
                in: RoundedRectangle(cornerRadius: MihomoUI.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MihomoUI.cornerRadius, style: .continuous)
                    .stroke(MihomoUI.cardStroke, lineWidth: 1)
            }
    }

    @ViewBuilder
    func mihomoInteractiveMotion(
        reduceMotion: Bool,
        animation: Animation = MihomoUI.Motion.soft
    ) -> some View {
        if reduceMotion {
            self.transaction { $0.animation = nil }
        } else {
            self.animation(animation, value: reduceMotion == false)
        }
    }
}
