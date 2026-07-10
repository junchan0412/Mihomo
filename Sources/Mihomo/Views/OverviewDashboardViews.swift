import SwiftUI

struct OverviewSummaryMetric: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
            .frame(width: 1, height: 52)
            .padding(.horizontal, 12)
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
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.monochrome)
                .tint(tint)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
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
                    .font(.title2.weight(.bold))
            }
            Text(total)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
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
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .tint(tint)
            Text(value)
                .font(.title.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TrafficDistributionBar: View {
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
                    .fill(Color.cyan)
                    .frame(width: max(4, directWidth))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.indigo.opacity(0.75))
            }
        }
        .frame(height: 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
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
                    .font(.headline)
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
