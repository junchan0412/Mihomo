import SwiftUI

struct AppBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(backgroundGradient)
            MihomoMarkShape()
                .stroke(
                    markGradient,
                    style: StrokeStyle(
                        lineWidth: size * 0.105,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
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
