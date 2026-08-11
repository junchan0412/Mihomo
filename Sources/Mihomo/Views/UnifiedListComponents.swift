import SwiftUI

enum MihomoListMetrics {
    static let metadataWidth: CGFloat = 132
    static let actionsWidth: CGFloat = 66
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 10
}

struct MihomoListSurface<Content: View>: View {
    var minHeight: CGFloat
    var maxHeight: CGFloat?
    @ViewBuilder var content: Content

    init(
        minHeight: CGFloat = 176,
        maxHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: MihomoUI.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MihomoUI.cornerRadius)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: MihomoUI.cornerRadius))
    }
}

struct MihomoSelectableRow<Content: View>: View {
    var isSelected: Bool
    var select: () -> Void
    var activate: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var isHovered = false

    init(
        isSelected: Bool,
        select: @escaping () -> Void,
        activate: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.select = select
        self.activate = activate
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, MihomoListMetrics.rowHorizontalPadding)
            .padding(.vertical, MihomoListMetrics.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) {
                select()
                activate?()
            }
            .onTapGesture {
                select()
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MihomoUI.cardStroke.opacity(0.7))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return MihomoUI.mutedFill
        }
        return .clear
    }
}

struct MihomoRowBadge: View {
    var title: String
    var color: Color = .secondary

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.11), in: Capsule())
    }
}

struct MihomoRowMetadata: View {
    var primary: String
    var secondary: String
    var primaryColor: Color = .secondary

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(primary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(primaryColor)
                .lineLimit(1)
            Text(secondary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(width: MihomoListMetrics.metadataWidth, alignment: .trailing)
    }
}

struct MihomoRowActions<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .frame(width: MihomoListMetrics.actionsWidth, alignment: .trailing)
    }
}
