import SwiftUI

struct NetworkHealthBadge: View {
    var health: NetworkTakeoverHealth

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(NetworkHealthPresentation.color(for: health))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(NetworkHealthPresentation.color(for: health).opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch health {
        case .ok: return "接管正常"
        case .warning: return "需要关注"
        case .failed: return "存在故障"
        case .inactive: return "未接管"
        case .unknown: return "状态未知"
        }
    }

    private var systemImage: String {
        switch health {
        case .ok: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .inactive: return "shield"
        case .unknown: return "questionmark.diamond"
        }
    }
}

enum NetworkHealthPresentation {
    static func color(for health: NetworkTakeoverHealth) -> Color {
        switch health {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        case .inactive: return .secondary
        case .unknown: return .gray
        }
    }
}
