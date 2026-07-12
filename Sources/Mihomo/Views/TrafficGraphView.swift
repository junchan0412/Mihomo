import SwiftUI

struct TrafficGraphView: View {
    var samples: [TrafficSample]

    var body: some View {
        let maxValue = max(samples.map { max($0.uploadRate, $0.downloadRate) }.max() ?? 1, 1)

        Canvas { context, size in
            let topInset: CGFloat = 30
            let bottomInset: CGFloat = 12
            let leftInset: CGFloat = 8
            let rightInset: CGFloat = 58
            let graphRect = CGRect(
                x: leftInset,
                y: topInset,
                width: max(size.width - leftInset - rightInset, 1),
                height: max(size.height - topInset - bottomInset, 1)
            )

            drawGrid(context: context, graphRect: graphRect, maxValue: maxValue)
            drawLine(
                context: context,
                graphRect: graphRect,
                maxValue: maxValue,
                values: samples.map(\.downloadRate),
                color: .blue
            )
            drawLine(
                context: context,
                graphRect: graphRect,
                maxValue: maxValue,
                values: samples.map(\.uploadRate),
                color: .green
            )
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 14) {
                MetricLegend(title: "下载", value: Formatters.rate(currentDownload), systemImage: "arrow.down", color: .blue)
                MetricLegend(title: "上传", value: Formatters.rate(currentUpload), systemImage: "arrow.up", color: .green)
                Spacer()
                Text("峰值 \(Formatters.rate(maxValue))")
                    .foregroundStyle(.secondary)
            }
            .font(MihomoUI.Fonts.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var currentDownload: Int64 {
        samples.last?.downloadRate ?? 0
    }

    private var currentUpload: Int64 {
        samples.last?.uploadRate ?? 0
    }

    private func drawGrid(context: GraphicsContext, graphRect: CGRect, maxValue: Int64) {
        var path = Path()
        for index in 0...3 {
            let y = graphRect.minY + graphRect.height * CGFloat(index) / 3
            path.move(to: CGPoint(x: graphRect.minX, y: y))
            path.addLine(to: CGPoint(x: graphRect.maxX, y: y))

            let value = Int64(Double(maxValue) * Double(3 - index) / 3.0)
            let text = Text(Formatters.rate(value))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            context.draw(text, at: CGPoint(x: graphRect.maxX + 8, y: y), anchor: .leading)
        }
        context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
    }

    private func drawLine(
        context: GraphicsContext,
        graphRect: CGRect,
        maxValue: Int64,
        values: [Int64],
        color: Color
    ) {
        guard values.count > 1 else { return }
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = graphRect.minX + graphRect.width * CGFloat(index) / CGFloat(values.count - 1)
            let ratio = CGFloat(value) / CGFloat(maxValue)
            let y = graphRect.maxY - min(max(ratio, 0), 1) * graphRect.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 2)
    }
}

private struct MetricLegend: View {
    var title: String
    var value: String
    var systemImage: String
    var color: Color

    var body: some View {
        Label {
            Text("\(title) \(value)")
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(color)
        .lineLimit(1)
    }
}
