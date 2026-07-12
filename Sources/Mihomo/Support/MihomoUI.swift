import SwiftUI

enum MihomoUI {
    static let cornerRadius: CGFloat = 8
    static let pageHorizontalPadding: CGFloat = 26
    static let pageVerticalPadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18

    enum Fonts {
        static let pageTitle: Font = .system(size: 20, weight: .semibold)
        static let pageSubtitle: Font = .system(size: 12, weight: .medium)
        static let sectionTitle: Font = .system(size: 13, weight: .semibold)
        static let body: Font = .system(size: 13, weight: .regular)
        static let bodyMedium: Font = .system(size: 13, weight: .medium)
        static let metric: Font = .system(size: 20, weight: .semibold)
        static let metricLarge: Font = .system(size: 24, weight: .semibold)
        static let caption: Font = .system(size: 11, weight: .medium)
        static let sidebar: Font = .system(size: 13, weight: .medium)
    }

    static var cardFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.66)
    }

    static var cardStroke: Color {
        Color(nsColor: .separatorColor).opacity(0.28)
    }

    static var pageBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var mutedFill: Color {
        Color(nsColor: .quaternaryLabelColor).opacity(0.14)
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
