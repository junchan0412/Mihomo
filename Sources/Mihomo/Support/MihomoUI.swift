import SwiftUI
import AppKit

enum MihomoUI {
    static let cornerRadius: CGFloat = 8
    static let pageHorizontalPadding: CGFloat = 26
    static let pageVerticalPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18

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
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    static var cardStroke: Color {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return Color(nsColor: .labelColor).opacity(0.58)
        }
        return Color(nsColor: .separatorColor).opacity(0.42)
    }

    static var pageBackground: Color {
        Color(nsColor: .textBackgroundColor)
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
}
