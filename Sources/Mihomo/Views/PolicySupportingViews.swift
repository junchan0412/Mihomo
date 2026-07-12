import AppKit
import SwiftUI

struct PolicyNodeRow: Identifiable, Hashable {
    var group: ProxyGroup
    var node: ProxyNode

    var id: String { "\(group.name)\u{1f}\(node.name)" }
    var isCurrent: Bool { group.now == node.name }
    var displayName: String { isCurrent ? "✓ \(node.name)" : node.name }

    var delayText: String {
        guard let delay = node.delay, delay > 0 else { return "-" }
        return "\(delay) ms"
    }
}

extension ProxyGroup {
    var isAutomaticURLTestGroup: Bool {
        type.lowercased().replacingOccurrences(of: "-", with: "").contains("urltest")
    }
}

struct PolicyStatusStrip: View {
    var groupCount: Int
    var nodeCount: Int
    var selectedGroup: ProxyGroup?
    var delayStatus: String
    var failureSummary: String
    var isOffline: Bool

    var body: some View {
        HStack(spacing: 16) {
            Label("\(groupCount) 组", systemImage: "switch.2")
            Label("\(nodeCount) 个候选", systemImage: "circle.grid.3x3")

            if let selectedGroup {
                Label("\(selectedGroup.name)：\(selectedGroup.now.isEmpty ? "-" : selectedGroup.now)", systemImage: "checkmark.circle")
                    .lineLimit(1)
            }

            Spacer()

            if isOffline {
                Label("离线配置预览，启动核心后可切换节点与测速", systemImage: "eye")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(delayStatus)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            if isOffline == false && failureSummary.isEmpty == false {
                Label(failureSummary, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PolicyStartupEmptyState: View {
    var isCoreRunning: Bool
    var coreStatus: String
    var activeProfileName: String?
    var tunEnabled: Bool
    var startOrRestartCore: () -> Void
    var refreshController: () -> Void
    var openProfiles: () -> Void
    var toggleTun: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: isCoreRunning ? "point.3.connected.trianglepath.dotted" : "power.circle")
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(title)
                    .font(MihomoUI.Fonts.pageTitle)
                Text(message)
                    .font(MihomoUI.Fonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    startOrRestartCore()
                } label: {
                    Label(isCoreRunning ? "重启核心" : "启动核心", systemImage: isCoreRunning ? "arrow.clockwise" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(activeProfileName == nil)

                Button {
                    refreshController()
                } label: {
                    Label("刷新 Controller", systemImage: "arrow.clockwise")
                }

                Button {
                    openProfiles()
                } label: {
                    Label("配置", systemImage: "doc.text")
                }

                Button {
                    toggleTun()
                } label: {
                    Label(tunEnabled ? "关闭 TUN" : "开启 TUN", systemImage: "lock.shield")
                }
            }

            Divider()
                .frame(maxWidth: 520)

            HStack(spacing: 22) {
                PolicyStartupFact(title: "核心", value: coreStatus)
                PolicyStartupFact(title: "配置", value: activeProfileName ?? "未选择")
                PolicyStartupFact(title: "TUN", value: tunEnabled ? "将随核心启用" : "关闭")
            }
            .frame(maxWidth: 620)

            Spacer(minLength: 0)
        }
        .padding(MihomoUI.pageHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }

    private var title: String {
        isCoreRunning ? "Controller 暂无策略组" : "mihomo 未启动"
    }

    private var message: String {
        if activeProfileName == nil {
            return "请选择或导入配置后启动核心。"
        }
        if isCoreRunning {
            return "当前运行状态没有返回可用策略组。"
        }
        return "启动核心后将在这里显示策略组和候选节点。"
    }
}

private struct PolicyStartupFact: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(MihomoUI.Fonts.bodyMedium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PolicySearchEmptyState: View {
    var query: String
    var resetSearch: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text("没有匹配的策略")
                    .font(MihomoUI.Fonts.pageTitle)
                Text("未找到包含“\(query)”的策略组或节点。")
                    .font(MihomoUI.Fonts.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                resetSearch()
            } label: {
                Label("清除搜索", systemImage: "xmark.circle")
            }

            Spacer(minLength: 0)
        }
        .padding(MihomoUI.pageHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(MihomoUI.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }
}
