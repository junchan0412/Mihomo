import SwiftUI
import UniformTypeIdentifiers

struct ConfigFragmentListPresentation {
    var allFragments: [ConfigFragment]
    var visibleFragments: [ConfigFragment]
    var selectedFragments: [ConfigFragment]
    var selectedFragment: ConfigFragment?
    var tableHeight: CGFloat

    var columns: [AppKitTableColumn<ConfigFragment>] {
        ConfigFragmentTablePresentation.columns(for: allFragments)
    }

    var enableActionTitle: String {
        selectedFragments.contains(where: { !$0.enabled }) ? "启用" : "停用"
    }

    var enableActionSystemImage: String {
        selectedFragments.contains(where: { !$0.enabled }) ? "checkmark.circle" : "pause.circle"
    }

    static func make(
        fragments: [ConfigFragment],
        selectedIDs: Set<UUID>,
        searchText: String
    ) -> ConfigFragmentListPresentation {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var visibleFragments: [ConfigFragment] = []
        var selectedFragments: [ConfigFragment] = []
        visibleFragments.reserveCapacity(fragments.count)
        selectedFragments.reserveCapacity(min(selectedIDs.count, fragments.count))

        for fragment in fragments {
            if selectedIDs.contains(fragment.id) {
                selectedFragments.append(fragment)
            }
            if query.isEmpty
                || fragment.name.localizedCaseInsensitiveContains(query)
                || fragment.location.localizedCaseInsensitiveContains(query)
                || fragment.content.localizedCaseInsensitiveContains(query)
            {
                visibleFragments.append(fragment)
            }
        }

        let selectedFragment = selectedIDs.count == 1 ? selectedFragments.first : nil
        let visibleRows = max(visibleFragments.count, 1)
        let naturalHeight = 16 + CGFloat(visibleRows) * 78
        return ConfigFragmentListPresentation(
            allFragments: fragments,
            visibleFragments: visibleFragments,
            selectedFragments: selectedFragments,
            selectedFragment: selectedFragment,
            tableHeight: min(max(naturalHeight, 210), 420)
        )
    }

    func index(of fragment: ConfigFragment) -> Int? {
        allFragments.firstIndex { $0.id == fragment.id }
    }
}

enum ConfigFragmentTablePresentation {
    static func columns(for fragments: [ConfigFragment]) -> [AppKitTableColumn<ConfigFragment>] {
        var orderByID: [UUID: Int] = [:]
        for (offset, fragment) in fragments.enumerated() {
            orderByID[fragment.id] = offset + 1
        }

        return [
            AppKitTableColumn(title: "顺序", width: 60) { fragment in
                guard let order = orderByID[fragment.id] else { return "-" }
                return String(order)
            },
            .init(title: "状态", width: 72) { $0.enabled ? "启用" : "停用" },
            .init(title: "名称", width: 150) { $0.name },
            .init(title: "类型", width: 80) { $0.kind.title },
            .init(title: "来源", width: 190) { sourceText(for: $0) },
            .init(title: "范围", width: 110) { scopeText(for: $0) },
            .init(title: "更新", width: 140) { Formatters.shortDate.string(from: $0.updatedAt) }
        ]
    }

    static func sourceText(for fragment: ConfigFragment) -> String {
        if fragment.location.isEmpty { return fragment.isRemote ? "远程" : "手动创建" }
        if fragment.isRemote {
            return URLDisplayText.redactingSensitiveComponents(fragment.location)
        }
        return URL(fileURLWithPath: fragment.location).lastPathComponent
    }

    static func scopeText(for fragment: ConfigFragment) -> String {
        fragment.appliesGlobally ? "全部配置" : "\(fragment.profileIDs.count) 个配置"
    }
}

struct ConfigFragmentDropTargetOverlay: View {
    var isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                .padding(12)
        }
    }
}

extension UTType {
    static let mihomoOverrideYAML = UTType(filenameExtension: "yaml") ?? .plainText
    static let mihomoJavaScript = UTType(filenameExtension: "js") ?? .plainText
}
