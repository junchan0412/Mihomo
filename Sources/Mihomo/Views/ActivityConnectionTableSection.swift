import AppKit
import SwiftUI

struct ActivityConnectionTableSection: View {
    var moduleTab: ActivityModuleTab
    var rows: [ConnectionTableRow]
    @Binding var selection: Set<String>
    @Binding var showsConnectionDetail: Bool
    var hasConnections: Bool
    var hasSelectedActiveConnections: Bool
    var selectedConnection: ConnectionItem?
    var clearOrCloseAll: () -> Void
    var reload: () -> Void
    var requestCloseSelected: () -> Void
    var focusRule: (ConnectionItem) -> Void
    var focusResources: () -> Void
    var open: (ConnectionTableRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            connectionTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            actionBar
        }
    }

    @ViewBuilder
    private var connectionTable: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                moduleTab == .recent ? "暂无最近请求" : "暂无活动连接",
                systemImage: "network",
                description: Text(moduleTab == .recent ? "新的连接请求会显示在这里。" : "核心当前没有活动连接。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AppKitTable(
                rows: rows,
                selection: $selection,
                columns: [
                    .init(title: "ID", width: 74, textColor: { $0.statusColor }) { $0.idText },
                    .init(title: "时间", width: 86) { $0.timeText },
                    .init(title: "客户端", width: 150, image: { $0.clientIcon }) { $0.clientText },
                    .init(title: "规则", width: 220) { $0.ruleText },
                    .init(title: "策略", width: 150) { $0.policyText },
                    .init(title: "上传", width: 78) { $0.uploadText },
                    .init(title: "下载", width: 78) { $0.downloadText },
                    .init(title: "时长", width: 78) { $0.durationText },
                    .init(title: "方法", width: 82) { $0.methodText },
                    .init(title: "地址", width: 300) { $0.addressText }
                ],
                allowsMultipleSelection: true,
                onDoubleClick: open,
                onActivate: openFirstRow,
                onPreview: openFirstRow,
                onDelete: { _ in requestCloseSelected() },
                hasHorizontalScroller: true,
                borderType: .noBorder,
                contextMenuActions: contextMenuActions
            )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(moduleTab == .recent ? "清空记录" : "关闭全部", action: clearOrCloseAll)
                .disabled(hasConnections == false)

            Button("重新载入", action: reload)

            Button("关闭连接", action: requestCloseSelected)
                .disabled(hasSelectedActiveConnections == false)

            Button("查看规则") {
                guard let selectedConnection else { return }
                focusRule(selectedConnection)
            }
            .disabled(selectedConnection == nil)

            Button("Provider", action: focusResources)
                .disabled(selectedConnection == nil)

            Spacer()

            Button {
                showsConnectionDetail.toggle()
            } label: {
                Image(systemName: showsConnectionDetail ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(showsConnectionDetail ? "收起连接详情" : "展开连接详情")
            .disabled(selectedConnection == nil)
        }
        .font(MihomoUI.Fonts.bodyMedium)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MihomoUI.cardStroke)
                .frame(height: 1)
        }
    }

    private var contextMenuActions: [AppKitTableContextAction<ConnectionTableRow>] {
        [
            .init(
                "关闭所选连接",
                isDestructive: true,
                isEnabled: { rows in rows.contains(where: \.isActive) }
            ) { _ in
                requestCloseSelected()
            },
            .init("复制地址") { rows in
                let addresses = rows.map(\.addressText).filter { $0.isEmpty == false }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(addresses.joined(separator: "\n"), forType: .string)
            },
            .init("查看规则", isEnabled: { $0.count == 1 }) { rows in
                guard let connection = rows.first?.connection else { return }
                focusRule(connection)
            },
            .init("定位 Provider", isEnabled: { $0.count == 1 }) { _ in
                focusResources()
            }
        ]
    }

    private func openFirstRow(_ rows: [ConnectionTableRow]) {
        guard let row = rows.first else { return }
        open(row)
    }
}
