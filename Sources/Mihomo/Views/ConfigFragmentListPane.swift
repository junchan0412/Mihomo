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
    @State private var selectionAnchor: UUID?

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
            MihomoListSurface(minHeight: presentation.tableHeight, maxHeight: presentation.tableHeight) {
                ForEach(Array(presentation.visibleFragments.enumerated()), id: \.element.id) { offset, fragment in
                    fragmentRow(fragment, order: presentation.index(of: fragment).map { $0 + 1 } ?? offset + 1)
                }
            }
        }
    }

    private func fragmentRow(_ fragment: ConfigFragment, order: Int) -> some View {
        MihomoSelectableRow(
            isSelected: selectedFragmentIDs.contains(fragment.id),
            select: { select(fragment) },
            activate: { edit(fragment) }
        ) {
            HStack(spacing: 12) {
                Toggle(
                    "启用覆写",
                    isOn: Binding(
                        get: { fragment.enabled },
                        set: { enabled in
                            selectedFragmentIDs = [fragment.id]
                            selectionAnchor = fragment.id
                            actions.setEnabled([fragment], enabled)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)

                Text("\(order)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)

                Image(systemName: fragment.kind == .yaml ? "doc.text" : "curlybraces")
                    .foregroundStyle(fragment.enabled ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(fragment.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(fragment.enabled ? .primary : .secondary)
                            .lineLimit(1)
                        MihomoRowBadge(title: fragment.kind.title, color: fragment.kind == .yaml ? .blue : .orange)
                        MihomoRowBadge(title: fragment.isRemote ? "远程" : "本地", color: fragment.isRemote ? .purple : .secondary)
                        if fragment.enabled == false { MihomoRowBadge(title: "已停用") }
                    }
                    Text(ConfigFragmentTablePresentation.sourceText(for: fragment))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ConfigFragmentTablePresentation.scopeText(for: fragment))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                MihomoRowMetadata(
                    primary: Formatters.shortDate.string(from: fragment.updatedAt),
                    secondary: fragment.appliesGlobally ? "全部配置" : "指定配置"
                )

                MihomoRowActions {
                    Button {
                        selectedFragmentIDs = [fragment.id]
                        selectionAnchor = fragment.id
                        edit(fragment)
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("编辑覆写")

                    Menu {
                        Button(fragment.enabled ? "停用" : "启用") { actions.setEnabled([fragment], !fragment.enabled) }
                        if fragment.isRemote { Button("刷新") { actions.refresh([fragment]) } }
                        Button("快速查看") { actions.preview([fragment]) }
                        Button("复制内容") { copyContent([fragment]) }
                        Button("上移") { actions.move(fragment, -1) }
                            .disabled(canMove(fragment, offset: -1) == false)
                        Button("下移") { actions.move(fragment, 1) }
                            .disabled(canMove(fragment, offset: 1) == false)
                        Divider()
                        Button("删除", role: .destructive) { actions.delete([fragment]) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 18, height: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .help("更多操作")
                }
            }
        }
        .contextMenu {
            Button(fragment.enabled ? "停用" : "启用") { actions.setEnabled([fragment], !fragment.enabled) }
            Button("编辑") { edit(fragment) }
            if fragment.isRemote { Button("刷新") { actions.refresh([fragment]) } }
            Button("快速查看") { actions.preview([fragment]) }
            Button("复制内容") { copyContent([fragment]) }
            Button("上移") { actions.move(fragment, -1) }
                .disabled(canMove(fragment, offset: -1) == false)
            Button("下移") { actions.move(fragment, 1) }
                .disabled(canMove(fragment, offset: 1) == false)
            Divider()
            Button("删除", role: .destructive) { actions.delete([fragment]) }
        }
    }

    private func select(_ fragment: ConfigFragment) {
        let update = TableSelection.updated(
            selectedFragmentIDs,
            clicking: fragment.id,
            visibleIDs: presentation.visibleFragments.map(\.id),
            anchor: selectionAnchor,
            modifiers: NSEvent.modifierFlags
        )
        selectedFragmentIDs = update.selection
        selectionAnchor = update.anchor
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

    private func edit(_ fragment: ConfigFragment) {
        selectedFragmentIDs = [fragment.id]
        actions.edit(fragment)
    }

    private func copyContent(_ fragments: [ConfigFragment]) {
        guard let fragment = fragments.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fragment.content, forType: .string)
    }

    private func canMove(_ fragment: ConfigFragment, offset: Int) -> Bool {
        guard let index = presentation.index(of: fragment) else { return false }
        let destination = index + offset
        return presentation.allFragments.indices.contains(destination)
    }
}
