import SwiftUI

struct AppBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(backgroundGradient)
            MihomoSignalMark(gradient: markGradient)
                .padding(size * 0.19)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Mihomo")
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.09, green: 0.14, blue: 0.23), Color(red: 0.03, green: 0.04, blue: 0.08)]
                : [Color(red: 0.97, green: 0.99, blue: 1), Color(red: 0.86, green: 0.92, blue: 1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var markGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.34, green: 0.88, blue: 0.94), Color(red: 0.42, green: 0.64, blue: 1), Color(red: 0.65, green: 0.51, blue: 1)]
                : [.cyan, .blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MihomoSignalMark: View {
    let gradient: LinearGradient

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let barWidth = width * 0.18
            HStack(alignment: .bottom, spacing: width * 0.2) {
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: width * 0.48)
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: width * 0.86)
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(gradient)
                    .frame(width: barWidth, height: width * 0.66)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct MihomoMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
