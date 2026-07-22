import SwiftUI

struct OverviewSummaryMetric: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(MihomoUI.Fonts.metric)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewDivider: View {
    var body: some View {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 10)
    }
}

struct OverviewPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var tint: Color
    private let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(MihomoUI.Fonts.sectionTitle)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.monochrome)
                .tint(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .mihomoCard()
    }
}

struct TrafficRateLabel: View {
    var title: String
    var value: String
    var total: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .foregroundStyle(tint)
                Text(value)
                    .font(MihomoUI.Fonts.metric)
                    .contentTransition(.numericText())
            }
            Text(total)
                .font(MihomoUI.Fonts.bodyMedium)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }
}

struct OverviewSideStat: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(MihomoUI.Fonts.sectionTitle)
                .foregroundStyle(.secondary)
                .tint(tint)
            Text(value)
                .font(MihomoUI.Fonts.metricLarge)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(detail)
                .font(MihomoUI.Fonts.bodyMedium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .mihomoCard()
    }
}

struct TrafficDistributionBar: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var directBytes: Int64
    var proxyBytes: Int64

    private var total: Int64 {
        max(1, directBytes + proxyBytes)
    }

    var body: some View {
        GeometryReader { proxy in
            let directWidth = proxy.size.width * CGFloat(directBytes) / CGFloat(total)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(contrast == .increased ? Color.blue : Color.cyan)
                    .frame(width: max(4, directWidth))
                RoundedRectangle(cornerRadius: 4)
                    .fill(contrast == .increased ? Color.purple : Color.indigo.opacity(0.82))
            }
        }
        .frame(height: 12)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct DistributionLegend: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(MihomoUI.Fonts.sectionTitle)
            }
            Text(title)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)
        }
    }
}
