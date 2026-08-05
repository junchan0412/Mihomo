import AppKit
import SwiftUI

struct ConfigFragmentListActions {
    var setEnabled: ([ConfigFragment], Bool) -> Void
    var edit: (ConfigFragment) -> Void
    var refresh: ([ConfigFragment]) -> Void
    var refreshAll: () -> Void
    var isRefreshing: Bool
    var preview: ([ConfigFragment]) -> Void
    var move: (ConfigFragment, Int) -> Void
    var create: () -> Void
    var importLocal: () -> Void
    var importRemote: () -> Void
    var export: (ConfigFragment) -> Void
    var delete: ([ConfigFragment]) -> Void
}

struct ConfigFragmentListPane: View {
    var presentation: ConfigFragmentListPresentation
    @Binding var selectedFragmentIDs: Set<UUID>
    var actions: ConfigFragmentListActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("覆写列表")
                    .font(.headline)
                Spacer()
                Text("\(presentation.allFragments.count) 个覆写")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            tableContent
                .frame(height: presentation.tableHeight)

            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var tableContent: some View {
        if presentation.visibleFragments.isEmpty {
            ContentUnavailableView(
                presentation.allFragments.isEmpty ? "没有覆写" : "没有匹配的覆写",
                systemImage: presentation.allFragments.isEmpty ? "doc.badge.plus" : "magnifyingglass",
                description: Text(
                    presentation.allFragments.isEmpty
                        ? "可以新建、导入文件或从 URL 安装覆写。"
                        : "请尝试其他搜索词。"
                )
            )
        } else {
            AppKitTable(
                rows: presentation.visibleFragments,
                selection: $selectedFragmentIDs,
                columns: presentation.columns,
                allowsMultipleSelection: true,
                onDoubleClick: edit,
                onActivate: activateFirst,
                onPreview: actions.preview,
                onDelete: actions.delete,
                hasHorizontalScroller: false,
                allowsParentScrollPassthrough: true,
                contextMenuActions: contextMenuActions
            )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                let enabled = presentation.selectedFragments.contains { !$0.enabled }
                actions.setEnabled(presentation.selectedFragments, enabled)
            } label: {
                Label(presentation.enableActionTitle, systemImage: presentation.enableActionSystemImage)
            }
            .disabled(presentation.selectedFragments.isEmpty)

            Button {
                guard let fragment = presentation.selectedFragment else { return }
                actions.edit(fragment)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 18)
            }
            .help("编辑选中覆写")
            .disabled(presentation.selectedFragment == nil)

            Menu {
                Button("刷新所选", systemImage: "arrow.clockwise") {
                    actions.refresh(presentation.selectedFragments)
                }
                .disabled(presentation.selectedFragments.contains(where: \.isRemote) == false || actions.isRefreshing)

                Button("刷新所有远程订阅", systemImage: "arrow.triangle.2.circlepath", action: actions.refreshAll)
                    .disabled(actions.isRefreshing)
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .fixedSize()

            Menu {
                Button("新建覆写", systemImage: "doc.badge.plus", action: actions.create)
                Button("导入文件", systemImage: "square.and.arrow.down", action: actions.importLocal)
                Button("从 URL 安装", systemImage: "link.badge.plus", action: actions.importRemote)
            } label: {
                Label("添加", systemImage: "plus")
            }
            .fixedSize()

            Button {
                guard let fragment = presentation.selectedFragment else { return }
                actions.export(fragment)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 18)
            }
            .help("导出选中覆写")
            .disabled(presentation.selectedFragment == nil)

            Spacer()

            Button(role: .destructive) {
                actions.delete(presentation.selectedFragments)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 18)
            }
            .help("删除选中覆写")
            .disabled(presentation.selectedFragments.isEmpty)
        }
        .buttonStyle(.bordered)
    }

    private var contextMenuActions: [AppKitTableContextAction<ConfigFragment>] {
        [
            .init("启用", isEnabled: { $0.contains(where: { !$0.enabled }) }) {
                actions.setEnabled($0, true)
            },
            .init("停用", isEnabled: { $0.contains(where: \.enabled) }) {
                actions.setEnabled($0, false)
            },
            .init("编辑", isEnabled: { $0.count == 1 }) { fragments in
                guard let fragment = fragments.first else { return }
                edit(fragment)
            },
            .init("刷新", isEnabled: { $0.contains(where: \.isRemote) }) {
                actions.refresh($0)
            },
            .init("快速查看", action: actions.preview),
            .init("复制内容", isEnabled: { $0.count == 1 }) { copyContent($0) },
            .init("上移", isEnabled: canMoveUp) { fragments in
                guard let fragment = fragments.first else { return }
                actions.move(fragment, -1)
            },
            .init("下移", isEnabled: canMoveDown) { fragments in
                guard let fragment = fragments.first else { return }
                actions.move(fragment, 1)
            },
            .init("删除", isDestructive: true, isEnabled: { !$0.isEmpty }, action: actions.delete)
        ]
    }

    private func edit(_ fragment: ConfigFragment) {
        selectedFragmentIDs = [fragment.id]
        actions.edit(fragment)
    }

    private func activateFirst(_ fragments: [ConfigFragment]) {
        guard let fragment = fragments.first else { return }
        edit(fragment)
    }

    private func copyContent(_ fragments: [ConfigFragment]) {
        guard let fragment = fragments.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fragment.content, forType: .string)
    }

    private func canMoveUp(_ fragments: [ConfigFragment]) -> Bool {
        guard fragments.count == 1, let fragment = fragments.first,
              let index = presentation.index(of: fragment)
        else { return false }
        return index > 0
    }

    private func canMoveDown(_ fragments: [ConfigFragment]) -> Bool {
        guard fragments.count == 1, let fragment = fragments.first,
              let index = presentation.index(of: fragment)
        else { return false }
        return index < presentation.allFragments.count - 1
    }
}
