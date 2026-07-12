import AppKit
import SwiftUI

enum ActivityConnectionDetailTab: String, CaseIterable, Identifiable {
    case general
    case routing
    case address
    case process

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .routing: return "规则 & 链路"
        case .address: return "地址"
        case .process: return "进程"
        }
    }
}
struct ConnectionTableRow: Identifiable, Hashable {
    var connection: ConnectionItem
    var isActive = true

    var id: String { connection.id }

    var idText: String {
        let compact = connection.id.count > 6 ? String(connection.id.suffix(6)) : connection.id
        return "● \(compact)"
    }

    var timeText: String {
        guard let start = connection.start else { return "-" }
        return Formatters.logTime.string(from: start)
    }

    var clientText: String {
        connection.processName
    }

    var ruleText: String {
        let type = connection.ruleType.isEmpty ? connection.rule : connection.ruleType
        let payload = connection.rulePayload
        if payload.isEmpty || payload == "-" {
            return type.isEmpty ? "-" : type
        }
        return "\(type) \(payload)"
    }

    var policyText: String {
        let last = connection.chain.components(separatedBy: " -> ").last ?? ""
        return last.isEmpty ? "DIRECT" : last
    }

    var uploadText: String {
        Formatters.bytes(connection.upload)
    }

    var downloadText: String {
        Formatters.bytes(connection.download)
    }

    var durationText: String {
        guard let start = connection.start else { return "-" }
        return Self.durationText(from: Date().timeIntervalSince(start))
    }

    var methodText: String {
        let text = connection.metadataType.isEmpty ? connection.network : connection.metadataType
        return text.isEmpty ? "-" : text.uppercased()
    }

    var addressText: String {
        connection.remoteEndpoint
    }

    var statusColor: NSColor {
        isActive ? .systemGreen : .systemYellow
    }

    private static func durationText(from interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) m"
        }
        return "\(minutes / 60) h"
    }
}

struct ConnectionInlineDetailView: View {
    let connection: ConnectionItem
    @Binding var tab: ActivityConnectionDetailTab
    var close: (ConnectionItem) -> Void
    var focusRule: (ConnectionItem) -> Void
    var focusResources: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 158), spacing: 8, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            tabPicker
            detailGrid
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MihomoUI.pageBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MihomoUI.cardStroke)
                .frame(height: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                if let icon = connection.processIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                } else {
                    Image(systemName: "network")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.processName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ConnectionBadge(connection.displayMethod, tint: .green)
                    Text(connection.remoteEndpoint)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            ConnectionBadge("活跃", tint: .green)

            Button {
                close(connection)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("关闭此连接")
        }
    }

    private var tabPicker: some View {
        HStack {
            Picker("连接详情", selection: $tab) {
                ForEach(ActivityConnectionDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 410)

            Spacer()

            Button {
                focusRule(connection)
            } label: {
                Label("查看规则", systemImage: "list.bullet.rectangle")
            }
            .disabled(connection.ruleType.isEmpty && connection.rule.isEmpty)

            Button {
                focusResources()
            } label: {
                Label("Provider", systemImage: "shippingbox")
            }
        }
        .controlSize(.small)
        .font(MihomoUI.Fonts.bodyMedium)
    }

    @ViewBuilder
    private var detailGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(cards) { card in
                    ConnectionDetailCard(card: card)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var cards: [ConnectionDetailCardModel] {
        switch tab {
        case .general:
            return [
                .init(title: "HTTP", rows: [
                    ("方法", connection.displayMethod),
                    ("状态码", "N/A")
                ]),
                .init(title: "总流量", rows: [
                    ("上传", Formatters.bytes(connection.upload)),
                    ("下载", Formatters.bytes(connection.download))
                ]),
                .init(title: "规则", rows: [
                    ("规则", connection.ruleDisplay),
                    ("策略", connection.policyDisplay)
                ]),
                .init(title: "远程地址", rows: [
                    ("远程地址", connection.remoteEndpoint),
                    ("目标 IP", connection.destinationIPDisplay),
                    ("目标端口", connection.destinationPortDisplay)
                ]),
                .init(title: "客户端地址", rows: [
                    ("出站地址", connection.sourceIPDisplay),
                    ("客户端地址", connection.sourceEndpoint)
                ]),
                .init(title: "时间", rows: [
                    ("开始时间", connection.startText),
                    ("时长", connection.durationText)
                ]),
                .init(title: "进程", rows: [
                    ("名称", connection.processName),
                    ("路径", connection.processPathDisplay)
                ]),
                .init(title: "杂项", rows: [
                    ("连接 ID", connection.id),
                    ("主机名", connection.hostDisplay),
                    ("网络", connection.networkDisplay)
                ])
            ]
        case .routing:
            return [
                .init(title: "规则", rows: [
                    ("类型", connection.ruleTypeDisplay),
                    ("内容", connection.rulePayloadDisplay),
                    ("完整", connection.ruleDisplay)
                ]),
                .init(title: "策略链", rows: [
                    ("链路", connection.chainDisplay),
                    ("出站", connection.policyDisplay)
                ]),
                .init(title: "Provider", rows: [
                    ("类型", connection.ruleTypeDisplay),
                    ("名称", connection.rulePayloadDisplay)
                ])
            ]
        case .address:
            return [
                .init(title: "客户端地址", rows: [
                    ("源地址", connection.sourceEndpoint),
                    ("源 IP", connection.sourceIPDisplay),
                    ("源端口", connection.sourcePortDisplay)
                ]),
                .init(title: "远程地址", rows: [
                    ("主机名", connection.hostDisplay),
                    ("目标 IP", connection.destinationIPDisplay),
                    ("目标端口", connection.destinationPortDisplay)
                ]),
                .init(title: "远程目标", rows: [
                    ("地址", connection.remoteDestinationDisplay),
                    ("展示", connection.remoteEndpoint)
                ])
            ]
        case .process:
            return [
                .init(title: "客户端", rows: [
                    ("进程", connection.processName),
                    ("路径", connection.processPathDisplay)
                ]),
                .init(title: "连接", rows: [
                    ("ID", connection.id),
                    ("开始", connection.startText),
                    ("时长", connection.durationText)
                ]),
                .init(title: "传输", rows: [
                    ("上传", Formatters.bytes(connection.upload)),
                    ("下载", Formatters.bytes(connection.download)),
                    ("合计", Formatters.bytes(connection.upload + connection.download))
                ])
            ]
        }
    }
}

private struct ConnectionBadge: View {
    var title: String
    var tint: Color

    init(_ title: String, tint: Color) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct ConnectionDetailCardModel: Identifiable {
    var id: String { title }
    var title: String
    var rows: [(String, String)]
}

private struct ConnectionDetailCard: View {
    var card: ConnectionDetailCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.title)
                .font(MihomoUI.Fonts.caption)
                .foregroundStyle(.secondary)

            ForEach(card.rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(row.0)：")
                        .foregroundStyle(.secondary)
                    Text(row.1.isEmpty ? "-" : row.1)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
        .font(MihomoUI.Fonts.body)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(10)
        .background(MihomoUI.mutedFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
