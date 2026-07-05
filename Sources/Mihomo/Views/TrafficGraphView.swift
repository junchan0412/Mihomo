import SwiftUI

struct TrafficGraphView: View {
    var samples: [TrafficSample]

    var body: some View {
        Canvas { context, size in
            let values = samples.map { max($0.uploadRate, $0.downloadRate) }
            let maxValue = max(values.max() ?? 1, 1)
            let inset: CGFloat = 8
            let drawingSize = CGSize(width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))

            drawGrid(context: context, size: size, inset: inset)
            drawLine(
                context: context,
                size: drawingSize,
                inset: inset,
                maxValue: maxValue,
                values: samples.map(\.downloadRate),
                color: .blue
            )
            drawLine(
                context: context,
                size: drawingSize,
                inset: inset,
                maxValue: maxValue,
                values: samples.map(\.uploadRate),
                color: .green
            )
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                Label("下载", systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label("上传", systemImage: "arrow.up")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .padding(8)
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, inset: CGFloat) {
        var path = Path()
        for index in 0...3 {
            let y = inset + (size.height - inset * 2) * CGFloat(index) / 3
            path.move(to: CGPoint(x: inset, y: y))
            path.addLine(to: CGPoint(x: size.width - inset, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
    }

    private func drawLine(
        context: GraphicsContext,
        size: CGSize,
        inset: CGFloat,
        maxValue: Int64,
        values: [Int64],
        color: Color
    ) {
        guard values.count > 1 else { return }
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = inset + size.width * CGFloat(index) / CGFloat(values.count - 1)
            let ratio = CGFloat(value) / CGFloat(maxValue)
            let y = inset + size.height - min(max(ratio, 0), 1) * size.height
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
