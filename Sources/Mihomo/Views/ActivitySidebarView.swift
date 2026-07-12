import SwiftUI

enum ConnectionSidebarGrouping: String, CaseIterable, Identifiable {
    case client
    case host

    var id: String { rawValue }

    var title: String {
        switch self {
        case .client: return "按客户端"
        case .host: return "按主机名"
        }
    }

    var sectionTitle: String {
        switch self {
        case .client: return "本地程序"
        case .host: return "远程主机"
        }
    }
}
enum ActivityModuleTab: String, CaseIterable, Identifiable {
    case recent
    case active
    case dns
    case traffic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近的请求"
        case .active: return "活动连接"
        case .dns: return "DNS"
        case .traffic: return "流量统计"
        }
    }

}

struct ActivityModuleTabs: View {
    var selection: ActivityModuleTab
    var select: (ActivityModuleTab) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ActivityModuleTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    Text(tab.title)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == tab ? MihomoUI.mutedFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MihomoUI.cardStroke, lineWidth: 1)
        }
    }
}

struct ActivityConnectionFilter: Identifiable, Hashable {
    static let allID = "all"

    var id: String
    var title: String
    var detail: String
    var count: Int
    var upload: Int64
    var download: Int64
    var kind: Kind
    var representative: ConnectionItem?

    enum Kind: Hashable {
        case all
        case client(String)
        case host(String)
    }

    static func items(for connections: [ConnectionItem], grouping: ConnectionSidebarGrouping) -> [ActivityConnectionFilter] {
        let uploadTotal = connections.reduce(Int64(0)) { $0 + $1.upload }
        let downloadTotal = connections.reduce(Int64(0)) { $0 + $1.download }
        let all = ActivityConnectionFilter(
            id: allID,
            title: grouping == .client ? "所有客户端" : "所有主机名",
            detail: "\(Formatters.bytes(downloadTotal)) ↓  \(Formatters.bytes(uploadTotal)) ↑",
            count: connections.count,
            upload: uploadTotal,
            download: downloadTotal,
            kind: .all,
            representative: connections.first
        )

        let grouped = Dictionary(grouping: connections) { connection in
            grouping == .client ? connection.clientGroupingKey : connection.hostGroupingKey
        }

        let filters = grouped.map { key, values in
            let upload = values.reduce(Int64(0)) { $0 + $1.upload }
            let download = values.reduce(Int64(0)) { $0 + $1.download }
            return ActivityConnectionFilter(
                id: "\(grouping.rawValue):\(key)",
                title: key,
                detail: "\(Formatters.bytes(download)) ↓  \(Formatters.bytes(upload)) ↑",
                count: values.count,
                upload: upload,
                download: download,
                kind: grouping == .client ? .client(key) : .host(key),
                representative: values.first
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return [all] + filters
    }

    func matches(_ connection: ConnectionItem) -> Bool {
        switch kind {
        case .all:
            return true
        case .client(let key):
            return connection.clientGroupingKey == key
        case .host(let key):
            return connection.hostGroupingKey == key
        }
    }
}

struct ActivityConnectionSidebar: View {
    @Binding var grouping: ConnectionSidebarGrouping
    @Binding var selectedFilterID: String
    var items: [ActivityConnectionFilter]

    private var selectedFilter: ActivityConnectionFilter? {
        items.first { $0.id == selectedFilterID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("分组", selection: $grouping) {
                ForEach(ConnectionSidebarGrouping.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 7) {
                Text("请求")
                    .font(MihomoUI.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)

                if let all = items.first {
                    ActivityConnectionFilterRow(
                        item: all,
                        grouping: grouping,
                        isSelected: selectedFilterID == all.id
                    ) {
                        selectedFilterID = all.id
                    }
                    .padding(.horizontal, 10)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(grouping.sectionTitle)
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.tertiary)
                        .imageScale(.small)
                }
                .padding(.horizontal, 18)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(items.dropFirst()) { item in
                            ActivityConnectionFilterRow(
                                item: item,
                                grouping: grouping,
                                isSelected: selectedFilterID == item.id
                            ) {
                                selectedFilterID = item.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .onChange(of: items) {
            guard selectedFilter == nil else { return }
            selectedFilterID = ActivityConnectionFilter.allID
        }
    }
}

private struct ActivityConnectionFilterRow: View {
    var item: ActivityConnectionFilter
    var grouping: ConnectionSidebarGrouping
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ActivityConnectionFilterIcon(item: item, grouping: grouping)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(MihomoUI.Fonts.bodyMedium)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(MihomoUI.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(item.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.42) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}

private struct ActivityConnectionFilterIcon: View {
    var item: ActivityConnectionFilter
    var grouping: ConnectionSidebarGrouping

    var body: some View {
        Group {
            if case .all = item.kind {
                Image(systemName: grouping == .client ? "person.3.fill" : "globe")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            } else if grouping == .client, let icon = item.representative?.processIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: grouping == .client ? "app.dashed" : "network")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .padding(2)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
